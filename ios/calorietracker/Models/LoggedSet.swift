import Foundation

struct LoggedSet: Codable, Equatable {
    enum Field: String, Codable { case load, reps, rir, rpe }

    var weight: Double
    var reps: Int
    var rir: Int?
    var rpeText: String
}
