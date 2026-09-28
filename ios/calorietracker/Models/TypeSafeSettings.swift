import Foundation

enum TypeSafeEndpoint: String, CaseIterable, Identifiable {
    case direct
    case vercelGateway

    var id: String { rawValue }

    var title: String { self == .direct ? "TypeSafe" : "Vercel AI Gateway" }

    var baseURL: String {
        self == .direct ? "https://api.typesafe.ai" : "https://ai-gateway.vercel.sh/typesafe"
    }

    var presets: [String] {
        self == .direct ? ["jev-latest", "jev-preview", "jev-1.13.0"] : ["typesafe-ai/jev"]
    }

    var defaultModel: String { presets[0] }

    var keyPlaceholder: String {
        self == .direct ? "Paste TypeSafe API key" : "Paste AI Gateway key"
    }
}

enum TypeSafeSettings {
    static let didChangeNotification = Notification.Name("TypeSafeSettingsDidChange")
    static let enabledKey = "typesafe.estimateCheck.enabled"
    static let checkTextKey = "typesafe.estimateCheck.checkText"
    static let endpointKey = "typesafe.endpoint"
    static let modelKey = "typesafe.model"
    static let directAPIKeyAccount = "typesafe.apiKey.direct"
    static let vercelGatewayAPIKeyAccount = "typesafe.apiKey.vercelGateway"
    static let modelCatalogKeyPrefix = "typesafe.modelCatalog.v1."

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Absent key means on. `bool(forKey:)` would read that absence as false.
    static var checkTypedMeals: Bool {
        get {
            let defaults = UserDefaults.standard
            return defaults.object(forKey: checkTextKey) == nil ? true : defaults.bool(forKey: checkTextKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: checkTextKey) }
    }

    static var endpoint: TypeSafeEndpoint {
        get {
            let raw = UserDefaults.standard.string(forKey: endpointKey) ?? ""
            return TypeSafeEndpoint(rawValue: raw) ?? .direct
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: endpointKey)
            postChange()
        }
    }

    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? endpoint.defaultModel : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelKey)
            postChange()
        }
    }

    static func apiKeyAccount(for endpoint: TypeSafeEndpoint) -> String {
        switch endpoint {
        case .direct: directAPIKeyAccount
        case .vercelGateway: vercelGatewayAPIKeyAccount
        }
    }

    static func modelCatalogKey(for endpoint: TypeSafeEndpoint) -> String {
        modelCatalogKeyPrefix + endpoint.rawValue
    }

    static func apiKey(for endpoint: TypeSafeEndpoint) -> String? {
        KeychainHelper.load(key: apiKeyAccount(for: endpoint))
    }

    static func setAPIKey(_ key: String?, for endpoint: TypeSafeEndpoint) {
        let account = apiKeyAccount(for: endpoint)
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainHelper.save(key: account, value: trimmed)
        } else {
            KeychainHelper.delete(key: account)
        }
        postChange()
    }

    static var hasCredentials: Bool {
        let key = apiKey(for: endpoint)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && !modelID.isEmpty
    }

    static var isConfigured: Bool {
        enabled && hasCredentials
    }

    private static func postChange() {
        JevCredentials.refresh()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func cachedCatalog(for endpoint: TypeSafeEndpoint, defaults: UserDefaults = .standard) -> ModelCatalogSnapshot? {
        guard let data = defaults.data(forKey: modelCatalogKey(for: endpoint)) else { return nil }
        return try? JSONDecoder().decode(ModelCatalogSnapshot.self, from: data)
    }

    /// Stores model ids only. The API key is never written into this blob.
    static func storeCatalog(_ models: [CatalogModel], endpoint: TypeSafeEndpoint, defaults: UserDefaults = .standard, fetchedAt: Date = Date()) {
        let snapshot = ModelCatalogSnapshot(fetchedAt: fetchedAt, models: models)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: modelCatalogKey(for: endpoint))
    }

    static func deleteAllData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: checkTextKey)
        defaults.removeObject(forKey: endpointKey)
        defaults.removeObject(forKey: modelKey)
        for endpoint in TypeSafeEndpoint.allCases {
            defaults.removeObject(forKey: modelCatalogKey(for: endpoint))
            KeychainHelper.delete(key: apiKeyAccount(for: endpoint))
        }
    }
}
