import Foundation
import UIKit

/// Settings → AI Providers tests. Both run the real request path, are written to the
/// request log as tests, and return what to show.
enum AIDiagnostics {
    /// Small on purpose: the cheapest request that proves key, model and endpoint all work.
    static let connectionPrompt = "Reply with the single word OK."
    /// A drawn plate of grilled chicken, rice and broccoli. Generated for this app; no photo.
    static let sampleMealAssetName = "sample_meal_test"

    /// One plain-text prompt to the Photo & Text provider and model, through the same
    /// client and `makeRequest` that meal requests use. No router, no fallback.
    static func testConnection(store: AIRequestLogStore) async -> AIDiagnosticResult {
        let config = AIProviderSettings.currentConfig(requiresVision: true)
        let trace = AIRequestTrace(kind: .connectionTest)
        let started = Date()
        trace.beginAttempt(provider: config.provider.displayName, model: config.model)
        var failureMessage: String?
        do {
            if config.provider.requiresAPIKey, config.apiKey == nil {
                throw GeminiService.AnalysisError.noAPIKey
            }
            _ = try await AIRouteEnvironment.current.dispatch(config, connectionPrompt, [], false, trace)
        } catch {
            failureMessage = GeminiService.requestLogMessage(for: error)
        }
        var success: (summary: String, foods: [String])?
        if failureMessage == nil {
            success = (summary: "Connected. The model answered.", foods: [String]())
        }
        return finish(trace, started: started, failureMessage: failureMessage, success: success, store: store)
    }

    /// The bundled sample plate through `GeminiService.analyzeFood(image:)`, the same path
    /// as a meal photo, including the router and any configured fallback.
    static func testMealPhoto(store: AIRequestLogStore) async -> AIDiagnosticResult {
        let trace = AIRequestTrace(kind: .sampleMealPhoto)
        let started = Date()
        guard let image = UIImage(named: sampleMealAssetName) else {
            return finish(
                trace,
                started: started,
                failureMessage: "The sample meal image is missing from this build.",
                success: nil,
                store: store
            )
        }
        do {
            let analysis = try await GeminiService.analyzeFood(image: image, trace: trace)
            let meal = AIDiagnosticResult.mealSummary(
                name: analysis.name,
                calories: analysis.calories,
                ingredients: analysis.ingredients.map { (name: $0.name, calories: $0.calories) }
            )
            return finish(trace, started: started, failureMessage: nil, success: meal, store: store)
        } catch {
            return finish(
                trace,
                started: started,
                failureMessage: GeminiService.requestLogMessage(for: error),
                success: nil,
                store: store
            )
        }
    }

    private static func finish(
        _ trace: AIRequestTrace,
        started: Date,
        failureMessage: String?,
        success: (summary: String, foods: [String])?,
        store: AIRequestLogStore
    ) -> AIDiagnosticResult {
        let outcome: AIRequestTrace.Outcome
        if let failureMessage {
            outcome = .failed(failureMessage)
        } else {
            outcome = .parsed
        }
        let entries = trace.entries(outcome: outcome)
        store.append(entries)
        return AIDiagnosticResult.make(
            kind: trace.kind,
            entries: entries,
            latencyMs: Int((Date().timeIntervalSince(started) * 1_000).rounded()),
            failureMessage: failureMessage,
            success: success
        )
    }
}
