import Foundation

/// Strips credentials from text before it is written to the request log.
/// The request's own credentials (in any encoding), headers, bearer tokens, key-shaped
/// strings, credential query params and credential JSON fields (at any depth, however the
/// key is escaped) all become `[REDACTED]`. Error codes and messages are kept.
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
        // Header echoed inside a sentence, e.g. "Rejected x-api-key: abc".
        Rule(
            pattern: #"(?<![A-Za-z0-9_\-])((?:proxy-)?authorization|x-api-key|x-goog-api-key|api-key)([ \t]*[:=][ \t]*)(?:(?:bearer|basic|token)[ \t]+)?[^\s"',;\\]+"#,
            template: "$1$2\(placeholder)",
            options: [.caseInsensitive]
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

    /// JSON keys whose value is always a credential, compared lowercased with `-` and `_` removed.
    private static let credentialKeys: Set<String> = [
        "apikey", "key", "accesstoken", "refreshtoken", "idtoken", "token", "authorization",
        "proxyauthorization", "codeverifier", "secret", "clientsecret", "password",
        "xapikey", "xgoogapikey",
    ]

    /// Header and query names that carry a credential in an outgoing request.
    private static let credentialHeaderNames: Set<String> = [
        "authorization", "proxyauthorization", "xapikey", "xgoogapikey", "apikey",
    ]

    /// Shorter values are too likely to be ordinary words to scrub everywhere.
    static let minimumSecretLength = 8

    /// `secrets` are the credentials the request itself sent. They are removed first, in
    /// every encoding a server might echo them in, then the pattern rules run, then any
    /// JSON body is walked so escaped or nested credential fields can't slip through.
    static func redact(_ text: String, secrets: [String] = []) -> String {
        let usable = secrets.filter { $0.count >= minimumSecretLength }
        let scrubbed = applyRules(removingSecrets(usable, from: text))
        return redactingJSON(scrubbed, secrets: usable) ?? scrubbed
    }

    /// The credential values in a request's headers and URL query, for `redact(_:secrets:)`.
    /// "Bearer abc" yields both the full value and "abc".
    static func credentials(headers: [String: String], url: URL? = nil) -> [String] {
        var values: [String] = []
        for (name, value) in headers where credentialHeaderNames.contains(normalizedKey(name)) {
            values.append(value)
            let parts = value.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                values.append(String(parts[1]).trimmingCharacters(in: .whitespaces))
            }
        }
        if let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items where credentialKeys.contains(normalizedKey(item.name)) {
                if let value = item.value { values.append(value) }
            }
        }
        return values.filter { $0.count >= minimumSecretLength }
    }

    private static func applyRules(_ text: String) -> String {
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

    /// Longest forms first, so a raw value inside a longer encoded form isn't half-replaced.
    private static func removingSecrets(_ secrets: [String], from text: String) -> String {
        guard !secrets.isEmpty else { return text }
        let forms = Set(secrets.flatMap(encodedForms)).sorted { $0.count > $1.count }
        var result = text
        for form in forms where !form.isEmpty {
            result = result.replacingOccurrences(of: form, with: placeholder)
        }
        return result
    }

    /// Raw, percent-encoded, JSON-escaped, \u-escaped and base64 forms of one secret.
    private static func encodedForms(_ secret: String) -> [String] {
        var forms = [secret]
        if let percent = secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            forms.append(percent)
        }
        if let query = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            forms.append(query)
        }
        forms.append(secret.replacingOccurrences(of: "/", with: "\\/"))
        forms.append(secret.unicodeScalars.map { String(format: "\\u%04x", $0.value) }.joined())
        forms.append(secret.unicodeScalars.map { String(format: "\\u%04X", $0.value) }.joined())
        forms.append(Data(secret.utf8).base64EncodedString())
        return forms
    }

    /// Re-encodes a JSON body only when the walk removed something the text rules missed,
    /// so ordinary bodies keep their original key order and spacing.
    private static func redactingJSON(_ text: String, secrets: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])
        else { return nil }
        let (walked, changed) = redactJSONValue(object, secrets: secrets)
        guard changed,
              let data = try? JSONSerialization.data(withJSONObject: walked, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func redactJSONValue(_ value: Any, secrets: [String]) -> (Any, Bool) {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            var changed = false
            for (key, child) in dictionary {
                if credentialKeys.contains(normalizedKey(key)) {
                    let alreadyRedacted = (child as? String) == placeholder
                    result[key] = placeholder
                    changed = changed || !alreadyRedacted
                } else {
                    let (walked, childChanged) = redactJSONValue(child, secrets: secrets)
                    result[key] = walked
                    changed = changed || childChanged
                }
            }
            return (result, changed)
        }
        if let array = value as? [Any] {
            var changed = false
            let result = array.map { child -> Any in
                let (walked, childChanged) = redactJSONValue(child, secrets: secrets)
                changed = changed || childChanged
                return walked
            }
            return (result, changed)
        }
        if let string = value as? String {
            let redacted = applyRules(removingSecrets(secrets, from: string))
            return (redacted, redacted != string)
        }
        return (value, false)
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Redacts first, then trims to `maxBodyCharacters`, so a cut never exposes part of a key.
    static func redactedBody(_ text: String, secrets: [String] = []) -> String {
        let redacted = redact(text, secrets: secrets).trimmingCharacters(in: .whitespacesAndNewlines)
        guard redacted.count > maxBodyCharacters else { return redacted }
        return String(redacted.prefix(maxBodyCharacters)) + "… [truncated]"
    }

    static func redactedBody(_ data: Data, secrets: [String] = []) -> String {
        redactedBody(String(decoding: data, as: UTF8.self), secrets: secrets)
    }
}
