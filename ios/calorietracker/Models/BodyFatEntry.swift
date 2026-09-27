import Foundation

/// Single body-fat reading at a point in time. Mirrors WeightEntry — stored in
/// BodyFatStore and persisted to UserDefaults as a JSON array. Manual logs and
/// Apple Health imports coexist. The latest entry's value is the user's "current" body fat % and
/// also feeds UserProfile.bodyFatPercentage for Katch-McArdle BMR; the goal
/// body fat % lives on UserProfile and is display-only (no formula impact).
struct BodyFatEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    /// Stored as a fraction (0.0–1.0), same convention as `UserProfile.bodyFatPercentage`.
    var bodyFatFraction: Double
    /// HealthKit sample UUID for rows imported from Apple Health. Nil for manual logs.
    var healthKitSampleUUID: UUID?

    init(id: UUID = UUID(), date: Date = .now, bodyFatFraction: Double, healthKitSampleUUID: UUID? = nil) {
        self.id = id
        self.date = date
        self.bodyFatFraction = bodyFatFraction
        self.healthKitSampleUUID = healthKitSampleUUID
    }

    /// Convenience for views that prefer 0–100 scale (e.g. "23%").
    var bodyFatPercent: Double { bodyFatFraction * 100 }
}
