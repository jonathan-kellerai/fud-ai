import Foundation
import Testing
import UIKit
@testable import calorietracker

/// Hosted meal requests reach the request log with their HTTP status and redacted body,
/// through the real `GeminiService.analyzeFood` → `HostedAIService` path and a stubbed session.
@Suite(.serialized)
@MainActor
struct HostedAIServiceTraceTests {
    private static let foodJSON = #"{"name":"Oatmeal","calories":150,"protein":5,"carbs":27,"fat":3,"serving_size_grams":40,"ingredients":[],"unit_options":[]}"#

    @Test func hostedSuccessRecordsStatusAndParsed() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["text": Self.foodJSON])
        let (entries, error) = await run { request in Self.response(request, status: 200, body: body) }
        #expect(error == nil)
        #expect(entries.count == 1)
        #expect(entries.first?.provider == AIRequestTrace.hostedProviderName)
        #expect(entries.first?.httpStatus == 200)
        #expect(entries.first?.errorBody == nil)
        #expect(entries.first?.parsed == true)
    }

    @Test func hostedUpstreamFailureKeepsTheStatusAndBody() async {
        let (entries, error) = await run { request in
            Self.response(request, status: 503, body: Data(#"{"error":"upstream_unavailable"}"#.utf8))
        }
        #expect(error != nil)
        #expect(entries.count == 1)
        #expect(entries.first?.httpStatus == 503)
        #expect(entries.first?.errorBody?.contains("upstream_unavailable") == true)
        #expect(entries.first?.parsed == false)
    }

    @Test func hostedRejectionBodyIsRedacted() async {
        let (entries, error) = await run { request in
            Self.response(request, status: 400, body: Data(#"{"error":"invalid_request_body","detail":"Rejected x-api-key: opaque-credential"}"#.utf8))
        }
        #expect(error is HostedAIServiceError)
        #expect(entries.first?.httpStatus == 400)
        let body = entries.first?.errorBody ?? ""
        #expect(body.contains("invalid_request_body"))
        #expect(!body.contains("opaque-credential"))
        #expect(entries.first?.parsed == false)
    }

    @Test func hostedMalformedAnswerKeepsTheResponseForTheLog() async {
        let (entries, error) = await run { request in
            Self.response(request, status: 200, body: Data(#"{"unexpected":true}"#.utf8))
        }
        #expect(error != nil)
        #expect(entries.first?.httpStatus == 200)
        #expect(entries.first?.errorBody?.contains(#""unexpected":true"#) == true)
        #expect(entries.first?.parsed == false)
    }

    @Test func hostedTransportFailureIsRecordedWithoutAStatus() async {
        let (entries, error) = await run { _ in throw URLError(.notConnectedToInternet) }
        #expect(error != nil)
        #expect(entries.first?.httpStatus == nil)
        #expect(entries.first?.errorBody?.contains("\(NSURLErrorDomain) \(URLError.Code.notConnectedToInternet.rawValue)") == true)
        #expect(entries.first?.parsed == false)
    }

    // MARK: - Helpers

    /// One hosted meal photo request; returns the trace's entries and the thrown error, if any.
    private func run(
        _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async -> ([AIRequestLogEntry], Error?) {
        HostedTraceURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostedTraceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var environment = AIRouteEnvironment.live
        environment.isHosted = { true }
        environment.hosted = { prompt, imageDataList, trace in
            try await HostedAIService.generate(
                prompt: prompt,
                imageDataList: imageDataList,
                systemInstruction: nil,
                trace: trace,
                session: session,
                userID: "hosted-trace-test"
            )
        }
        let saved = AIRouteEnvironment.current
        AIRouteEnvironment.current = environment
        defer { AIRouteEnvironment.current = saved }

        let trace = AIRequestTrace(kind: .mealPhoto)
        do {
            _ = try await GeminiService.analyzeFood(image: Self.image(), skipHostedMetering: true, trace: trace)
            return (trace.entries(outcome: .parsed), nil)
        } catch {
            return (trace.entries(outcome: .failed(GeminiService.requestLogMessage(for: error))), error)
        }
    }

    private static func response(_ request: URLRequest, status: Int, body: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
    }

    private static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}

private final class HostedTraceURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
