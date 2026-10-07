import Foundation

struct LoggedSet: Codable, Equatable {
    enum Field: String, Codable, Hashable { case load, reps, rir, rpe }

    var weight: Double
    var reps: Int
    var rir: Int?
    var rpeText: String
    /// Absent in older drafts. Only user intent pins an unfinished prefill.
    var editedFields: Set<Field>? = nil

    mutating func recordEdits(from previous: LoggedSet, field: Field?) {
        var fields = editedFields ?? []
        if let field { fields.insert(field) }
        if weight != previous.weight { fields.insert(.load) }
        if reps != previous.reps { fields.insert(.reps) }
        if rir != previous.rir { fields.insert(.rir) }
        if rpeText != previous.rpeText { fields.insert(.rpe) }
        if !fields.isEmpty { editedFields = fields }
    }
}
