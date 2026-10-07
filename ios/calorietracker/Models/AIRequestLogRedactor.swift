import Foundation

/// Strips credentials from text before it is written to the request log.
/// Headers, bearer tokens, key-shaped strings, credential query params and credential
/// JSON fields all become `[REDACTED]`. Error codes and messages are kept.
nonisolated enum AIRequestLogRedactor {
    static let placeholder = "[REDACTED]"
    /// Longest error body kept per entry, after redaction.
    static let maxBodyCharacters = 4_000

    private nonisolated struct Rule: Sendable {
        let pattern: String
        let template: String
        let options: NSRegularExpression.Options
    }

    /// Applied in order: whole header lines first, then token shapes, so a key that a
    /// header rule already removed is never matched twice.
    private static let rules: [Rule] = [
        Rule(
            pattern: #"^([ \t]*(?:authorization|proxy-authorization|x-api-key|x-goog-api-key|api-key)[ \t]*:[ \t]*).+$"#,
            template: "$1\(placeholder)",
            options: [.caseInsensitive, .anchorsMatchLines]
        ),
        Rule(
            pattern: #"\b(bearer)\s+[A-Za-z0-9._~+/=\-]+"#,
            template: "$1 \(placeholder)",
            options: [.caseInsensitive]
        ),
        Rule(
            pattern: #"("(?:api[_-]?key|key|access[_-]?token|refresh[_-]?token|id[_-]?token|token|authorization|code[_-]?verifier|secret|client[_-]?secret|password|x-api-key|x-goog-api-key)"\s*:\s*")(?:[^"\\]|\\.)*(")"#,
            template: "$1\(placeholder)$2",
            options: [.caseInsensitive]
        ),
        Rule(
            pattern: #"([?&;](?:key|api[_-]?key|apikey|access[_-]?token|token|code[_-]?verifier|x-goog-api-key)=)[^&\s"'#]+"#,
            template: "$1\(placeholder)",
            options: [.caseInsensitive]
        ),
        // sk-…, sk-or-v1-…, sk-ant-…, sk-proj-…
        Rule(pattern: #"\bsk-[A-Za-z0-9_\-]{8,}"#, template: placeholder, options: []),
        Rule(pattern: #"\bxai-[A-Za-z0-9_\-]{8,}"#, template: placeholder, options: []),
        Rule(pattern: #"\bAIza[0-9A-Za-z_\-]{20,}"#, template: placeholder, options: []),
    ]

    static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }
        return result
    }

    /// Redacts first, then trims to `maxBodyCharacters`, so a cut never exposes part of a key.
    static func redactedBody(_ text: String) -> String {
        let redacted = redact(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > maxBodyCharacters else { return redacted }
        return String(redacted.prefix(maxBodyCharacters)) + "… [truncated]"
    }

    static func redactedBody(_ data: Data) -> String {
        redactedBody(String(decoding: data, as: UTF8.self))
    }
}
