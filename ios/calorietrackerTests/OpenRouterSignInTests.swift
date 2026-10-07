import Foundation
import Testing
@testable import calorietracker

/// Cancel and overlapping attempts never end in a saved key. The key exchange is held
/// in flight by a gate, so its response arrives exactly when the test says.
@MainActor
struct OpenRouterSignInTests {
    @Test func cancelDuringTheExchangeSavesNothing() async {
        let gate = ExchangeGate()
        let saved = SavedKeys()
        let signIn = makeSignIn(gate, saved)
        #expect(signIn.beginPasteCode() != nil)

        let pending = Task { await signIn.submitPastedCode("code-a") }
        await waitUntil { gate.requestCount == 1 }
        #expect(signIn.phase == .exchanging)

        signIn.cancelPasteCode()
        #expect(signIn.phase == .idle)
        gate.open()

        #expect(await pending.value == nil)
        #expect(saved.keys.isEmpty)
        #expect(!signIn.isSignedIn)
        #expect(signIn.phase == .idle)
        #expect(!signIn.isAwaitingPastedCode)
        #expect(gate.cancelledWhenAnswered == [true])
    }

    @Test func aSecondCodeWhileExchangingIsIgnored() async {
        let gate = ExchangeGate()
        let saved = SavedKeys()
        let signIn = makeSignIn(gate, saved)
        _ = signIn.beginPasteCode()

        let first = Task { await signIn.submitPastedCode("code-a") }
        await waitUntil { gate.requestCount == 1 }

        let second = await signIn.submitPastedCode("code-b")
        #expect(second == nil)
        #expect(signIn.phase == .exchanging)
        #expect(gate.requestCount == 1)

        gate.open()
        #expect(await first.value == ExchangeGate.key(for: "code-a"))
        #expect(saved.keys == [ExchangeGate.key(for: "code-a")])
        #expect(signIn.isSignedIn)
        #expect(signIn.phase == .idle)
    }

    @Test func aCancelledExchangeAnsweringLateCannotOverwriteTheNextAttempt() async {
        let gate = ExchangeGate()
        let saved = SavedKeys()
        let signIn = makeSignIn(gate, saved)
        _ = signIn.beginPasteCode()

        let stale = Task { await signIn.submitPastedCode("code-a") }
        await waitUntil { gate.requestCount == 1 }
        signIn.cancelPasteCode()

        _ = signIn.beginPasteCode()
        let fresh = Task { await signIn.submitPastedCode("code-b") }
        await waitUntil { gate.requestCount == 2 }

        gate.open()
        #expect(await stale.value == nil)
        #expect(await fresh.value == ExchangeGate.key(for: "code-b"))
        #expect(saved.keys == [ExchangeGate.key(for: "code-b")])
        #expect(signIn.isSignedIn)
    }

    @Test func startingPasteCodeAgainInvalidatesTheExchangeInFlight() async {
        let gate = ExchangeGate()
        let saved = SavedKeys()
        let signIn = makeSignIn(gate, saved)
        _ = signIn.beginPasteCode()

        let pending = Task { await signIn.submitPastedCode("code-a") }
        await waitUntil { gate.requestCount == 1 }
        #expect(signIn.beginPasteCode() != nil)
        gate.open()

        #expect(await pending.value == nil)
        #expect(saved.keys.isEmpty)
        #expect(signIn.isAwaitingPastedCode)
        #expect(signIn.phase == .idle)
    }

    @Test func anUncancelledExchangeStillSignsIn() async {
        let gate = ExchangeGate()
        gate.open()
        let saved = SavedKeys()
        let signIn = makeSignIn(gate, saved)
        _ = signIn.beginPasteCode()

        #expect(await signIn.submitPastedCode("code-a") == ExchangeGate.key(for: "code-a"))
        #expect(saved.keys == [ExchangeGate.key(for: "code-a")])
        #expect(signIn.isSignedIn)
        #expect(!signIn.isAwaitingPastedCode)
        #expect(gate.cancelledWhenAnswered == [false])
    }

    // MARK: - Helpers

    private func makeSignIn(_ gate: ExchangeGate, _ saved: SavedKeys) -> OpenRouterSignIn {
        OpenRouterSignIn(
            isSignedIn: false,
            send: { request in try await gate.send(request) },
            saveKey: { key in
                saved.keys.append(key)
                return true
            }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
private final class SavedKeys {
    var keys: [String] = []
}

/// Holds every key exchange until `open()`, then answers 200 with a key made from the code.
/// It answers even when cancelled, like a response already on the wire.
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
private final class ExchangeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var requests = 0
    private var cancelled: [Bool] = []

    static func key(for code: String) -> String { "sk-or-v1-test-\(code)" }

    var requestCount: Int { locked { requests } }
    var cancelledWhenAnswered: [Bool] { locked { cancelled } }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let code = body?["code"] as? String ?? ""
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            arrive(continuation)
        }
        let wasCancelled = Task.isCancelled
        locked { cancelled.append(wasCancelled) }
        let json = try JSONSerialization.data(withJSONObject: ["key": Self.key(for: code)])
        return (json, 200)
    }

    func open() {
        let ready: [CheckedContinuation<Void, Never>] = locked {
            isOpen = true
            let all = waiters
            waiters = []
            return all
        }
        ready.forEach { $0.resume() }
    }

    private func arrive(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow: Bool = locked {
            requests += 1
            if isOpen { return true }
            waiters.append(continuation)
            return false
        }
        if resumeNow { continuation.resume() }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
