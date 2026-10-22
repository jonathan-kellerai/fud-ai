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

// MARK: - U-100 syringe units and doses left in a vial

extension PeptideMath {
    /// U-100 syringes: 100 units = 1 mL.
    static let u100UnitsPerML = 100.0

    /// mL one dose takes from `vial`: an mL dose as typed, or the dose ÷ the
    /// vial's confirmed concentration (its amount ÷ its water, same dimension;
    /// IU never becomes mass). Nil when the vial's numbers can't say.
    static func doseMilliliters(_ dose: PeptideDose, vial: PeptideVial?) -> Double? {
        drawnML(dose: dose.amount, units: dose.unit.rawValue, drawnVolume: nil, drawnUnit: nil, scale: nil, vial: vial)
    }

    /// The dose on a U-100 syringe: its mL × 100. Arithmetic on the user's
    /// own vial numbers, never a suggested dose. Nil without a concentration
    /// (an mL dose needs none).
    static func syringeUnits(_ dose: PeptideDose, vial: PeptideVial?) -> Double? {
        doseMilliliters(dose, vial: vial).map { ReconMath.clean($0 * u100UnitsPerML) }
    }

    /// A typed draw on a U-100 syringe: its mL × 100. Nil for a units draw with no scale.
    static func syringeUnits(draw: Double, unit: PeptideDrawUnit, scale: PeptideSyringeScale?) -> Double? {
        drawMilliliters(draw: draw, unit: unit, scale: scale).map { ReconMath.clean($0 * u100UnitsPerML) }
    }

    /// "30 units".
    static func syringeUnitsText(_ units: Double) -> String {
        number(units) + " units"
    }

    /// How much of one planned dose is left in a vial.
    struct VialSupply: Equatable {
        var remainingML: Double
        var totalML: Double
        var doseML: Double
        var dose: PeptideDose
        /// Whole and part doses left, e.g. 3.57.
        var dosesLeft: Double

        /// Less than one more dose in the vial.
        var remixSoon: Bool { dosesLeft < 1 - ReconMath.epsilon }

        /// "3.6 doses left (1.4 mg each)".
        var text: String {
            "\(ReconMath.fmtTrim(dosesLeft, 1)) \(abs(dosesLeft - 1) < ReconMath.epsilon ? "dose" : "doses") left (\(dose.text) each)"
        }
    }

    /// The vial's water (or, premixed, its volume) less every dose logged from
    /// it since it was mixed, in `dose`s. Never estimated: nil when any of
    /// those doses, or `dose` itself, can't be turned into mL from the
    /// vial's own numbers.
    static func supply(vial: PeptideVial, entries: [PeptideLogEntry], dose: PeptideDose) -> VialSupply? {
        guard let total = vial.diluentML, total > 0,
              let doseML = doseMilliliters(dose, vial: vial), doseML > 0 else { return nil }
        var used = 0.0
        for entry in entries where entry.vialID == vial.id && entry.countsAsTaken {
            if let mixed = vial.mixedOn, let civil = entry.civilDate, civil < mixed { continue }
            guard let volume = drawnML(for: entry, vial: vial) else { return nil }
            used += volume
        }
        let left = max(ReconMath.clean(total - used), 0)
        return VialSupply(remainingML: left, totalML: total, doseML: doseML, dose: dose, dosesLeft: ReconMath.clean(left / doseML))
    }
}

// MARK: - The day's AM / PM plan

/// One day's planned doses and reminders, in the two fixed slots.
nonisolated struct PeptideDayPlan: Equatable {
    enum Item: Equatable, Identifiable {
        case reminder(PeptideReminder)
        case dose(PeptideMath.DueItem)

        var id: String {
            switch self {
            case .reminder(let reminder): "reminder-" + reminder.id
            case .dose(let item): "dose-" + item.id
            }
        }
    }

    struct Slot: Equatable, Identifiable {
        var slot: PeptideDoseSlot
        var items: [Item]
        var id: PeptideDoseSlot { slot }
    }

    /// yyyy-MM-dd.
    var date: String
    /// AM then PM, always both.
    var slots: [Slot]

    var isEmpty: Bool { slots.allSatisfy(\.items.isEmpty) }
}

extension PeptideMath {
    /// What the user's schedules and reminders name for `date`, by slot.
    /// In each slot the reminders come first (the lab draw sits above that
    /// morning's testosterone), then doses in the order the schedules were saved.
    static func dayPlan(
        date: String,
        schedules: [PeptideUserSchedule],
        entries: [PeptideLogEntry],
        reminders: [PeptideReminder]
    ) -> PeptideDayPlan {
        let due = dueItems(date: date, schedules: schedules, entries: entries)
        let shown = reminders.filter { !$0.dismissed && $0.date == date }.sorted { $0.startMinutes < $1.startMinutes }
        let slots = PeptideDoseSlot.allCases.map { slot in
            PeptideDayPlan.Slot(
                slot: slot,
                items: shown.filter { $0.slot == slot }.map(PeptideDayPlan.Item.reminder)
                    + due.filter { $0.schedule.daySlot == slot }.map(PeptideDayPlan.Item.dose)
            )
        }
        return PeptideDayPlan(date: date, slots: slots)
    }
}

extension PeptideMath {
    /// "0.3 mL · SQ · 30 units (U-100)", "1.4 mg · 14 units (U-100)", or
    /// "No dose planned". Units only when the vial's own numbers give them.
    static func plannedDoseText(_ schedule: PeptideUserSchedule, vial: PeptideVial?) -> String {
        guard let dose = schedule.dose else { return "No dose planned" }
        var parts = [dose.text]
        if let route = schedule.route?.trimmingCharacters(in: .whitespacesAndNewlines), !route.isEmpty { parts.append(route) }
        if let units = syringeUnits(dose, vial: vial) {
            parts.append(syringeUnitsText(units) + " (U-100)")
        }
        return parts.joined(separator: " · ")
    }
}
