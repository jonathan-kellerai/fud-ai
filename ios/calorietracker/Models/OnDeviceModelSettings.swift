import Foundation

/// Settings → AI → On-device model. Off keeps today's routing for every request.
enum OnDeviceModelChoice: String, CaseIterable, Identifiable, Sendable {
    case off
    case appleFoundationModels
    case gemma4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off (cloud only)"
        case .appleFoundationModels: "Apple Foundation Models"
        case .gemma4: "Gemma 4 E2B"
        }
    }

    /// Hub row subtitle.
    var shortTitle: String {
        switch self {
        case .off: "Off · cloud only"
        case .appleFoundationModels: "Apple Foundation Models"
        case .gemma4: "Gemma 4 E2B"
        }
    }

    /// The router tier a pick maps to. Off has none.
    var tier: JevTier? {
        switch self {
        case .off: nil
        case .appleFoundationModels: .appleIntelligence
        case .gemma4: .onDevice
        }
    }
}

enum OnDeviceModelAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// Picker value plus what this iPhone can run right now.
struct OnDeviceModelState: Equatable, Sendable {
    var choice: OnDeviceModelChoice
    var apple: OnDeviceModelAvailability
    var gemma: OnDeviceModelAvailability

    /// Reads MainActor-isolated settings; the type itself is Sendable and otherwise nonisolated.
    @MainActor
    static var current: OnDeviceModelState {
        OnDeviceModelState(
            choice: OnDeviceModelSettings.choice,
            apple: OnDeviceModelSettings.appleAvailability,
            gemma: OnDeviceModelSettings.gemmaAvailability
        )
    }

    func availability(of choice: OnDeviceModelChoice) -> OnDeviceModelAvailability {
        switch choice {
        case .off: .available
        case .appleFoundationModels: apple
        case .gemma4: gemma
        }
    }
}

/// One line on the picker screen: "Fell back to <provider> last time: <reason>".
struct OnDeviceFallbackNotice: Codable, Equatable, Sendable {
    var provider: String
    var reason: String
    var date: Date

    var line: String { "Fell back to \(provider) last time: \(reason)" }

    /// First line of the error, short enough for one row.
    static func reason(for error: Error) -> String {
        let text = error.localizedDescription
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return "the on-device model failed" }
        return text.count > 100 ? String(text.prefix(99)) + "…" : text
    }
}

/// What the picker means for one request. Pure, so tests can drive it.
enum OnDeviceModelSelection: Equatable, Sendable {
    /// Picker is Off: the normal Jev tier routing decides.
    case router
    /// Image request: on-device image input isn't available on iOS 26, so the cloud config runs.
    case cloudForImage
    /// The picked on-device model answers, with the cloud config as the escalation.
    case onDevice(JevTier)
    /// The picked model can't run now. The cloud config answers and the user sees why.
    case fallBack(reason: String)
}

enum OnDeviceModelSelector {
    static func select(_ state: OnDeviceModelState, request: JevTierRequest) -> OnDeviceModelSelection {
        if request.hasImage { return .cloudForImage }
        guard let tier = state.choice.tier else { return .router }
        switch state.availability(of: state.choice) {
        case .available:
            return .onDevice(tier)
        case .unavailable(let reason):
            return .fallBack(reason: reason)
        }
    }
}

enum OnDeviceModelSettings {
    static let choiceKey = "ai.onDeviceModel.choice"
    static let lastFallbackKey = "ai.onDeviceModel.lastFallback"

    /// Missing or unknown values read as Off, so existing installs keep cloud routing.
    static var choice: OnDeviceModelChoice {
        get {
            UserDefaults.standard.string(forKey: choiceKey)
                .flatMap(OnDeviceModelChoice.init(rawValue:)) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey) }
    }

    static var lastFallback: OnDeviceFallbackNotice? {
        get {
            guard let data = UserDefaults.standard.data(forKey: lastFallbackKey) else { return nil }
            return try? JSONDecoder().decode(OnDeviceFallbackNotice.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: lastFallbackKey)
                return
            }
            UserDefaults.standard.set(data, forKey: lastFallbackKey)
        }
    }

    static var appleAvailability: OnDeviceModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceAIService.isAvailable
                ? .available
                : .unavailable(OnDeviceAIService.availabilityDescription)
        }
        #endif
        return .unavailable("Needs iOS 26 with Apple Intelligence")
    }

    static var gemmaAvailability: OnDeviceModelAvailability {
        guard Gemma4LocalModelManager.isCurrentDeviceEligible else {
            return .unavailable("Needs an iPhone with 8 GB RAM")
        }
        guard Gemma4LocalModelManager.isCurrentDeviceSelectable else {
            return .unavailable("Gemma 4 isn't downloaded and prepared yet")
        }
        return .available
    }

    static func deleteAllData() {
        UserDefaults.standard.removeObject(forKey: choiceKey)
        UserDefaults.standard.removeObject(forKey: lastFallbackKey)
    }
}
