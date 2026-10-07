import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

/// Signs in to OpenRouter with OAuth PKCE and saves the key it returns as the OpenRouter
/// API key (`AIProviderSettings.saveOpenRouterSignInKey`), so requests use it unchanged.
/// OpenRouter is the only provider in the app that offers sign-in to third-party apps.
@Observable
final class OpenRouterSignIn {
    enum Phase: Equatable {
        case idle
        case signingIn
        case exchanging
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var isSignedIn: Bool
    /// True while the display-code fallback waits for a pasted code.
    private(set) var isAwaitingPastedCode = false
    /// After the first sign-in attempt, whatever its outcome, Paste code is offered.
    private(set) var hasTriedSignIn = false

    @ObservationIgnored private var pendingPKCE: OpenRouterOAuth.PKCE?
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private var anchor: OpenRouterPresentationAnchor?
    /// Bumped by every new attempt and by Cancel. Work from an older attempt that finishes
    /// late sees a different number and changes nothing: no saved key, no state.
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var exchangeTask: Task<(Data, Int), Error>?
    /// The browser sheet's continuation, so Cancel can end a sheet that never calls back.
    @ObservationIgnored private var pendingCallback: SignInContinuation?
    private let send: ExchangeTransport
    private let saveKey: @MainActor (String) -> Bool

    /// Posts the key exchange and returns the body and HTTP status.
    /// `@concurrent`: without it, approachable concurrency makes this type nonisolated(nonsending),
    /// and Swift 6.2 miscompiles calls to such a closure stored in a default-MainActor class: an
    /// ABI-changing convert_function drops the implicit actor argument, so the closure reads the
    /// actor where the URLRequest should be and crashes (OpenRouterSignInTests, CI run 37604526004).
    /// Running the network call off the main actor is what it should do anyway.
    typealias ExchangeTransport = @concurrent @Sendable (URLRequest) async throws -> (Data, Int)

    nonisolated static let urlSessionTransport: ExchangeTransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// `send` and `saveKey` are for tests; the defaults are the network and the Keychain.
    init(
        isSignedIn: Bool,
        send: @escaping ExchangeTransport = OpenRouterSignIn.urlSessionTransport,
        saveKey: @escaping @MainActor (String) -> Bool = { AIProviderSettings.saveOpenRouterSignInKey($0) }
    ) {
        self.isSignedIn = isSignedIn
        self.send = send
        self.saveKey = saveKey
    }

    /// The state Settings has now.
    static func live() -> OpenRouterSignIn {
        OpenRouterSignIn(isSignedIn: AIProviderSettings.isSignedInWithOpenRouter)
    }

    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Explicit nonisolated deinit: the synthesized main-actor-isolated deinit
    /// double-frees a TaskLocal scope on iOS <= 26.2 (swiftlang/swift#88036).
    /// Nothing here needs main-actor teardown.
    nonisolated deinit {}

    var isBusy: Bool {
        phase == .signingIn || phase == .exchanging
    }

    // MARK: - Browser sign-in

    /// Returns the new key, or nil when the user cancelled or sign-in failed (`phase` says which).
    func signIn() async -> String? {
        guard !isBusy else { return nil }
        let current = beginNewAttempt()
        hasTriedSignIn = true
        isAwaitingPastedCode = false
        phase = .signingIn
        do {
            let pkce = try Self.makePKCE()
            guard let url = OpenRouterOAuth.authorizationURL(pkce: pkce, mode: .callback) else {
                phase = .failed("Couldn't build the OpenRouter sign-in link.")
                return nil
            }
            let callback = try await authenticate(url: url)
            guard current == attempt else { return nil }
            switch OpenRouterOAuth.parseCallback(callback, expectedState: pkce.state) {
            case .code(let code):
                return await exchange(code: code, pkce: pkce, attempt: current)
            case .denied(let reason):
                phase = .failed("OpenRouter didn't authorize JL Physical: \(reason)")
            case .stateMismatch:
                phase = .failed("The sign-in response didn't match this request. Try again.")
            case .missingCode, .wrongCallback:
                phase = .failed("OpenRouter didn't send a sign-in code back. Use Paste code instead.")
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            guard current == attempt else { return nil }
            phase = .idle
        } catch {
            guard current == attempt else { return nil }
            phase = .failed("Sign-in didn't finish: \(error.localizedDescription) Use Paste code instead.")
        }
        session = nil
        anchor = nil
        pendingCallback = nil
        return nil
    }

    // MARK: - Paste code fallback

    /// Starts the display-code flow and returns the OpenRouter page to open in Safari.
    /// OpenRouter shows a code there; `submitPastedCode` exchanges it with this verifier.
    func beginPasteCode() -> URL? {
        beginNewAttempt()
        do {
            let pkce = try Self.makePKCE()
            pendingPKCE = pkce
            isAwaitingPastedCode = true
            phase = .idle
            return OpenRouterOAuth.authorizationURL(pkce: pkce, mode: .displayCode)
        } catch {
            phase = .failed("Couldn't start sign-in: \(error.localizedDescription)")
            return nil
        }
    }

    func submitPastedCode(_ text: String) async -> String? {
        guard !isBusy else { return nil }
        guard let pkce = pendingPKCE else {
            phase = .failed("Open OpenRouter from Paste code first, then paste the code it shows.")
            return nil
        }
        guard let code = OpenRouterOAuth.normalizedPastedCode(text) else {
            phase = .failed("That doesn't look like an OpenRouter code.")
            return nil
        }
        return await exchange(code: code, pkce: pkce, attempt: beginNewAttempt())
    }

    /// Stops whatever sign-in is running, including a key exchange already sent:
    /// its response is ignored, so Cancel never ends in a saved key.
    func cancelPasteCode() {
        beginNewAttempt()
        pendingPKCE = nil
        isAwaitingPastedCode = false
        phase = .idle
    }

    // MARK: - Sign out

    func signOut() {
        AIProviderSettings.signOutOfOpenRouter()
        isSignedIn = false
        cancelPasteCode()
    }

    // MARK: - Private

    /// Invalidates the previous attempt (cancelling its browser sheet and key exchange)
    /// and returns the new attempt's number.
    @discardableResult
    private func beginNewAttempt() -> Int {
        attempt += 1
        exchangeTask?.cancel()
        exchangeTask = nil
        session?.cancel()
        session = nil
        anchor = nil
        pendingCallback?.resume(with: .failure(CancellationError()))
        pendingCallback = nil
        return attempt
    }

    private func exchange(code: String, pkce: OpenRouterOAuth.PKCE, attempt current: Int) async -> String? {
        phase = .exchanging
        guard let request = OpenRouterOAuth.exchangeRequest(code: code, verifier: pkce.verifier) else {
            phase = .failed("Couldn't build the OpenRouter request.")
            return nil
        }
        let send = self.send
        let task = Task { try await send(request) }
        exchangeTask = task
        let result = await task.result
        guard current == attempt else { return nil }
        exchangeTask = nil
        do {
            let (data, status) = try result.get()
            let key = try OpenRouterOAuth.parseExchangeResponse(status: status, data: data)
            guard saveKey(key) else {
                phase = .failed("Signed in, but the key couldn't be saved to the Keychain. Try again.")
                return nil
            }
            pendingPKCE = nil
            isAwaitingPastedCode = false
            isSignedIn = true
            phase = .idle
            return key
        } catch let error as OpenRouterOAuth.ExchangeError {
            phase = .failed(error.message)
        } catch {
            phase = .failed("Couldn't reach OpenRouter: \(error.localizedDescription)")
        }
        return nil
    }

    private func authenticate(url: URL) async throws -> URL {
        guard let window = Self.keyWindow() else { throw SignInError.noWindow }
        let anchor = OpenRouterPresentationAnchor(window: window)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let once = SignInContinuation(continuation)
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(OpenRouterOAuth.callbackScheme)
            ) { @Sendable callbackURL, error in
                if let callbackURL {
                    once.resume(with: .success(callbackURL))
                } else {
                    once.resume(with: .failure(error ?? SignInError.noCallback))
                }
            }
            session.presentationContextProvider = anchor
            // Shared cookies: someone already signed in to OpenRouter in Safari isn't asked again.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            self.anchor = anchor
            self.pendingCallback = once
            if !session.start() {
                once.resume(with: .failure(SignInError.couldNotStart))
            }
        }
    }

    private static func makePKCE() throws -> OpenRouterOAuth.PKCE {
        OpenRouterOAuth.PKCE(
            verifierBytes: try randomBytes(OpenRouterOAuth.verifierByteCount),
            stateBytes: try randomBytes(OpenRouterOAuth.stateByteCount)
        )
    }

    private static func randomBytes(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw SignInError.randomUnavailable }
        return bytes
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    private nonisolated enum SignInError: LocalizedError {
        case noWindow
        case noCallback
        case couldNotStart
        case randomUnavailable

        var errorDescription: String? {
            switch self {
            case .noWindow: "The app has no window to show sign-in in."
            case .noCallback: "OpenRouter closed without a response."
            case .couldNotStart: "The sign-in sheet couldn't open."
            case .randomUnavailable: "The device couldn't generate a secure sign-in code."
            }
        }
    }
}

/// Shows the sign-in sheet over the app's key window. Nonisolated so it satisfies the
/// protocol whatever isolation the SDK gives it; it only hands back the window it was given.
nonisolated private final class OpenRouterPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

/// Resumes the sign-in continuation at most once: a failed `start()` and the session's own
/// completion handler can both report, and a second resume would crash.
/// `@unchecked Sendable`: the only mutable state is guarded by `lock`.
nonisolated private final class SignInContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
