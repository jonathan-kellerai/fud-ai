import Foundation
import Testing
@testable import calorietracker

@MainActor
struct ModelCatalogTests {
    @Test func openAICompatibleListParsesCreatedDatesAndPagination() throws {
        let first = Data("""
        {"object":"list","data":[{"id":"gpt-6-luna","created":100},{"id":"gpt-6-sol","created":200.0}],"has_more":true,"last_id":"gpt-6-sol"}
        """.utf8)
        let second = Data("""
        {"object":"list","data":[{"id":"gpt-6-sol","created":200},{"id":"gpt-6-astra","created":300}],"has_more":false,"last_id":"gpt-6-astra"}
        """.utf8)

        let page1 = try ModelCatalogParser.parseOpenAICompatible(first, provider: .openai)
        let page2 = try ModelCatalogParser.parseOpenAICompatible(second, provider: .openai)

        #expect(page1.nextCursor == "gpt-6-sol")
        #expect(page2.nextCursor == nil)
        #expect(page1.models.map(\.vision) == [.supported, .supported])
        let combined = ModelCatalogParser.combining([page1, page2])
        #expect(combined.map(\.id) == ["gpt-6-luna", "gpt-6-sol", "gpt-6-astra"])
        #expect(combined[2].createdAt == Date(timeIntervalSince1970: 300))
    }

    @Test func openRouterModalitiesTagVisionAndLeaveMissingDataUnverified() throws {
        let data = Data("""
        {"data":[
          {"id":"vision-model","architecture":{"input_modalities":["text","image"]}},
          {"id":"text-model","architecture":{"input_modalities":["Text"]}},
          {"id":"unknown-model"}
        ]}
        """.utf8)
        let page = try ModelCatalogParser.parseOpenAICompatible(data, provider: .openrouter)
        #expect(page.models.map(\.vision) == [.supported, .textOnly, .unverified])
        #expect(ModelCatalogLogic.visionSupport(provider: .togetherai, modalities: nil) == .unverified)
        #expect(ModelCatalogLogic.visionSupport(provider: .anthropic, modalities: nil) == .supported)
    }

    @Test func anthropicListPaginatesAndTreatsCurrentModelsAsVision() throws {
        let first = Data("""
        {"data":[{"id":"claude-sonnet-5","created_at":"2026-06-30T00:00:00Z"}],"has_more":true,"last_id":"claude-sonnet-5"}
        """.utf8)
        let second = Data("""
        {"data":[{"id":"claude-haiku-4-5","created_at":"2025-10-15T00:00:00Z"}],"has_more":false,"last_id":"claude-haiku-4-5"}
        """.utf8)
        let page1 = try ModelCatalogParser.parseAnthropic(first)
        let page2 = try ModelCatalogParser.parseAnthropic(second)
        #expect(page1.nextCursor == "claude-sonnet-5")
        #expect(page2.nextCursor == nil)
        let combined = ModelCatalogParser.combining([page1, page2])
        #expect(combined.map(\.id) == ["claude-sonnet-5", "claude-haiku-4-5"])
        #expect(combined.allSatisfy { $0.vision == .supported })
        #expect(combined[0].createdAt != nil)
    }

    @Test func geminiListKeepsGenerateContentModelsAndPaginates() throws {
        let first = Data("""
        {"models":[
          {"name":"models/gemini-3.8-flash","supportedGenerationMethods":["generateContent","countTokens"],"inputModalities":["TEXT","IMAGE"]},
          {"name":"models/gemini-embedding-001","supportedGenerationMethods":["embedContent"],"inputModalities":["TEXT"]}
        ],"nextPageToken":"page-2"}
        """.utf8)
        let second = Data("""
        {"models":[
          {"name":"models/gemini-3.8-flash","supportedGenerationMethods":["generateContent"],"inputModalities":["TEXT","IMAGE"]},
          {"name":"models/gemini-3.5-flash-lite","supportedGenerationMethods":["generateContent"]}
        ]}
        """.utf8)
        let page1 = try ModelCatalogParser.parseGemini(first)
        let page2 = try ModelCatalogParser.parseGemini(second)
        #expect(page1.nextCursor == "page-2")
        #expect(page1.models.map(\.id) == ["gemini-3.8-flash"])
        #expect(page1.models[0].vision == .supported)
        #expect(page2.nextCursor == nil)
        #expect(page2.models.map(\.vision) == [.supported, .unverified])
        let combined = ModelCatalogParser.combining([page1, page2])
        #expect(combined.map(\.id) == ["gemini-3.8-flash", "gemini-3.5-flash-lite"])
    }

    @Test func cacheExpiresAfterTwentyFourHours() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        #expect(!ModelCatalogCachePolicy.isExpired(fetchedAt: fetched, now: fetched.addingTimeInterval(24 * 60 * 60)))
        #expect(ModelCatalogCachePolicy.isExpired(fetchedAt: fetched, now: fetched.addingTimeInterval(24 * 60 * 60 + 1)))
    }

    @Test func presetsStayFirstAndDiscoveredModelsAreUniqueAndNewestFirst() {
        let discovered = [
            CatalogModel(id: "preset-b", createdAt: Date(timeIntervalSince1970: 10), vision: .supported),
            CatalogModel(id: "new-old", createdAt: Date(timeIntervalSince1970: 20), vision: .unverified),
            CatalogModel(id: "new-new", createdAt: Date(timeIntervalSince1970: 40), vision: .supported),
            CatalogModel(id: "text-only", createdAt: Date(timeIntervalSince1970: 50), vision: .textOnly),
            CatalogModel(id: "new-new", createdAt: Date(timeIntervalSince1970: 1), vision: .supported),
            CatalogModel(id: "undated", createdAt: nil, vision: .unverified),
        ]
        let sections = ModelCatalogLogic.sections(
            presets: ["preset-a", "preset-b", "preset-a"],
            discovered: discovered,
            visionOnly: true,
            excludedModelIDs: ["preset-a"]
        )
        #expect(sections.recommended.map(\.id) == ["preset-b"])
        #expect(sections.discovered.map(\.id) == ["new-new", "new-old", "undated"])
        #expect(sections.discovered.map(\.vision) == [.supported, .unverified, .unverified])
    }

    @Test func refreshStoresModelsWithoutTheAPIKeyAndSendsTheKeyOnlyToTheProvider() async throws {
        let suite = "ModelCatalogTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogListStub.self]
        let session = URLSession(configuration: configuration)
        let service = ModelCatalogService(defaults: defaults, session: session, now: { Date(timeIntervalSince1970: 50) })
        CatalogListStub.lastRequest = nil
        let apiKey = "secret-provider-key"

        await service.refresh(provider: .openai, baseURL: "https://api.openai.com/v1/", apiKey: apiKey, force: true)

        let request = try #require(CatalogListStub.lastRequest)
        #expect(request.url?.host == "api.openai.com")
        #expect(request.url?.path == "/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(apiKey)")
        let stored = defaults.dictionaryRepresentation()
            .filter { $0.key.contains("aiModelCatalog") }
            .values
            .compactMap { $0 as? Data }
            .compactMap { String(data: $0, encoding: .utf8) }
        #expect(stored.contains { $0.contains("gpt-6-luna") })
        #expect(!stored.contains { $0.contains(apiKey) })
        #expect(service.couldNotRefresh(provider: .openai, baseURL: "https://api.openai.com/v1") == false)

        let sections = service.sections(
            provider: .openai,
            presets: ["gpt-6-luna", "gpt-5.4-mini"],
            baseURL: "https://api.openai.com/v1",
            visionOnly: true
        )
        #expect(sections.recommended.map(\.id) == ["gpt-6-luna", "gpt-5.4-mini"])
        #expect(sections.discovered.map(\.id) == ["gpt-6-astra"])
    }
}

nonisolated private final class CatalogListStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        Self.lastRequest = request
        let body = Data("""
        {"data":[{"id":"gpt-6-luna","created":10},{"id":"gpt-6-astra","created":20}]}
        """.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    nonisolated override func stopLoading() {}
}
