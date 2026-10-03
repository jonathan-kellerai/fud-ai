import Foundation

struct LoggedSet: Codable, Equatable {
    var weight: Double
    var reps: Int
    var rir: Int?
    var rpeText: String
}
