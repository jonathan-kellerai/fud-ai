import Foundation

/// Lean body mass rows are imported from Apple Health
/// (HKQuantityTypeIdentifierLeanBodyMass, e.g. written by a Withings scale)
/// into WeightStore with `leanBodyMass == true`. `bodyWeightEntries` and
/// `entries(in:)` leave them out; these read them back for Progress.
extension WeightStore {
    /// Lean-mass rows, oldest first.
    var leanMassEntries: [WeightEntry] {
        ProgressBodyRows.leanMass(entries)
    }

    /// Lean-mass rows inside `range`, oldest first.
    func leanMassEntries(in range: ClosedRange<Date>) -> [WeightEntry] {
        leanMassEntries.filter { range.contains($0.date) }
    }

    var latestLeanMassEntry: WeightEntry? {
        entries.filter(\.isLeanBodyMass).max { $0.date < $1.date }
    }
}

enum ProgressBodyRows {
    static func leanMass(_ rows: [WeightEntry]) -> [WeightEntry] {
        rows.filter(\.isLeanBodyMass).sorted { $0.date < $1.date }
    }

    static func bodyWeight(_ rows: [WeightEntry]) -> [WeightEntry] {
        rows.filter { !$0.isLeanBodyMass }.sorted { $0.date < $1.date }
    }
}
