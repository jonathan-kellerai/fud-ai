import Foundation

/// What a Settings → AI Providers test showed: who answered, how long it took, and either
/// the parsed answer or the error. Built from the same entries the request log stores.
nonisolated struct AIDiagnosticResult: Equatable, Sendable {
    nonisolated enum Outcome: Equatable, Sendable {
        /// `summary` is one line ("Chicken, rice & broccoli · 640 kcal"); `foods` lists the parts.
        case success(summary: String, foods: [String])
        /// `body` is the redacted provider body, nil when it would repeat `message`.
        case failure(status: Int?, message: String, body: String?)
    }

    let kind: AIRequestLogEntry.Kind
    let provider: String
    let model: String?
    let latencyMs: Int
    let outcome: Outcome

    var succeeded: Bool {
        if case .success = outcome { return true }
        return false
    }

    /// The last entry is the attempt whose answer counts; `latencyMs` is the whole test.
    static func make(
        kind: AIRequestLogEntry.Kind,
        entries: [AIRequestLogEntry],
        latencyMs: Int,
        failureMessage: String?,
        success: (summary: String, foods: [String])?
    ) -> AIDiagnosticResult {
        let last = entries.last
        let outcome: Outcome
        if let success, last?.parsed == true {
            outcome = .success(summary: success.summary, foods: success.foods)
        } else {
            let message = failureMessage ?? last?.errorBody ?? "The test didn't finish."
            let body = last?.errorBody.flatMap { $0 == message ? nil : $0 }
            outcome = .failure(status: last?.httpStatus, message: message, body: body)
        }
        return AIDiagnosticResult(
            kind: kind,
            provider: last?.provider ?? AIRequestTrace.notSentProviderName,
            model: last?.model,
            latencyMs: max(0, latencyMs),
            outcome: outcome
        )
    }

    /// "Chicken, rice & broccoli · 640 kcal", plus "Grilled chicken · 280 kcal" per ingredient.
    static func mealSummary(
        name: String,
        calories: Int,
        ingredients: [(name: String, calories: Int)]
    ) -> (summary: String, foods: [String]) {
        let foods = ingredients.isEmpty
            ? [name]
            : ingredients.map { "\($0.name) · \($0.calories) kcal" }
        return (summary: "\(name) · \(calories) kcal", foods: foods)
    }
}

nonisolated extension AIRequestLogEntry {
    nonisolated enum Severity: Hashable, Sendable {
        case ok
        case warning
        case error
    }

    /// The chip on each log row: OK, NOT PARSED (200 but unusable), the HTTP status, or NO REPLY.
    var statusLabel: String {
        if parsed { return "OK" }
        guard let httpStatus else { return "No reply" }
        return httpStatus == 200 ? "Not parsed" : "HTTP \(httpStatus)"
    }

    var severity: Severity {
        if parsed { return .ok }
        if httpStatus == 200 || httpStatus == 429 || httpStatus == 503 || httpStatus == 529 { return .warning }
        return .error
    }
}
