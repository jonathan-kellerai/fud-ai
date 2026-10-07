import Foundation

/// What happened during one meal identification request, attempt by attempt.
///
/// `GeminiService.routed` opens an attempt for each provider it tries, and
/// `GeminiService.makeRequest` (the one HTTP function for AI providers) reports every
/// response to the trace it was handed. `entries(outcome:)` turns that into redacted
/// request log entries, one per attempt. The trace is passed explicitly, never through a
/// task-local, so no task-local scope is open while app objects are released (swiftlang/swift#88036).
final class AIRequestTrace {
    nonisolated static let hostedProviderName = "JL Physical AI (hosted)"
    nonisolated static let notSentProviderName = "Not sent"

    struct Attempt: Equatable {
        var provider: String
        var model: String?
        var startedAt: Date
        var endedAt: Date?
        var httpStatus: Int?
        /// Redacted provider error body, transport error, or why this attempt was abandoned.
        var errorBody: String?
        /// Redacted body of the last 200, kept only to explain an answer that couldn't be parsed.
        var lastSuccessBody: String?
    }

    enum Outcome: Equatable {
        /// The last attempt's answer was parsed and used.
        case parsed
        /// Nothing usable came back. The message explains why, already user-readable.
        case failed(String)
    }

    let kind: AIRequestLogEntry.Kind
    let startedAt: Date
    private(set) var attempts: [Attempt] = []
    private let now: () -> Date
    /// Credentials this request sent, scrubbed from every body before it is kept.
    private var secrets: [String] = []

    init(kind: AIRequestLogEntry.Kind, now: @escaping () -> Date = Date.init) {
        self.kind = kind
        self.now = now
        self.startedAt = now()
    }

    /// Explicit nonisolated deinit: the synthesized main-actor-isolated deinit
    /// double-frees a TaskLocal scope on iOS <= 26.2 (swiftlang/swift#88036).
    /// Nothing here needs main-actor teardown.
    nonisolated deinit {}

    // MARK: - Recording

    /// The request's own credentials, so a server that echoes them back (raw or encoded)
    /// can't put them in the log. Call before the request is sent.
    func registerCredentials(_ values: [String]) {
        for value in values where !secrets.contains(value) {
            secrets.append(value)
        }
    }

    func beginAttempt(provider: String, model: String?) {
        closeLastAttempt()
        attempts.append(Attempt(provider: provider, model: model, startedAt: now()))
    }

    /// One HTTP response. A later 200 (after a retried 429/503) clears the earlier error.
    func recordResponse(provider: String, status: Int, body: Data) {
        ensureAttempt(provider: provider)
        let index = attempts.count - 1
        attempts[index].httpStatus = status
        if status == 200 {
            attempts[index].errorBody = nil
            attempts[index].lastSuccessBody = AIRequestLogRedactor.redactedBody(body, secrets: secrets)
        } else {
            let text = AIRequestLogRedactor.redactedBody(body, secrets: secrets)
            attempts[index].errorBody = text.isEmpty ? "HTTP \(status) with an empty body" : text
        }
    }

    /// The request never got an HTTP response (offline, timeout, TLS, cancelled).
    func recordTransportError(provider: String, _ error: Error) {
        ensureAttempt(provider: provider)
        let nsError = error as NSError
        let message = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        attempts[attempts.count - 1].errorBody = AIRequestLogRedactor.redactedBody(message, secrets: secrets)
    }

    /// Why the current attempt was abandoned, when the HTTP layer didn't already say.
    func recordAttemptFailure(_ message: String) {
        guard let last = attempts.indices.last else { return }
        if attempts[last].errorBody == nil {
            attempts[last].errorBody = failureText(message, for: attempts[last])
        }
    }

    // MARK: - Entries

    /// One entry per attempt, oldest first. Only the last attempt can be `parsed`.
    /// A request that failed before any attempt (hosted quota, no key) still gets one entry.
    func entries(outcome: Outcome) -> [AIRequestLogEntry] {
        closeLastAttempt()
        var all = attempts
        if all.isEmpty {
            all = [Attempt(provider: Self.notSentProviderName, model: nil, startedAt: startedAt, endedAt: now())]
        }
        let lastIndex = all.count - 1
        return all.enumerated().map { index, attempt in
            let isLast = index == lastIndex
            let parsed = isLast && outcome == .parsed
            var errorBody = attempt.errorBody
            if isLast, errorBody == nil, case .failed(let message) = outcome {
                errorBody = failureText(message, for: attempt)
            }
            let ended = attempt.endedAt ?? now()
            let latency = max(0, Int((ended.timeIntervalSince(attempt.startedAt) * 1_000).rounded()))
            return AIRequestLogEntry(
                timestamp: attempt.startedAt,
                provider: attempt.provider,
                model: attempt.model,
                kind: kind,
                httpStatus: attempt.httpStatus,
                latencyMs: latency,
                errorBody: errorBody,
                parsed: parsed
            )
        }
    }

    /// The last attempt, for screens that show what answered.
    var lastAttempt: Attempt? { attempts.last }

    // MARK: - Private

    private func ensureAttempt(provider: String) {
        if attempts.isEmpty || attempts[attempts.count - 1].endedAt != nil {
            attempts.append(Attempt(provider: provider, model: nil, startedAt: now()))
        }
    }

    private func closeLastAttempt() {
        guard let last = attempts.indices.last, attempts[last].endedAt == nil else { return }
        attempts[last].endedAt = now()
    }

    /// A 200 that couldn't be used is the case where the raw answer matters most.
    private func failureText(_ message: String, for attempt: Attempt) -> String {
        let redactedMessage = AIRequestLogRedactor.redactedBody(message, secrets: secrets)
        guard attempt.httpStatus == 200, let body = attempt.lastSuccessBody, !body.isEmpty else {
            return redactedMessage
        }
        return AIRequestLogRedactor.redactedBody("\(redactedMessage)\nResponse: \(body)", secrets: secrets)
    }
}
