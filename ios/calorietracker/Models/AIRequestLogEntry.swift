import Foundation

/// One attempt at a meal identification request against one AI provider, as kept in the
/// on-device request log. Text fields are redacted before an entry is built. Nothing here
/// is uploaded.
nonisolated struct AIRequestLogEntry: Codable, Hashable, Identifiable, Sendable {
    nonisolated enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case mealPhoto
        case textFood
        case connectionTest
        case sampleMealPhoto

        var title: String {
            switch self {
            case .mealPhoto: "Meal photo"
            case .textFood: "Text food"
            case .connectionTest: "Connection test"
            case .sampleMealPhoto: "Sample meal photo"
            }
        }
    }

    var id: UUID
    var timestamp: Date
    /// Provider display name, e.g. "OpenRouter" or "JL Physical AI (hosted)".
    var provider: String
    var model: String?
    var kind: Kind
    /// Status of the last HTTP response in this attempt. Nil when none arrived:
    /// on-device models, hosted mode, no key, or a network failure.
    var httpStatus: Int?
    var latencyMs: Int
    /// Redacted provider error body, or the error message when there was no body.
    var errorBody: String?
    /// True only when this attempt produced a parsed result.
    var parsed: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        provider: String,
        model: String?,
        kind: Kind,
        httpStatus: Int?,
        latencyMs: Int,
        errorBody: String?,
        parsed: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.kind = kind
        self.httpStatus = httpStatus
        self.latencyMs = latencyMs
        self.errorBody = errorBody
        self.parsed = parsed
    }

    /// True when the attempt answered and its answer was used.
    var succeeded: Bool { parsed }

    /// Plain-text form for Copy and Share. Already redacted.
    func reportText(timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var lines = [
            "JL Physical AI request",
            "Time: \(formatter.string(from: timestamp))",
            "Kind: \(kind.title)",
            "Provider: \(provider)",
            "Model: \(model ?? "unknown")",
            "HTTP status: \(httpStatus.map(String.init) ?? "none")",
            "Latency: \(latencyMs) ms",
            "Parsed: \(parsed ? "yes" : "no")",
        ]
        if let errorBody, !errorBody.isEmpty {
            lines.append("Error:")
            lines.append(errorBody)
        }
        return lines.joined(separator: "\n")
    }
}
