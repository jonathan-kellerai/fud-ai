import Foundation

struct WeightEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    var weightKg: Double
    /// HealthKit sample UUID for rows imported from Apple Health. Nil for manual logs.
    var healthKitSampleUUID: UUID?
    /// Apple Health source, such as "Withings". Nil for manual logs.
    var healthSourceName: String?
    /// True for HKQuantityType leanBodyMass. Missing or false is total body weight.
    var leanBodyMass: Bool?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weightKg: Double,
        healthKitSampleUUID: UUID? = nil,
        healthSourceName: String? = nil,
        leanBodyMass: Bool? = nil
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.healthKitSampleUUID = healthKitSampleUUID
        self.healthSourceName = healthSourceName
        self.leanBodyMass = leanBodyMass
    }

    var isLeanBodyMass: Bool { leanBodyMass == true }

    var weightLbs: Double {
        weightKg * 2.20462
    }
}
