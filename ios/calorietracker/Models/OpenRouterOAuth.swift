import CryptoKit
import Foundation

/// OpenRouter's OAuth PKCE flow as plain values: the verifier and challenge, the sign-in URL,
/// callback parsing, and the code-for-key exchange.
/// Source: https://openrouter.ai/docs/guides/overview/auth/oauth (RFC 7636 S256).
/// The browser session, random bytes and network calls live in `OpenRouterSignIn`.
nonisolated enum OpenRouterOAuth {
    /// Already registered in Info.plist for widgets and shared meals. Neither handler uses this host.
    static let callbackScheme = "fudai"
    static let callbackHost = "openrouter-callback"
    static let callbackURLString = "\(callbackScheme)://\(callbackHost)"
    static let authorizeURLString = "https://openrouter.ai/auth"
    static let exchangeURLString = "https://openrouter.ai/api/v1/auth/keys"
    /// Prefills the name of the key OpenRouter creates in display-code mode.
    static let keyLabel = "JL Physical"

    // MARK: - PKCE

    nonisolated struct PKCE: Equatable, Sendable {
        let verifier: String
        let challenge: String
        /// Returned unchanged on the callback; a mismatch means the response isn't ours.
        let state: String

        init(verifier: String, state: String) {
            self.verifier = verifier
            self.challenge = OpenRouterOAuth.challenge(for: verifier)
            self.state = state
        }

        /// 32 random bytes give a 43-character verifier, the RFC 7636 minimum length.
        init(verifierBytes: [UInt8], stateBytes: [UInt8]) {
            self.init(
                verifier: OpenRouterOAuth.base64URL(Data(verifierBytes)),
                state: OpenRouterOAuth.base64URL(Data(stateBytes))
            )
        }
    }

    static let verifierByteCount = 32
    static let stateByteCount = 16

    /// S256: BASE64URL(SHA256(ASCII(verifier))), no padding (RFC 7636 §4.2).
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Sign-in URL

    nonisolated enum Mode: Sendable {
        /// OpenRouter redirects to `fudai://openrouter-callback?code=…&state=…`.
        case callback
        /// No callback: OpenRouter shows the code on screen and the user pastes it.
        case displayCode
    }

    static func authorizationURL(pkce: PKCE, mode: Mode) -> URL? {
        var items: [(String, String)] = []
        switch mode {
        case .callback:
            items.append(("callback_url", callbackURLString))
        case .displayCode:
            break
        }
        items.append(("code_challenge", pkce.challenge))
        items.append(("code_challenge_method", "S256"))
        switch mode {
        case .callback:
            items.append(("state", pkce.state))
        case .displayCode:
            items.append(("key_label", keyLabel))
        }
        let query = items.map { "\($0.0)=\(percentEncoded($0.1))" }.joined(separator: "&")
        return URL(string: "\(authorizeURLString)?\(query)")
    }

    /// Only RFC 3986 unreserved characters pass, so the callback URL arrives intact.
    static func percentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // `alphanumerics` includes non-ASCII letters; keep ASCII only.
        return value.unicodeScalars.map { scalar -> String in
            if scalar.isASCII, allowed.contains(scalar) { return String(scalar) }
            return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }

    // MARK: - Callback

    nonisolated enum CallbackResult: Equatable, Sendable {
        case code(String)
        /// The user declined, or OpenRouter reported an error. Carries its description.
        case denied(String)
        case stateMismatch
        case missingCode
        /// Not a `fudai://openrouter-callback` URL.
        case wrongCallback
    }

    /// OpenRouter returns `state` on success only, so an error is read before state is checked.
    static func parseCallback(_ url: URL, expectedState: String) -> CallbackResult {
        guard url.scheme?.lowercased() == callbackScheme, url.host?.lowercased() == callbackHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .wrongCallback }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let error = value("error") {
            let description = value("error_description").flatMap { $0.isEmpty ? nil : $0 } ?? error
            return .denied(description)
        }
        guard value("state") == expectedState else { return .stateMismatch }
        guard let code = value("code")?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            return .missingCode
        }
        return .code(code)
    }

    /// Accepts a bare code, or a whole pasted callback URL that carries `code=`.
    static func normalizedPastedCode(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("code="),
           let components = URLComponents(string: trimmed),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return trimmed
    }

    // MARK: - Exchange

    private nonisolated struct ExchangeBody: Encodable {
        let code: String
        let code_verifier: String
        let code_challenge_method: String
    }

    static func exchangeRequest(code: String, verifier: String) -> URLRequest? {
        guard let url = URL(string: exchangeURLString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try? encoder.encode(
            ExchangeBody(code: code, code_verifier: verifier, code_challenge_method: "S256")
        )
        return request
    }

    nonisolated enum ExchangeError: Error, Equatable, Sendable {
        case rejected(status: Int, message: String)
        case malformedResponse

        /// Shown under the sign-in button. Never contains a key.
        var message: String {
            switch self {
            case .rejected(let status, let message):
                switch status {
                case 403: return "OpenRouter rejected the sign-in code (it may have expired). Sign in again. \(message)"
                default: return "OpenRouter couldn't finish sign-in (HTTP \(status)). \(message)"
                }
            case .malformedResponse:
                return "OpenRouter's reply didn't include a key. Sign in again."
            }
        }
    }

    static func parseExchangeResponse(status: Int, data: Data) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let error = json?["error"]
            let raw = (error as? [String: Any])?["message"] as? String
                ?? error as? String
                ?? json?["message"] as? String
                ?? ""
            throw ExchangeError.rejected(status: status, message: AIRequestLogRedactor.redact(raw))
        }
        guard let key = (json?["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ExchangeError.malformedResponse
        }
        return key
    }

    // MARK: - Signed-in marker

    /// SHA-256 hex of a key. Settings store this, never the key, to know the saved OpenRouter
    /// key is the one sign-in created; pasting another key makes it stop matching.
    static func keyFingerprint(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
