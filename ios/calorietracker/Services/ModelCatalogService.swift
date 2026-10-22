import Foundation
import Observation

struct ModelCatalogSnapshot: Equatable, Codable {
    var fetchedAt: Date
    var models: [CatalogModel]
}

/// Loads each provider's model list with the user's own key and caches the ids.
/// The key is sent only on that provider's list endpoint and is never written to the cache.
@MainActor
@Observable
final class ModelCatalogService {
    static let shared = ModelCatalogService(session: ephemeralSession)

    private static let ephemeralSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static let maximumPages = 8
    private static let refreshDelayNs: UInt64 = 800_000_000
    private static let anthropicVersion = "2023-06-01"

    private var snapshots: [String: ModelCatalogSnapshot] = [:]
    private var failedKeys: Set<String> = []
    private(set) var revision = 0
    private var pendingRefreshes: [String: Task<Void, Never>] = [:]
    private let defaults: UserDefaults
    private let session: URLSession
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.session = session
        self.now = now
    }

    func snapshot(provider: AIProvider, baseURL: String) -> ModelCatalogSnapshot? {
        let key = cacheKey(provider: provider, baseURL: baseURL)
        if let snapshot = snapshots[key] { return snapshot }
        guard let data = defaults.data(forKey: storageKey(key)),
              let snapshot = try? JSONDecoder().decode(ModelCatalogSnapshot.self, from: data) else {
            return nil
        }
        snapshots[key] = snapshot
        return snapshot
    }

    func couldNotRefresh(provider: AIProvider, baseURL: String) -> Bool {
        failedKeys.contains(cacheKey(provider: provider, baseURL: baseURL))
    }

    func sections(
        provider: AIProvider,
        presets: [String],
        baseURL: String,
        visionOnly: Bool,
        excludedModelIDs: Set<String> = []
    ) -> ModelPickerSections {
        let discovered = snapshot(provider: provider, baseURL: baseURL)?.models ?? []
        return ModelCatalogLogic.sections(
            presets: presets,
            discovered: discovered,
            presetVision: { id in
                provider.models.contains(id) ? .supported : .unverified
            },
            visionOnly: visionOnly,
            excludedModelIDs: excludedModelIDs
        )
    }

    /// Waits briefly so a pasted key is one request, not one request per character.
    func scheduleRefresh(provider: AIProvider, baseURL: String, apiKey: String, force: Bool = true) {
        let key = cacheKey(provider: provider, baseURL: baseURL)
        pendingRefreshes[key]?.cancel()
        pendingRefreshes[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.refreshDelayNs)
            guard !Task.isCancelled else { return }
            await self?.refresh(provider: provider, baseURL: baseURL, apiKey: apiKey, force: force)
        }
    }

    func refresh(provider: AIProvider, baseURL: String, apiKey: String, force: Bool) async {
        let resolvedBaseURL = normalizedBaseURL(baseURL.isEmpty ? provider.baseURL : baseURL)
        let key = cacheKey(provider: provider, baseURL: resolvedBaseURL)
        guard canRequest(provider: provider, baseURL: resolvedBaseURL, apiKey: apiKey) else { return }
        if !force, let snapshot = snapshot(provider: provider, baseURL: resolvedBaseURL),
           !ModelCatalogCachePolicy.isExpired(fetchedAt: snapshot.fetchedAt, now: now()) {
            failedKeys.remove(key)
            revision += 1
            return
        }

        do {
            let models = try await listModels(provider: provider, baseURL: resolvedBaseURL, apiKey: apiKey)
            let snapshot = ModelCatalogSnapshot(fetchedAt: now(), models: models)
            snapshots[key] = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: storageKey(key))
            }
            failedKeys.remove(key)
            revision += 1
        } catch is CancellationError {
            return
        } catch {
            failedKeys.insert(key)
            revision += 1
        }
    }

    private func canRequest(provider: AIProvider, baseURL: String, apiKey: String) -> Bool {
        switch provider.apiFormat {
        case .onDevice, .liteRTLocal:
            return false
        case .gemini, .openaiCompatible, .anthropic:
            break
        }
        if baseURL.isEmpty { return false }
        if provider.requiresAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private func listModels(provider: AIProvider, baseURL: String, apiKey: String) async throws -> [CatalogModel] {
        var pages: [CatalogPage] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        for _ in 0..<Self.maximumPages {
            let page = try await fetchPage(provider: provider, baseURL: baseURL, apiKey: apiKey, cursor: cursor)
            pages.append(page)
            guard let next = page.nextCursor, !next.isEmpty, seenCursors.insert(next).inserted else { break }
            cursor = next
        }
        return ModelCatalogParser.combining(pages)
    }

    private func fetchPage(provider: AIProvider, baseURL: String, apiKey: String, cursor: String?) async throws -> CatalogPage {
        let url = try listURL(provider: provider, baseURL: baseURL, apiKey: apiKey, cursor: cursor)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch provider.apiFormat {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        case .openaiCompatible:
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
            }
        case .gemini, .onDevice, .liteRTLocal:
            break
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CatalogRequestError.unsuccessful
        }
        switch provider.apiFormat {
        case .anthropic:
            return try ModelCatalogParser.parseAnthropic(data)
        case .gemini:
            return try ModelCatalogParser.parseGemini(data)
        case .openaiCompatible:
            return try ModelCatalogParser.parseOpenAICompatible(data, provider: provider)
        case .onDevice, .liteRTLocal:
            throw CatalogRequestError.unsuccessful
        }
    }

    private func listURL(provider: AIProvider, baseURL: String, apiKey: String, cursor: String?) throws -> URL {
        guard var components = URLComponents(string: normalizedBaseURL(baseURL) + "/models") else {
            throw CatalogRequestError.unsuccessful
        }
        var items: [URLQueryItem] = []
        switch provider.apiFormat {
        case .gemini:
            items.append(URLQueryItem(name: "key", value: apiKey))
            items.append(URLQueryItem(name: "pageSize", value: "100"))
            if let cursor { items.append(URLQueryItem(name: "pageToken", value: cursor)) }
        case .anthropic:
            items.append(URLQueryItem(name: "limit", value: "100"))
            if let cursor { items.append(URLQueryItem(name: "after_id", value: cursor)) }
        case .openaiCompatible:
            if let cursor { items.append(URLQueryItem(name: "after_id", value: cursor)) }
        case .onDevice, .liteRTLocal:
            break
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw CatalogRequestError.unsuccessful }
        return url
    }

    private func normalizedBaseURL(_ baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    private func cacheKey(provider: AIProvider, baseURL: String) -> String {
        provider.rawValue + "\n" + normalizedBaseURL(baseURL.isEmpty ? provider.baseURL : baseURL)
    }

    private func storageKey(_ cacheKey: String) -> String {
        "aiModelCatalog.v1." + cacheKey
    }
}

private enum CatalogRequestError: Error {
    case unsuccessful
}
