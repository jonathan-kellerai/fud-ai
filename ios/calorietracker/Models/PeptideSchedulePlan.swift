//
//  PeptideSchedulePlan.swift
//  calorietracker
//
//  The two fixed daily slots (AM / PM), the dose a user plans in a schedule,
//  and one-off reminders. Every amount is one the user typed (or their own
//  schedule preset holds); nothing here proposes or converts a dose.
//

import Foundation

/// The two fixed slots every day. Noon splits them.
nonisolated enum PeptideDoseSlot: String, Codable, CaseIterable, Identifiable {
    case am
    case pm

    var id: String { rawValue }

    /// "AM" / "PM".
    var label: String {
        switch self {
        case .am: "AM"
        case .pm: "PM"
        }
    }

    /// For VoiceOver.
    var spokenLabel: String {
        switch self {
        case .am: "morning"
        case .pm: "evening"
        }
    }

    /// AM before 12:00, PM from 12:00. No time reads as AM.
    init(minutes: Int?) {
        self = (minutes ?? 0) < 12 * 60 ? .am : .pm
    }
}

/// The unit a planned dose is typed in. Saved with the amount and never
/// converted: mL stays a volume, IU never becomes mass.
nonisolated enum PeptideDoseUnit: String, Codable, CaseIterable, Identifiable {
    case milliliters = "mL"
    case iu = "IU"
    case mg
    case mcg

    var id: String { rawValue }

    var label: String { rawValue }

    /// For VoiceOver.
    var spokenLabel: String {
        switch self {
        case .milliliters: "millilitres"
        case .iu: "international units"
        case .mg: "milligrams"
        case .mcg: "micrograms"
        }
    }
}

/// A dose as the user typed it: an amount and its unit, saved together.
nonisolated struct PeptideDose: Codable, Equatable, Hashable {
    var amount: Double
    var unit: PeptideDoseUnit

    init(amount: Double, unit: PeptideDoseUnit) {
        self.amount = amount
        self.unit = unit
    }

    /// "0.3 mL", "250 mcg".
    var text: String { PeptideMath.number(amount) + " " + unit.label }

    /// "0.3 millilitres".
    var spokenText: String { PeptideMath.number(amount) + " " + unit.spokenLabel }

    /// A typed amount and a picked unit, or nil unless the amount is a number above 0.
    static func typed(_ text: String, unit: PeptideDoseUnit?) -> PeptideDose? {
        guard let unit else { return nil }
        let value = ReconMath.toNumber(text)
        guard value.isFinite, value > 0 else { return nil }
        return PeptideDose(amount: value, unit: unit)
    }
}

/// Who made a schedule or reminder. Nil (absent) means the user typed it.
nonisolated enum PeptideRecordOrigin: String, Codable {
    /// "Load my schedule": replaced, never duplicated, when loaded again.
    case preset
}

/// A one-off reminder the user (or their schedule preset) saved for a day,
/// e.g. "Labs: draw before testosterone injection". Shown in its slot on that
/// day above the doses, until dismissed.
nonisolated struct PeptideReminder: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var title: String
    /// yyyy-MM-dd.
    var date: String
    /// Minutes after midnight, phone's local time.
    var startMinutes: Int
    var endMinutes: Int?
    var dismissed: Bool
    var origin: PeptideRecordOrigin?
    var createdAt: Date

    static let maxTitleLength = 200

    init(
        id: String = UUID().uuidString,
        title: String,
        date: String,
        startMinutes: Int,
        endMinutes: Int? = nil,
        dismissed: Bool = false,
        origin: PeptideRecordOrigin? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.dismissed = dismissed
        self.origin = origin
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, date, startMinutes, endMinutes, dismissed, origin, createdAt
    }

    /// `id`, `title`, a yyyy-MM-dd `date` and a start time within the day are required.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty id")
        }
        let date = try container.decode(String.self, forKey: .date)
        guard ReconMath.parseISO(date) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: container, debugDescription: "Not yyyy-MM-dd")
        }
        let start = try container.decode(Int.self, forKey: .startMinutes)
        guard Self.isTimeOfDay(start) else {
            throw DecodingError.dataCorruptedError(forKey: .startMinutes, in: container, debugDescription: "Not a time of day")
        }
        let end = try container.decodeIfPresent(Int.self, forKey: .endMinutes)
        self.init(
            id: id,
            title: try container.decode(String.self, forKey: .title),
            date: date,
            startMinutes: start,
            endMinutes: end.flatMap { Self.isTimeOfDay($0) ? $0 : nil },
            dismissed: (try container.decodeIfPresent(Bool.self, forKey: .dismissed)) ?? false,
            origin: try? container.decodeIfPresent(PeptideRecordOrigin.self, forKey: .origin),
            createdAt: (try container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        )
    }

    static func isTimeOfDay(_ minutes: Int) -> Bool {
        minutes >= 0 && minutes < 24 * 60
    }

    var slot: PeptideDoseSlot { PeptideDoseSlot(minutes: startMinutes) }

    /// "8:00 AM–10:00 AM", or "8:00 AM" with no end.
    var timeText: String {
        let start = PeptideMath.clockText(minutes: startMinutes)
        guard let endMinutes, endMinutes > startMinutes else { return start }
        return start + "–" + PeptideMath.clockText(minutes: endMinutes)
    }

    /// Why this reminder can't be saved, or nil when it can.
    var issue: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type what the reminder is for." }
        if trimmed.count > Self.maxTitleLength { return "The reminder is longer than \(Self.maxTitleLength) characters." }
        if ReconMath.parseISO(date) == nil { return "Pick a date." }
        if !Self.isTimeOfDay(startMinutes) { return "Pick a start time." }
        if let endMinutes, endMinutes <= startMinutes { return "The end time is before the start time." }
        return nil
    }
}

/// One local notification for a reminder: when, in the phone's own calendar.
nonisolated struct PeptideReminderNotificationPlan: Equatable {
    static let idPrefix = "peptide.reminder."

    var id: String
    var title: String
    var body: String
    /// Year, month, day, hour and minute in the phone's calendar.
    var fireAt: DateComponents
}

extension PeptideReminder {
    /// The local notification for each reminder that isn't dismissed and
    /// whose start time (on its date, in `calendar`) is still ahead of `now`.
    static func notificationPlans(_ reminders: [PeptideReminder], now: Date, calendar: Calendar = .current) -> [PeptideReminderNotificationPlan] {
        reminders.compactMap { reminder in
            guard !reminder.dismissed, let parts = ReconMath.parseISO(reminder.date) else { return nil }
            var components = DateComponents()
            components.year = parts.year
            components.month = parts.month
            components.day = parts.day
            components.hour = reminder.startMinutes / 60
            components.minute = reminder.startMinutes % 60
            guard let fire = calendar.date(from: components), fire > now else { return nil }
            return PeptideReminderNotificationPlan(
                id: PeptideReminderNotificationPlan.idPrefix + reminder.id,
                title: "Peptides reminder",
                body: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines) + " · " + reminder.timeText,
                fireAt: components
            )
        }
    }
}
