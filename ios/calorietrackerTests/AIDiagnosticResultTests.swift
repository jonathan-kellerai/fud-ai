import Foundation
import Testing
@testable import calorietracker

/// What the AI Providers test buttons show, built from request log entries.
struct AIDiagnosticResultTests {
    private func entry(
        provider: String = "OpenRouter",
        model: String? = "openai/gpt-5-mini",
        status: Int?,
        body: String? = nil,
        parsed: Bool
    ) -> AIRequestLogEntry {
        AIRequestLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_790_000_000),
            provider: provider,
            model: model,
            kind: .sampleMealPhoto,
            httpStatus: status,
            latencyMs: 900,
            errorBody: body,
            parsed: parsed
        )
    }

    @Test func successShowsTheParsedMealFromTheLastAttempt() {
        let meal = AIDiagnosticResult.mealSummary(
            name: "Chicken, rice & broccoli",
            calories: 640,
            ingredients: [("Grilled chicken", 280), ("White rice", 260), ("Broccoli", 100)]
        )
        let result = AIDiagnosticResult.make(
            kind: .sampleMealPhoto,
            entries: [
                entry(status: 402, body: "credits", parsed: false),
                entry(provider: "Google Gemini", model: "gemini-3-flash", status: 200, parsed: true),
            ],
            latencyMs: 2_345,
            failureMessage: nil,
            success: meal
        )
        #expect(result.provider == "Google Gemini")
        #expect(result.model == "gemini-3-flash")
        #expect(result.latencyMs == 2_345)
        #expect(result.succeeded)
        #expect(result.outcome == .success(
            summary: "Chicken, rice & broccoli · 640 kcal",
            foods: ["Grilled chicken · 280 kcal", "White rice · 260 kcal", "Broccoli · 100 kcal"]
        ))
    }

    @Test func mealWithoutIngredientsListsItsName() {
        let meal = AIDiagnosticResult.mealSummary(name: "Oatmeal", calories: 150, ingredients: [])
        #expect(meal.summary == "Oatmeal · 150 kcal")
        #expect(meal.foods == ["Oatmeal"])
    }

    @Test func failureShowsStatusMessageAndRedactedBody() {
        let result = AIDiagnosticResult.make(
            kind: .connectionTest,
            entries: [entry(status: 401, body: #"{"error":{"message":"No auth credentials found"}}"#, parsed: false)],
            latencyMs: 180,
            failureMessage: "Your API key was rejected.",
            success: nil
        )
        #expect(!result.succeeded)
        #expect(result.outcome == .failure(
            status: 401,
            message: "Your API key was rejected.",
            body: #"{"error":{"message":"No auth credentials found"}}"#
        ))
    }

    @Test func failureWithoutHTTPDoesNotRepeatTheMessage() {
        let result = AIDiagnosticResult.make(
            kind: .connectionTest,
            entries: [entry(status: nil, body: "No API key configured.", parsed: false)],
            latencyMs: 0,
            failureMessage: "No API key configured.",
            success: nil
        )
        #expect(result.outcome == .failure(status: nil, message: "No API key configured.", body: nil))
    }

    @Test func noEntriesStillGiveAResult() {
        let result = AIDiagnosticResult.make(kind: .connectionTest, entries: [], latencyMs: -5, failureMessage: nil, success: nil)
        #expect(result.provider == AIRequestTrace.notSentProviderName)
        #expect(result.latencyMs == 0)
        #expect(result.outcome == .failure(status: nil, message: "The test didn't finish.", body: nil))
    }

    @Test func statusChipsNameWhatHappened() {
        #expect(entry(status: 200, parsed: true).statusLabel == "OK")
        #expect(entry(status: nil, parsed: true).statusLabel == "OK")
        #expect(entry(status: 200, parsed: false).statusLabel == "Not parsed")
        #expect(entry(status: 401, parsed: false).statusLabel == "HTTP 401")
        #expect(entry(status: nil, parsed: false).statusLabel == "No reply")
        #expect(entry(status: 200, parsed: true).severity == .ok)
        #expect(entry(status: 200, parsed: false).severity == .warning)
        #expect(entry(status: 429, parsed: false).severity == .warning)
        #expect(entry(status: 401, parsed: false).severity == .error)
        #expect(entry(status: nil, parsed: false).severity == .error)
    }
}
