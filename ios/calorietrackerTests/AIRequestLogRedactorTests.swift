import Foundation
import Testing
@testable import calorietracker

/// Nothing that looks like a credential may reach the request log file.
struct AIRequestLogRedactorTests {
    private let redacted = AIRequestLogRedactor.placeholder

    @Test(arguments: [
        "sk-proj-AbCdEf0123456789xyz",
        "sk-or-v1-0123456789abcdef0123456789abcdef",
        "sk-ant-api03-Zz9_Yy8-Xx7Ww6",
        "sk-0123456789ABCDEFGHIJ",
        "xai-AbCdEf0123456789AbCdEf",
        "AIzaSyD-0123456789abcdefghijklmnopqrs",
    ])
    func keyShapedStringsAreRemoved(key: String) {
        let text = "Incorrect API key provided: \(key). You can find your key at the dashboard."
        let result = AIRequestLogRedactor.redact(text)
        #expect(!result.contains(key))
        #expect(result.contains(redacted))
        #expect(result.hasPrefix("Incorrect API key provided: "))
        #expect(result.hasSuffix(". You can find your key at the dashboard."))
    }

    @Test func bearerTokensAreRemovedButTheWordStays() {
        let result = AIRequestLogRedactor.redact("sent Bearer abc.DEF-123_xyz~+/= to the server")
        #expect(result == "sent Bearer \(redacted) to the server")
    }

    @Test func credentialHeaderLinesAreRemoved() {
        let text = """
        Authorization: Bearer sk-or-v1-secretsecretsecret
        x-api-key: sk-ant-api03-secretsecret
        X-goog-api-key: AIzaSyD-0123456789abcdefghijklmnopqrs
        Content-Type: application/json
        """
        let result = AIRequestLogRedactor.redact(text)
        #expect(result == """
        Authorization: \(redacted)
        x-api-key: \(redacted)
        X-goog-api-key: \(redacted)
        Content-Type: application/json
        """)
    }

    @Test func credentialQueryParamsAreRemoved() {
        let url = "https://generativelanguage.googleapis.com/v1beta/models/x:generateContent?key=plainsecret&alt=json&api_key=other&token=t0k&access_token=a1#frag"
        let result = AIRequestLogRedactor.redact(url)
        #expect(!result.contains("plainsecret"))
        #expect(!result.contains("other"))
        #expect(!result.contains("t0k"))
        #expect(!result.contains("=a1"))
        #expect(result.contains("?key=\(redacted)&alt=json&api_key=\(redacted)"))
        #expect(result.hasSuffix("#frag"))
    }

    @Test func credentialJSONFieldsAreRemovedAndErrorCodesKept() {
        let body = #"{"key":"opaque-value","api_key":"v2","token":"esc\"aped","code_verifier":"verif","error":{"code":"invalid_api_key","message":"Bad key"}}"#
        let result = AIRequestLogRedactor.redact(body)
        #expect(result == #"{"key":"[REDACTED]","api_key":"[REDACTED]","token":"[REDACTED]","code_verifier":"[REDACTED]","error":{"code":"invalid_api_key","message":"Bad key"}}"#)
    }

    @Test func ordinaryErrorTextIsUntouched() {
        let body = #"{"error":{"message":"The model `grok-9` does not exist or you do not have access to it.","type":"invalid_request_error","code":"model_not_found"}}"#
        #expect(AIRequestLogRedactor.redact(body) == body)
        #expect(AIRequestLogRedactor.redact("task-sk-free words: skip, desk-lamp") == "task-sk-free words: skip, desk-lamp")
    }

    @Test func longBodiesAreRedactedBeforeTheyAreTrimmed() {
        let key = "sk-or-v1-" + String(repeating: "a", count: 40)
        // The key starts 5 characters before the cut, so trimming first would keep "sk-o".
        let padding = String(repeating: "x", count: AIRequestLogRedactor.maxBodyCharacters - 6)
        let result = AIRequestLogRedactor.redactedBody(padding + " " + key)
        #expect(!result.contains("sk-o"))
        #expect(result.contains(" [RED"))
        #expect(result.hasSuffix("… [truncated]"))
        #expect(result.count <= AIRequestLogRedactor.maxBodyCharacters + "… [truncated]".count)
    }

    @Test func dataBodiesAreDecodedAndRedacted() {
        let data = Data(#"{"error":{"message":"Invalid key sk-0123456789ABCDEF"}}"#.utf8)
        #expect(AIRequestLogRedactor.redactedBody(data) == #"{"error":{"message":"Invalid key [REDACTED]"}}"#)
    }

    // MARK: - Codex round 1 (P1): escaped keys, inline echoes, the request's own credential

    @Test func unicodeEscapedCredentialKeysAreRedacted() {
        // `api\u005fkey` is "api_key" once decoded; the text rules can't match it.
        let body = #"{"api\u005fkey":"opaque-credential"}"#
        #expect(body.contains(#"\u005f"#))
        let result = AIRequestLogRedactor.redact(body)
        #expect(!result.contains("opaque-credential"))
        #expect(result == #"{"api_key":"[REDACTED]"}"#)
    }

    @Test func nestedCredentialFieldsAreRedactedAtAnyDepth() {
        let body = #"{"data":[{"auth":{"access_token":"deep-opaque-1","Client-Secret":42}}],"error":{"code":"bad"}}"#
        let result = AIRequestLogRedactor.redact(body)
        #expect(!result.contains("deep-opaque-1"))
        #expect(!result.contains("42"))
        #expect(result.contains(#""code":"bad""#))
    }

    @Test func headerEchoesInsideAMessageAreRedacted() {
        let body = #"{"error":{"message":"Rejected x-api-key: opaque-credential"}}"#
        let result = AIRequestLogRedactor.redact(body)
        #expect(result == #"{"error":{"message":"Rejected x-api-key: [REDACTED]"}}"#)
    }

    @Test(arguments: [
        "Rejected x-api-key: opaque-credential, try again",
        "bad header Authorization: Bearer opaque-credential.",
        "got X-Goog-Api-Key=opaque-credential;",
        "proxy-authorization: Basic opaque-credential",
    ])
    func inlineHeaderEchoesInPlainTextAreRedacted(text: String) {
        let result = AIRequestLogRedactor.redact(text)
        #expect(!result.contains("opaque-credential"))
        #expect(result.contains(redacted))
    }

    @Test func theRequestsOwnCredentialIsRemovedInEveryEncoding() throws {
        let secret = "opaque/cred+ential=1"
        let percent = try #require(secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let base64 = Data(secret.utf8).base64EncodedString()
        let unicode = secret.unicodeScalars.map { String(format: "\\u%04x", $0.value) }.joined()
        let text = "raw \(secret) | pct \(percent) | json opaque\\/cred+ential=1 | b64 \(base64) | u \(unicode)"
        let result = AIRequestLogRedactor.redact(text, secrets: [secret])
        #expect(result == "raw \(redacted) | pct \(redacted) | json \(redacted) | b64 \(redacted) | u \(redacted)")
    }

    @Test func theRequestsOwnCredentialIsRemovedFromDecodedJSONStrings() {
        // The value is split by an escape the raw text pass can't see.
        let body = #"{"error":{"message":"Unknown credential opaque\u002dcredential-77"}}"#
        #expect(body.contains(#"\u002d"#))
        let result = AIRequestLogRedactor.redact(body, secrets: ["opaque-credential-77"])
        #expect(!result.contains("credential-77"))
        #expect(result == #"{"error":{"message":"Unknown credential [REDACTED]"}}"#)
    }

    @Test func shortSecretsAreIgnoredSoOrdinaryWordsSurvive() {
        #expect(AIRequestLogRedactor.redact("the key is ok", secrets: ["ok", ""]) == "the key is ok")
    }

    @Test func credentialsAreReadFromRequestHeadersAndQuery() throws {
        let url = try #require(URL(string: "https://example.test/v1?key=query-secret-1&alt=json"))
        let values = AIRequestLogRedactor.credentials(
            headers: [
                "Authorization": "Bearer bearer-secret-1",
                "x-api-key": "header-secret-1",
                "Content-Type": "application/json",
            ],
            url: url
        )
        #expect(Set(values) == ["Bearer bearer-secret-1", "bearer-secret-1", "header-secret-1", "query-secret-1"])
    }
}
