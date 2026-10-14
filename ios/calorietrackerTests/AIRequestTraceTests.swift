import Foundation
import Testing
@testable import calorietracker

/// The trace turns provider attempts and HTTP responses into request log entries.
@MainActor
struct AIRequestTraceTests {
    /// Advances 250 ms on every read, so each recorded step has a known latency.
    private final class Clock {
        var current = Date(timeIntervalSince1970: 1_790_000_000)
        func tick() -> Date {
            current = current.addingTimeInterval(0.25)
            return current
        }
    }

    private func trace(_ kind: AIRequestLogEntry.Kind = .mealPhoto) -> (AIRequestTrace, Clock) {
        let clock = Clock()
        return (AIRequestTrace(kind: kind, now: clock.tick), clock)
    }

    @Test func parsedSuccessMarksTheOnlyAttemptParsed() {
        let (trace, _) = trace(.textFood)
        trace.beginAttempt(provider: "OpenRouter", model: "openai/gpt-5-mini")
        trace.recordResponse(provider: "OpenRouter", status: 200, body: Data(#"{"choices":[]}"#.utf8))
        let entries = trace.entries(outcome: .parsed)
        #expect(entries.count == 1)
        #expect(entries[0].parsed)
        #expect(entries[0].httpStatus == 200)
        #expect(entries[0].errorBody == nil)
        #expect(entries[0].kind == .textFood)
        #expect(entries[0].model == "openai/gpt-5-mini")
        // begin at t+0.5, closed at t+0.75.
        #expect(entries[0].latencyMs == 250)
    }

    @Test func unparseableAnswerIsNotParsedAndKeepsTheRedactedResponse() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "xAI Grok", model: "grok-4")
        trace.recordResponse(provider: "xAI Grok", status: 200, body: Data("I think it's pasta, key sk-0123456789abcdef".utf8))
        let entries = trace.entries(outcome: .failed("Could not understand the AI response."))
        #expect(entries.count == 1)
        #expect(!entries[0].parsed)
        #expect(entries[0].httpStatus == 200)
        let body = entries[0].errorBody ?? ""
        #expect(body.hasPrefix("Could not understand the AI response.\nResponse: I think it's pasta"))
        #expect(!body.contains("sk-0123456789abcdef"))
    }

    @Test func httpErrorKeepsTheRedactedBody() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "OpenAI", model: "gpt-5")
        trace.recordResponse(
            provider: "OpenAI",
            status: 401,
            body: Data(#"{"error":{"message":"Incorrect API key provided: sk-proj-abcdef0123456789","code":"invalid_api_key"}}"#.utf8)
        )
        trace.recordAttemptFailure("Your API key was rejected.")
        let entry = trace.entries(outcome: .failed("Your API key was rejected."))[0]
        #expect(entry.httpStatus == 401)
        #expect(!entry.parsed)
        #expect(entry.errorBody == #"{"error":{"message":"Incorrect API key provided: [REDACTED]","code":"invalid_api_key"}}"#)
    }

    @Test func retriedOverloadThatSucceedsClearsTheError() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "Google Gemini", model: "gemini-3-flash")
        trace.recordResponse(provider: "Google Gemini", status: 503, body: Data("overloaded".utf8))
        trace.recordResponse(provider: "Google Gemini", status: 200, body: Data("{}".utf8))
        let entry = trace.entries(outcome: .parsed)[0]
        #expect(entry.httpStatus == 200)
        #expect(entry.errorBody == nil)
        #expect(entry.parsed)
    }

    @Test func fallbackGivesOneEntryPerAttemptAndOnlyTheLastIsParsed() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "OpenRouter", model: "a/one")
        trace.recordResponse(provider: "OpenRouter", status: 402, body: Data(#"{"error":"Insufficient credits"}"#.utf8))
        trace.recordAttemptFailure("Out of credits")
        trace.beginAttempt(provider: "Google Gemini", model: "gemini-3-flash")
        trace.recordResponse(provider: "Google Gemini", status: 200, body: Data("{}".utf8))
        let entries = trace.entries(outcome: .parsed)
        #expect(entries.map(\.provider) == ["OpenRouter", "Google Gemini"])
        #expect(entries.map(\.parsed) == [false, true])
        #expect(entries.map(\.httpStatus) == [402, 200])
        #expect(entries[0].errorBody == #"{"error":"Insufficient credits"}"#)
        #expect(entries[0].timestamp < entries[1].timestamp)
    }

    @Test func failedRequestMarksNoAttemptParsed() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "OpenRouter", model: "a/one")
        trace.recordResponse(provider: "OpenRouter", status: 500, body: Data())
        trace.beginAttempt(provider: "Google Gemini", model: "gemini-3-flash")
        trace.recordResponse(provider: "Google Gemini", status: 429, body: Data("slow down".utf8))
        let entries = trace.entries(outcome: .failed("Both failed"))
        #expect(entries.map(\.parsed) == [false, false])
        #expect(entries[0].errorBody == "HTTP 500 with an empty body")
        #expect(entries[1].errorBody == "slow down")
    }

    @Test func attemptWithoutHTTPHasNoStatus() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: AIRequestTrace.hostedProviderName, model: nil)
        let entry = trace.entries(outcome: .parsed)[0]
        #expect(entry.httpStatus == nil)
        #expect(entry.parsed)
        #expect(entry.provider == "JL Physical AI (hosted)")
    }

    @Test func transportErrorIsRecorded() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "OpenAI", model: "gpt-5")
        trace.recordTransportError(provider: "OpenAI", URLError(.timedOut))
        let entry = trace.entries(outcome: .failed("The AI took too long to respond."))[0]
        #expect(entry.httpStatus == nil)
        #expect(entry.errorBody?.contains("NSURLErrorDomain -1001") == true)
    }

    @Test func failureBeforeAnyAttemptStillLogsOneEntry() {
        let (trace, _) = trace()
        let entries = trace.entries(outcome: .failed("No API key configured."))
        #expect(entries.count == 1)
        #expect(entries[0].provider == AIRequestTrace.notSentProviderName)
        #expect(entries[0].errorBody == "No API key configured.")
        #expect(!entries[0].parsed)
    }

    @Test func responseWithoutAnOpenAttemptStartsOne() {
        let (trace, _) = trace()
        trace.recordResponse(provider: "Anthropic Claude", status: 529, body: Data("overloaded".utf8))
        let entry = trace.entries(outcome: .failed("Overloaded"))[0]
        #expect(entry.provider == "Anthropic Claude")
        #expect(entry.httpStatus == 529)
    }

    @Test func lastAttemptReportsWhatAnswered() {
        let (trace, _) = trace()
        trace.beginAttempt(provider: "OpenRouter", model: "a/one")
        trace.beginAttempt(provider: "Google Gemini", model: "gemini-3-flash")
        #expect(trace.lastAttempt?.provider == "Google Gemini")
        #expect(trace.lastAttempt?.model == "gemini-3-flash")
    }

    @Test func registeredCredentialsNeverReachEntries() {
        let (trace, _) = trace()
        let secret = "opaque-credential-0001"
        trace.registerCredentials(AIRequestLogRedactor.credentials(headers: ["x-api-key": secret]))
        trace.beginAttempt(provider: "Anthropic", model: "claude")
        trace.recordResponse(provider: "Anthropic", status: 401, body: Data(#"{"error":{"message":"Key opaque-credential-0001 was revoked"}}"#.utf8))
        trace.beginAttempt(provider: "OpenRouter", model: "m")
        trace.recordResponse(provider: "OpenRouter", status: 200, body: Data("echo b3BhcXVlLWNyZWRlbnRpYWwtMDAwMQ==".utf8))
        let entries = trace.entries(outcome: .failed("Could not parse \(secret)"))
        #expect(entries.count == 2)
        for entry in entries {
            let text = entry.reportText(timeZone: TimeZone(identifier: "UTC")!)
            #expect(!text.contains(secret))
            #expect(!text.contains("b3BhcXVlLWNyZWRlbnRpYWwtMDAwMQ=="))
        }
        #expect(entries[0].errorBody?.contains(AIRequestLogRedactor.placeholder) == true)
    }
}
