import Foundation

enum JevUse: String, CaseIterable, Codable, Sendable, Identifiable {
    case mealMatch
    case tierRouting
    case coachIntent
    case exerciseMatch
    case plausibility
    case estimateCheck

    var id: String { rawValue }

    /// Advanced AI row order. Estimate Check stays on the TypeSafe card.
    static let settingsOrder: [JevUse] = [
        .mealMatch, .coachIntent, .tierRouting, .exerciseMatch, .plausibility
    ]

    /// Exercise matching and plausibility land with their features. Until then the rows stay off.
    var isShipped: Bool {
        switch self {
        case .exerciseMatch, .plausibility: false
        case .mealMatch, .coachIntent, .tierRouting, .estimateCheck: true
        }
    }

    var title: String {
        switch self {
        case .mealMatch: "Match typed meals to saved meals"
        case .tierRouting: "Model tiers"
        case .coachIntent: "Coach shortcuts"
        case .exerciseMatch: "Exercise matching"
        case .plausibility: "Plausibility checks"
        case .estimateCheck: "Estimate Check"
        }
    }

    /// Uses 1–5 appear as toggles. Estimate Check keeps its own switch.
    var isSettingsToggle: Bool { self != .estimateCheck }

    var defaultEnabled: Bool { self != .tierRouting }
}

struct JevCredentials: Equatable, Sendable {
    let endpoint: TypeSafeEndpoint
    let apiKey: String
    let model: String

    private static let lock = NSLock()
    nonisolated(unsafe) private static var snapshot: JevCredentials?
    nonisolated(unsafe) private static var didRefresh = false

    static var current: JevCredentials? {
        lock.lock()
        let needsRefresh = !didRefresh
        lock.unlock()
        if needsRefresh { refresh() }
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    static func refresh() {
        let endpoint = TypeSafeSettings.endpoint
        let model = TypeSafeSettings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = TypeSafeSettings.apiKey(for: endpoint)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let next: JevCredentials? = (key.isEmpty || model.isEmpty)
            ? nil
            : JevCredentials(endpoint: endpoint, apiKey: key, model: model)
        lock.lock()
        snapshot = next
        didRefresh = true
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        snapshot = nil
        didRefresh = false
        lock.unlock()
    }
}

enum JevRouterSettings {
    static let enabledKey = "jevRouter.enabled"
    static let killSwitchKey = "jevRouter.killSwitch"
    static let allowOnDeviceKey = "jevRouter.tier.allowOnDevice"
    static let cheapTextModelKey = "jevRouter.tier.cheapTextModel"
    static let plausibilityTieBreakKey = "jevRouter.use.plausibility.jevTieBreak.enabled"
    static let statsKey = "jevRouter.stats.v1"
    static let exerciseAliasesKey = "jevRouter.exerciseAliases.v1"

    /// Visual QA only. Production stays on the credential gate.
    static var visualPreview = false

    static func useKey(_ use: JevUse) -> String {
        "jevRouter.use.\(use.rawValue).enabled"
    }

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var killSwitch: Bool {
        get { UserDefaults.standard.bool(forKey: killSwitchKey) }
        set { UserDefaults.standard.set(newValue, forKey: killSwitchKey) }
    }

    static var allowOnDevice: Bool {
        get { UserDefaults.standard.bool(forKey: allowOnDeviceKey) }
        set { UserDefaults.standard.set(newValue, forKey: allowOnDeviceKey) }
    }

    static var cheapTextModel: String {
        get { UserDefaults.standard.string(forKey: cheapTextModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: cheapTextModelKey) }
    }

    /// Jev tie-break for grey plausibility flags. Off until the user opts in.
    static var plausibilityTieBreak: Bool {
        get { UserDefaults.standard.bool(forKey: plausibilityTieBreakKey) }
        set { UserDefaults.standard.set(newValue, forKey: plausibilityTieBreakKey) }
    }

    static func isUseEnabled(_ use: JevUse) -> Bool {
        let key = useKey(use)
        if UserDefaults.standard.object(forKey: key) == nil { return use.defaultEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setUseEnabled(_ use: JevUse, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useKey(use))
    }

    /// Jev calls. Plausibility's free local rules use `localPlausibilityActive` instead.
    static func isActive(_ use: JevUse, credentials: JevCredentials? = nil) -> Bool {
        let creds = credentials ?? JevCredentials.current
        guard !killSwitch, creds != nil else { return false }
        if use == .estimateCheck { return TypeSafeSettings.enabled }
        if use == .plausibility { return plausibilityTieBreak }
        return enabled && isUseEnabled(use)
    }

    /// Strong and grey-candidate flags. No key and no master toggle required.
    static var localPlausibilityActive: Bool {
        !killSwitch && isUseEnabled(.plausibility)
    }

    static func deleteAllData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: killSwitchKey)
        defaults.removeObject(forKey: allowOnDeviceKey)
        defaults.removeObject(forKey: cheapTextModelKey)
        defaults.removeObject(forKey: plausibilityTieBreakKey)
        defaults.removeObject(forKey: statsKey)
        defaults.removeObject(forKey: exerciseAliasesKey)
        for use in JevUse.allCases {
            defaults.removeObject(forKey: useKey(use))
        }
        JevCredentials.clear()
        Task { await JevRouter.shared.reset() }
    }
}
