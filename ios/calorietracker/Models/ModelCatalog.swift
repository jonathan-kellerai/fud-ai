import Foundation

/// A model returned by a provider's list endpoint, plus the bundled presets
/// shown ahead of that list.
struct CatalogModel: Equatable, Identifiable, Codable {
    var id: String
    var createdAt: Date?
    /// `.textOnly` is hidden from the photo picker. `.unverified` stays visible
    /// with an "image support unverified" tag.
    var vision: CatalogVision
}

enum CatalogVision: String, Equatable, Codable {
    case supported
    case unverified
    case textOnly
}

struct CatalogPage: Equatable {
    var models: [CatalogModel]
    var nextCursor: String?
}

enum ModelCatalogCopy {
    static let couldNotRefresh = "Couldn't refresh the model list."
    static let imageSupportUnverified = "image support unverified"
}

enum ModelCatalogCachePolicy {
    /// A saved list older than this is fetched again the next time the picker opens.
    static let ttl: TimeInterval = 24 * 60 * 60

    static func isExpired(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > ttl
    }
}

struct ModelPickerSections: Equatable {
    var recommended: [CatalogModel]
    var discovered: [CatalogModel]
}

enum ModelCatalogLogic {
    /// OpenAI and Anthropic list endpoints omit modality, and their current
    /// models accept images. Every other provider without modality data stays
    /// unverified so the row is shown instead of hidden.
    static func visionSupport(provider: AIProvider, modalities: [String]?) -> CatalogVision {
        if let modalities {
            let acceptsImage = modalities.contains { modality in
                modality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "image"
            }
            return acceptsImage ? .supported : .textOnly
        }
        switch provider {
        case .openai, .anthropic:
            return .supported
        default:
            return .unverified
        }
    }

    static func sections(
        presets: [String],
        discovered: [CatalogModel],
        presetVision: (String) -> CatalogVision = { _ in .supported },
        visionOnly: Bool,
        excludedModelIDs: Set<String> = []
    ) -> ModelPickerSections {
        var discoveredByID: [String: CatalogModel] = [:]
        for model in discovered where discoveredByID[model.id] == nil {
            discoveredByID[model.id] = model
        }

        var recommended: [CatalogModel] = []
        var seen: Set<String> = []
        for preset in presets where !excludedModelIDs.contains(preset) && seen.insert(preset).inserted {
            let match = discoveredByID[preset]
            let vision = match?.vision ?? presetVision(preset)
            let row = CatalogModel(id: preset, createdAt: match?.createdAt, vision: vision)
            if visionOnly && row.vision == .textOnly { continue }
            recommended.append(row)
        }

        let recommendedIDs = Set(recommended.map(\.id))
        let extras = discovered.filter { model in
            !recommendedIDs.contains(model.id)
                && !excludedModelIDs.contains(model.id)
                && !(visionOnly && model.vision == .textOnly)
        }
        let sorted = extras.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (left?, right?):
                if left != right { return left > right }
                return lhs.id < rhs.id
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.id < rhs.id
            }
        }
        var discoveredRows: [CatalogModel] = []
        var discoveredIDs: Set<String> = []
        for model in sorted where discoveredIDs.insert(model.id).inserted {
            discoveredRows.append(model)
        }
        return ModelPickerSections(recommended: recommended, discovered: discoveredRows)
    }

    static func matches(_ model: CatalogModel, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return model.id.localizedCaseInsensitiveContains(trimmed)
    }
}

enum ModelCatalogParser {
    static func parseOpenAICompatible(_ data: Data, provider: AIProvider) throws -> CatalogPage {
        let json = try jsonObject(data)
        let rows = json["data"] as? [[String: Any]] ?? []
        let models = rows.compactMap { row -> CatalogModel? in
            guard let id = nonEmptyString(row["id"]) else { return nil }
            let modalities = modalities(in: row["architecture"] as? [String: Any])
            return CatalogModel(
                id: id,
                createdAt: unixDate(row["created"]),
                vision: ModelCatalogLogic.visionSupport(provider: provider, modalities: modalities)
            )
        }
        let next = (json["has_more"] as? Bool) == true ? nonEmptyString(json["last_id"]) : nil
        return CatalogPage(models: models, nextCursor: next)
    }

    static func parseAnthropic(_ data: Data) throws -> CatalogPage {
        let json = try jsonObject(data)
        let rows = json["data"] as? [[String: Any]] ?? []
        let models = rows.compactMap { row -> CatalogModel? in
            guard let id = nonEmptyString(row["id"]) else { return nil }
            return CatalogModel(
                id: id,
                createdAt: iso8601Date(nonEmptyString(row["created_at"])),
                vision: ModelCatalogLogic.visionSupport(provider: .anthropic, modalities: nil)
            )
        }
        let next = (json["has_more"] as? Bool) == true ? nonEmptyString(json["last_id"]) : nil
        return CatalogPage(models: models, nextCursor: next)
    }

    static func parseGemini(_ data: Data) throws -> CatalogPage {
        let json = try jsonObject(data)
        let rows = json["models"] as? [[String: Any]] ?? []
        let models = rows.compactMap { row -> CatalogModel? in
            guard let name = nonEmptyString(row["name"]) else { return nil }
            let methods = row["supportedGenerationMethods"] as? [String] ?? []
            guard methods.contains("generateContent") else { return nil }
            let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            guard !id.isEmpty else { return nil }
            let modalities = stringList(row["inputModalities"]) ?? stringList(row["supportedInputModalities"])
            return CatalogModel(
                id: id,
                createdAt: nil,
                vision: ModelCatalogLogic.visionSupport(provider: .gemini, modalities: modalities)
            )
        }
        return CatalogPage(models: models, nextCursor: nonEmptyString(json["nextPageToken"]))
    }

    /// Pages are applied in order. A later page does not replace an id already seen.
    static func combining(_ pages: [CatalogPage]) -> [CatalogModel] {
        var combined: [CatalogModel] = []
        var seen: Set<String> = []
        for page in pages {
            for model in page.models where seen.insert(model.id).inserted {
                combined.append(model)
            }
        }
        return combined
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogParseError.notAnObject
        }
        return json
    }

    private static func modalities(in architecture: [String: Any]?) -> [String]? {
        guard let architecture else { return nil }
        return stringList(architecture["input_modalities"])
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let values = value as? [String] else { return nil }
        return values
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unixDate(_ value: Any?) -> Date? {
        if let seconds = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if let seconds = value as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = value as? NSNumber {
            return Date(timeIntervalSince1970: seconds.doubleValue)
        }
        return nil
    }

    private static func iso8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

enum CatalogParseError: Error {
    case notAnObject
}
