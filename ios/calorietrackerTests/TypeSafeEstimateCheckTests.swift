import Foundation
import Testing
@testable import calorietracker

nonisolated private final class TypeSafeStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) throws -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var requests: [(URLRequest, Data?)] = []

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        Self.requests.append((request, body))
        do {
            let (status, headers, data) = try Self.handler!(request, body)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    nonisolated override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct TypeSafeEstimateCheckTests {
    private let bowl = EstimateCheckInput(
        name: "Chicken rice bowl",
        calories: 640,
        servingSizeGrams: 420,
        servingSizeIsKnown: true,
        items: [
            EstimateCheckItem(name: "grilled chicken", grams: 150),
            EstimateCheckItem(name: "white rice", grams: 200),
        ],
        userNote: "restaurant, extra sauce"
    )

    init() {
        TypeSafeStub.requests = []
        TypeSafeStub.handler = nil
    }

    @Test func requestHitsSystemOneWithBearerKeyAndDocumentedShape() async throws {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answerJSON(noul: 0.9, band: "band_2", density: "moderate")) }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .ok(model: "jev-1.13.0"))
        let (request, body) = try #require(TypeSafeStub.requests.first)
        #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try jsonObject(body)
        #expect(json["model"] as? String == "jev-latest")
        let state = try #require(json["state"] as? [String: Any])
        let meal = try #require(state["meal"] as? [String: Any])
        #expect(meal["name"] as? String == "Chicken rice bowl")
        #expect(containsCaloriesKey(state) == false)
        let questions = try #require(json["questions"] as? [String: Any])
        let plausible = try #require(questions["plausible"] as? [String: Any])
        #expect(plausible["type"] as? String == "noul")
        let instructions = try #require(plausible["instructions"] as? [String: Any])
        #expect(instructions["estimate"] as? String == "about 640 kcal")
        let band = try #require(questions["calorie_band"] as? [String: Any])
        let bandCriteria = try #require(band["criteria"] as? [String: Any])
        #expect(bandCriteria.count == 6)
        let density = try #require(questions["density"] as? [String: Any])
        let densityCriteria = try #require(density["criteria"] as? [String: Any])
        #expect(densityCriteria.count == 5)
    }

    @Test func implausibleEstimateReturnsLooksOffTooLow() async throws {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answerJSON(
                noul: 0.08,
                band: "band_4",
                bandProbabilities: ["band_3": 0.05, "band_4": 0.8, "band_5": 0.15],
                bandConfidence: 0.8,
                density: "rich",
                densityConfidence: 0.7
            ))
        }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .looksOff(
            direction: .tooLow,
            expectedBandLabel: "1,000–1,500 kcal (a very large or restaurant-size meal)",
            model: "jev-1.13.0"
        ))
    }

    @Test func plausibleEstimateReturnsOK() async throws {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answerJSON(noul: 0.9, band: "band_4", density: "rich")) }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .ok(model: "jev-1.13.0"))
    }

    @Test func lowNoulAloneDoesNotFlag() async throws {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answerJSON(noul: 0.1, band: "band_2", density: "moderate"))
        }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .ok(model: "jev-1.13.0"))
    }

    @Test func rejectedKeyIsSilentUnavailable() async throws {
        let auth = Data(#"{"detail":{"error_type":"authentication_error","message":"bad key"}}"#.utf8)
        for status in [401, 403] {
            TypeSafeStub.requests = []
            TypeSafeStub.handler = { _, _ in (status, [:], auth) }
            let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
            #expect(outcome == .unavailable(.keyRejected))
            #expect(TypeSafeStub.requests.count == 1)
        }
    }

    @Test func validationErrorIsInvalidRequest() async throws {
        let body = Data(#"{"detail":[{"loc":["body","state"],"msg":"Field required","type":"missing"}]}"#.utf8)
        TypeSafeStub.handler = { _, _ in (422, [:], body) }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .unavailable(.invalidRequest))
        #expect(TypeSafeStub.requests.count == 1)
    }

    @Test func overloadRetriesOnceThenSucceeds() async throws {
        TypeSafeStub.handler = { _, _ in
            if TypeSafeStub.requests.count == 1 {
                return (529, [:], Data("{}".utf8))
            }
            return (200, [:], Self.answerJSON(noul: 0.9, band: "band_2", density: "moderate"))
        }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .ok(model: "jev-1.13.0"))
        #expect(TypeSafeStub.requests.count == 2)
    }

    @Test func persistentRateLimitGivesUpAfterOneRetry() async throws {
        TypeSafeStub.handler = { _, _ in (429, [:], Data("{}".utf8)) }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(outcome == .unavailable(.rateLimited))
        #expect(TypeSafeStub.requests.count == 2)
    }

    @Test func malformedOrMissingAnswersNeverCrash() async throws {
        let missingBand = Data(#"{"model":"jev-1.13.0","answers":{"plausible":{"type":"noul","noul":0.1}}}"#.utf8)
        TypeSafeStub.handler = { _, _ in (200, [:], missingBand) }
        let missing = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(missing == .unavailable(.invalidResponse))

        TypeSafeStub.requests = []
        let future = Data("""
        {"model":"jev-1.13.0","answers":{"plausible":{"type":"future_type"},"calorie_band":{"type":"choice","choice":"band_2","confidence":0.9,"probabilities":{"band_2":1}}}}
        """.utf8)
        TypeSafeStub.handler = { _, _ in (200, [:], future) }
        let unknown = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "jev-latest")
        #expect(unknown == .unavailable(.invalidResponse))
    }

    @Test func gatewaySentinelsAreTreatedAsOK() async throws {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answerJSON(
                noul: 0.08,
                band: "band_4",
                bandProbabilities: [:],
                bandConfidence: 0,
                density: "rich",
                densityConfidence: 0
            ))
        }
        let outcome = await TypeSafeEstimateChecker.check(bowl, client: client(), model: "typesafe-ai/jev")
        #expect(outcome == .ok(model: "jev-1.13.0"))
    }

    @Test func modelListParsesAndNeverCachesKey() async throws {
        let payload = Data(#"""
        {"models":[{"name":"jev-latest","description":"alias","release_date":"2026-09-15"},{"name":"jev-preview","description":"preview","release_date":"2026-09-15"}]}
        """#.utf8)
        let page = try ModelCatalogParser.parseTypeSafe(payload)
        #expect(page.models.map(\.id) == ["jev-latest", "jev-preview"])
        #expect(page.models.allSatisfy { $0.vision == .textOnly })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: try #require(page.models[0].createdAt))
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 15)

        let gateway = try ModelCatalogParser.parseTypeSafe(Data(#"{"data":[{"id":"typesafe-ai/jev"}]}"#.utf8))
        #expect(gateway.models.map(\.id) == ["typesafe-ai/jev"])

        TypeSafeStub.handler = { _, _ in (200, [:], payload) }
        let models = try await client().listModels()
        #expect(models.map(\.id) == ["jev-latest", "jev-preview"])

        let suiteName = "typesafe.estimate-check.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        TypeSafeSettings.storeCatalog(models, endpoint: .direct, defaults: defaults)
        let stored = try #require(defaults.data(forKey: TypeSafeSettings.modelCatalogKey(for: .direct)))
        #expect(String(decoding: stored, as: UTF8.self).contains("test-key") == false)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func densityOmittedWhenWeightUnknown() async throws {
        let input = EstimateCheckInput(
            name: "Chicken rice bowl",
            calories: 640,
            servingSizeGrams: 420,
            servingSizeIsKnown: false,
            items: bowl.items,
            userNote: nil
        )
        let request = TypeSafeEstimateChecker.makeRequest(for: input, model: "jev-latest")
        #expect(request.questions["density"] == nil)
        let response = try JSONDecoder().decode(
            TypeSafeResponse.self,
            from: Self.answerJSON(noul: 0.1, band: "band_2", density: "very_rich", densityConfidence: 0.9)
        )
        #expect(TypeSafeEstimateChecker.verdict(for: input, response: response) == .ok(model: "jev-1.13.0"))
    }

    @Test func calorieAndDensityBandBoundaries() {
        #expect(TypeSafeEstimateChecker.calorieBand(for: 149) == 0)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 150) == 1)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 399) == 1)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 400) == 2)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 699) == 2)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 700) == 3)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 999) == 3)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 1_000) == 4)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 1_499) == 4)
        #expect(TypeSafeEstimateChecker.calorieBand(for: 1_500) == 5)

        #expect(TypeSafeEstimateChecker.densityBand(kcal: 59, grams: 100) == 0)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 60, grams: 100) == 1)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 149, grams: 100) == 1)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 150, grams: 100) == 2)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 249, grams: 100) == 2)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 250, grams: 100) == 3)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 399, grams: 100) == 3)
        #expect(TypeSafeEstimateChecker.densityBand(kcal: 400, grams: 100) == 4)
    }

    private func client() -> TypeSafeClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TypeSafeStub.self]
        return TypeSafeClient(
            baseURL: "https://api.typesafe.ai",
            apiKey: "test-key",
            session: URLSession(configuration: configuration),
            retryDelaysNs: [0]
        )
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let payload = try #require(data)
        let object = try JSONSerialization.jsonObject(with: payload)
        return try #require(object as? [String: Any])
    }

    private func containsCaloriesKey(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if object.keys.contains("calories") { return true }
            return object.values.contains { containsCaloriesKey($0) }
        }
        if let array = value as? [Any] {
            return array.contains { containsCaloriesKey($0) }
        }
        return false
    }

    nonisolated private static func answerJSON(
        noul: Double,
        band: String,
        bandProbabilities: [String: Double]? = nil,
        bandConfidence: Double = 0.9,
        density: String,
        densityConfidence: Double = 0.9
    ) -> Data {
        let probabilities = bandProbabilities ?? [band: 1]
        let probabilityJSON = probabilities
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\($0.value)" }
            .joined(separator: ",")
        let raw = """
        {"model":"jev-1.13.0","answers":{"plausible":{"type":"noul","noul":\(noul)},"calorie_band":{"type":"choice","choice":"\(band)","confidence":\(bandConfidence),"probabilities":{\(probabilityJSON)}},"density":{"type":"choice","choice":"\(density)","confidence":\(densityConfidence),"probabilities":{"\(density)":1}}},"usage":{"input_tokens":320,"output_tokens":12}}
        """
        return Data(raw.utf8)
    }
}
