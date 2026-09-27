import Foundation

struct WeightEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    var weightKg: Double
    /// HealthKit sample UUID for rows imported from Apple Health. Nil for manual logs.
    var healthKitSampleUUID: UUID?

    init(id: UUID = UUID(), date: Date = .now, weightKg: Double, healthKitSampleUUID: UUID? = nil) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.healthKitSampleUUID = healthKitSampleUUID
    }

    var weightLbs: Double {
        weightKg * 2.20462
    }
}
