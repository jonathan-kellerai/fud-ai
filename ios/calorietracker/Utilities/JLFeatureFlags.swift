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
    /// Weekly Challenge segment on Progress.
    static let weeklyChallenge = false
    /// Legacy Fud workout logger. Shown only under Training → Advanced.
    static let legacyWorkoutLogger = true
    /// Theme color picker and alternate app icons.
    static let themeColorPicker = false
}
