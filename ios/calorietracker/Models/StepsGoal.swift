import Foundation

/// One steps goal for Home and the Steps screen: the active program's daily target.
enum StepsGoal {
    static let fallback = 10_000

    static func resolved(_ target: Int?) -> Int {
        let value = target ?? 0
        return value > 0 ? value : fallback
    }

    static var current: Int {
        resolved(ActiveProgramCache.load()?.body?.dailyStepsTarget)
    }
}
