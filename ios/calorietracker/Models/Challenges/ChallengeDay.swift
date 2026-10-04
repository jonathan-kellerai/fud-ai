import Foundation

/// A calendar day for Challenges: year, month and day in the Gregorian calendar.
///
/// Days are bucketed in the caller's calendar time zone at evaluation time
/// (production passes `Calendar.current`, like Progress and Home). Counting and
/// stepping use day numbers, never 86,400-second arithmetic, so DST changes
/// can't merge or split days. Challenge-only; unrelated to `StrengthWorkoutDate`.
nonisolated struct ChallengeDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone (always Gregorian fields).
    init(_ date: Date, calendar: Calendar) {
        let parts = Self.gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Strict `yyyy-MM-dd`; rejects anything that isn't a real date.
    init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard string.count == 10, parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1, day <= Self.daysInMonth(year: year, month: month) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    var string: String {
        let y = String(year)
        let m = month < 10 ? "0\(month)" : String(month)
        let d = day < 10 ? "0\(day)" : String(day)
        return "\(String(repeating: "0", count: max(0, 4 - y.count)))\(y)-\(m)-\(d)"
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    func startDate(in calendar: Calendar) -> Date? {
        let gregorian = Self.gregorian(like: calendar)
        guard let noon = gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            return nil
        }
        return gregorian.startOfDay(for: noon)
    }

    func adding(days: Int) -> ChallengeDay {
        Self(dayNumber: dayNumber + days)
    }

    /// Whole calendar days from `start` to `end` (negative when `end` is earlier).
    static func days(from start: ChallengeDay, to end: ChallengeDay) -> Int {
        end.dayNumber - start.dayNumber
    }

    static func < (lhs: ChallengeDay, rhs: ChallengeDay) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }

    // MARK: - Day numbers (proleptic Gregorian, days since 1970-01-01)

    private var dayNumber: Int {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private init(dayNumber: Int) {
        // Howard Hinnant's civil_from_days.
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func gregorian(like calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}

nonisolated extension ChallengeDay: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = ChallengeDay(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad challenge day \(raw)")
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// Lets `[ChallengeDay: Bool]` encode as a JSON object keyed by `yyyy-MM-dd`.
nonisolated extension ChallengeDay: CodingKeyRepresentable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    var codingKey: CodingKey { Key(stringValue: string) }

    init?<T: CodingKey>(codingKey: T) {
        self.init(string: codingKey.stringValue)
    }
}
