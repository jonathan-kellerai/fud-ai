import Foundation
import Testing
@testable import calorietracker

struct OpenRouterOAuthTests {
    /// RFC 7636 Appendix B.
    private static let rfcVerifierBytes: [UInt8] = [
        116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186,
        22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121,
    ]
    private static let rfcVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    private static let rfcChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    private let pkce = OpenRouterOAuth.PKCE(verifier: rfcVerifier, state: "state-123")

    // MARK: - PKCE

    @Test func rfc7636AppendixBVector() {
        #expect(OpenRouterOAuth.challenge(for: Self.rfcVerifier) == Self.rfcChallenge)
        let fromBytes = OpenRouterOAuth.PKCE(verifierBytes: Self.rfcVerifierBytes, stateBytes: [0, 1, 2])
        #expect(fromBytes.verifier == Self.rfcVerifier)
        #expect(fromBytes.challenge == Self.rfcChallenge)
    }

    @Test func verifierFromRandomBytesMeetsTheRFC() {
        let bytes = (0..<OpenRouterOAuth.verifierByteCount).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 251) }
        let made = OpenRouterOAuth.PKCE(verifierBytes: bytes, stateBytes: Array(repeating: 255, count: OpenRouterOAuth.stateByteCount))
        #expect(made.verifier.count == 43)
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(made.verifier.unicodeScalars.allSatisfy { unreserved.contains($0) })
        #expect(!made.challenge.contains("="))
        #expect(made.challenge.count == 43)
        #expect(made.state == "_____________________w")
    }

    @Test func base64URLHasNoPaddingOrUnsafeCharacters() {
        #expect(OpenRouterOAuth.base64URL(Data([0xfb, 0xff, 0xfe])) == "-__-")
        #expect(OpenRouterOAuth.base64URL(Data([0x00])) == "AA")
    }

    // MARK: - Sign-in URL

    @Test func callbackURLCarriesChallengeStateAndEncodedCallback() throws {
        let url = try #require(OpenRouterOAuth.authorizationURL(pkce: pkce, mode: .callback))
        #expect(url.absoluteString == "https://openrouter.ai/auth?callback_url=fudai%3A%2F%2Fopenrouter-callback&code_challenge=\(Self.rfcChallenge)&code_challenge_method=S256&state=state-123")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "callback_url" }?.value == "fudai://openrouter-callback")
    }

    @Test func displayCodeURLOmitsTheCallbackAndNamesTheKey() throws {
        let url = try #require(OpenRouterOAuth.authorizationURL(pkce: pkce, mode: .displayCode))
        #expect(url.absoluteString == "https://openrouter.ai/auth?code_challenge=\(Self.rfcChallenge)&code_challenge_method=S256&key_label=JL%20Physical")
        #expect(!url.absoluteString.contains("callback_url"))
        #expect(!url.absoluteString.contains("state="))
    }

    @Test func percentEncodingKeepsOnlyUnreservedASCII() {
        #expect(OpenRouterOAuth.percentEncoded("a-b_c.d~e") == "a-b_c.d~e")
        #expect(OpenRouterOAuth.percentEncoded("a b/c?d=e&f+g") == "a%20b%2Fc%3Fd%3De%26f%2Bg")
        #expect(OpenRouterOAuth.percentEncoded("é") == "%C3%A9")
    }

    // MARK: - Callback

    @Test func callbackWithCodeAndMatchingState() throws {
        let url = try #require(URL(string: "fudai://openrouter-callback?code=abc-123&state=state-123"))
        #expect(OpenRouterOAuth.parseCallback(url, expectedState: "state-123") == .code("abc-123"))
    }

    @Test func callbackWithWrongOrMissingStateIsRejected() throws {
        let wrong = try #require(URL(string: "fudai://openrouter-callback?code=abc&state=other"))
        let missing = try #require(URL(string: "fudai://openrouter-callback?code=abc"))
        #expect(OpenRouterOAuth.parseCallback(wrong, expectedState: "state-123") == .stateMismatch)
        #expect(OpenRouterOAuth.parseCallback(missing, expectedState: "state-123") == .stateMismatch)
    }

    @Test func callbackErrorIsReadEvenWithoutState() throws {
        let denied = try #require(URL(string: "fudai://openrouter-callback?error=access_denied&error_description=User%20declined"))
        let bare = try #require(URL(string: "fudai://openrouter-callback?error=access_denied"))
        #expect(OpenRouterOAuth.parseCallback(denied, expectedState: "state-123") == .denied("User declined"))
        #expect(OpenRouterOAuth.parseCallback(bare, expectedState: "state-123") == .denied("access_denied"))
    }

    @Test func callbackWithoutCodeOrForAnotherHost() throws {
        let empty = try #require(URL(string: "fudai://openrouter-callback?code=&state=state-123"))
        let otherHost = try #require(URL(string: "fudai://log-food?code=abc&state=state-123"))
        let otherScheme = try #require(URL(string: "https://openrouter-callback?code=abc&state=state-123"))
        #expect(OpenRouterOAuth.parseCallback(empty, expectedState: "state-123") == .missingCode)
        #expect(OpenRouterOAuth.parseCallback(otherHost, expectedState: "state-123") == .wrongCallback)
        #expect(OpenRouterOAuth.parseCallback(otherScheme, expectedState: "state-123") == .wrongCallback)
    }

    @Test func pastedCodesAreCleanedUp() {
        #expect(OpenRouterOAuth.normalizedPastedCode("  abc-123\n") == "abc-123")
        #expect(OpenRouterOAuth.normalizedPastedCode("fudai://openrouter-callback?code=xyz&state=s") == "xyz")
        #expect(OpenRouterOAuth.normalizedPastedCode("") == nil)
        #expect(OpenRouterOAuth.normalizedPastedCode("two words") == nil)
    }

    // MARK: - Exchange

    @Test func exchangeRequestPostsCodeVerifierAndMethod() throws {
        let request = try #require(OpenRouterOAuth.exchangeRequest(code: "the-code", verifier: Self.rfcVerifier))
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/auth/keys")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body == #"{"code":"the-code","code_challenge_method":"S256","code_verifier":"\#(Self.rfcVerifier)"}"#)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func exchangeResponseReturnsTheKey() throws {
        let data = Data(#"{"key":"sk-or-v1-abcdef","user_id":"u1"}"#.utf8)
        #expect(try OpenRouterOAuth.parseExchangeResponse(status: 200, data: data) == "sk-or-v1-abcdef")
    }

    @Test func exchangeErrorsCarryStatusAndMessage() {
        let expired = Data(#"{"error":{"message":"Authorization code expired","code":403}}"#.utf8)
        #expect(throws: OpenRouterOAuth.ExchangeError.rejected(status: 403, message: "Authorization code expired")) {
            try OpenRouterOAuth.parseExchangeResponse(status: 403, data: expired)
        }
        #expect(throws: OpenRouterOAuth.ExchangeError.rejected(status: 400, message: "Invalid code_challenge_method")) {
            try OpenRouterOAuth.parseExchangeResponse(status: 400, data: Data(#"{"error":"Invalid code_challenge_method"}"#.utf8))
        }
        #expect(throws: OpenRouterOAuth.ExchangeError.rejected(status: 405, message: "")) {
            try OpenRouterOAuth.parseExchangeResponse(status: 405, data: Data("<html>".utf8))
        }
        #expect(throws: OpenRouterOAuth.ExchangeError.malformedResponse) {
            try OpenRouterOAuth.parseExchangeResponse(status: 200, data: Data(#"{"key":""}"#.utf8))
        }
    }

    @Test func exchangeErrorMessagesNeverEchoAKey() {
        let data = Data(#"{"error":{"message":"bad key sk-or-v1-0123456789abcdef"}}"#.utf8)
        do {
            _ = try OpenRouterOAuth.parseExchangeResponse(status: 401, data: data)
            Issue.record("Expected a rejection")
        } catch let error as OpenRouterOAuth.ExchangeError {
            #expect(!error.message.contains("sk-or-v1-0123"))
            #expect(error.message.contains("HTTP 401"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
        #expect(OpenRouterOAuth.ExchangeError.rejected(status: 403, message: "").message.contains("expired"))
    }

    @Test func keyFingerprintIsSHA256Hex() {
        #expect(OpenRouterOAuth.keyFingerprint("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(OpenRouterOAuth.keyFingerprint("abc") != OpenRouterOAuth.keyFingerprint("abd"))
    }
}
