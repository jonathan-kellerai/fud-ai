import Foundation

/// Compile-time switches for Fud-hosted and Fud-marketing surfaces.
/// Hidden screens keep their stored values. Flip a flag to bring a surface back.
enum JLFeatureFlags {
    /// Fud Hosted AI, AI Access, the paywall, and the launch upsell.
    static let fudHostedAI = false
    /// Tip Jar, Community, Product Hunt, Meet the Developer, and Fud legal pages.
    static let fudMarketing = false
    /// Fud App Store update check, the More-tab badge, and the App Updates reminder.
    static let fudUpdateCheck = false
    /// Legacy Fud workout logger. Shown only under Training → Advanced.
    static let legacyWorkoutLogger = true
    /// Theme color picker and alternate app icons.
    static let themeColorPicker = false

    /// UserDefaults key for the runtime Challenges switch (D64-1). Absent means on.
    nonisolated static let challengesKey = "jl.flags.challenges"

    /// Challenges list, Home card, More row and reminders. Runtime, not compile-time:
    /// writing `false` to `jl.flags.challenges` hides the surface without a new build.
    nonisolated static var challengesEnabled: Bool {
        challengesEnabled(in: .standard)
    }

    nonisolated static func challengesEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: challengesKey) as? Bool ?? true
    }
}
