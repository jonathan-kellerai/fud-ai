import Foundation

/// Rest-timer defaults. Per-exercise rest still overrides `defaultSeconds`.
enum RestTimerSettings {
    static let defaultSecondsKey = "jl.restTimer.defaultSeconds"
    static let clackKey = "jl.restTimer.clack"
    static let bellKey = "jl.restTimer.bell"
    static let hapticKey = "jl.restTimer.haptic"

    static var defaultSeconds: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultSecondsKey)
            return stored > 0 ? stored : 90
        }
        set {
            UserDefaults.standard.set(max(5, newValue), forKey: defaultSecondsKey)
        }
    }

    static var clackEnabled: Bool {
        get { storedBool(clackKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: clackKey) }
    }

    static var bellEnabled: Bool {
        get { storedBool(bellKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: bellKey) }
    }

    static var hapticEnabled: Bool {
        get { storedBool(hapticKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: hapticKey) }
    }

    static var defaultRestLabel: String {
        let seconds = defaultSeconds
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func storedBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
