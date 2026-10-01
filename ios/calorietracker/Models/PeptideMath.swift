//
//  PeptideMath.swift
//  calorietracker
//
//  Pure Peptides arithmetic. Every figure comes from numbers the user typed
//  (vial amount, diluent volume, drawn volume, logged amounts). Nothing here
//  proposes a dose, amount, protocol or schedule. IU is never converted to mass.
//

import Foundation

nonisolated enum PeptideMath {
    static let footerText = "Logs what you enter. Sets no doses and recommends no protocol."
    /// Amount units the log sheet offers. "units" are U-100 syringe units.
    static let unitOptions = ["mcg", "mg", "IU", "mL", "units"]
    static let vialUnitOptions = ["mg", "mcg", "IU"]
    static let siteOptions = ["Abdomen L", "Abdomen R", "Thigh L", "Thigh R", "Glute L", "Glute R", "Delt L", "Delt R"]
    /// Low stock without a user threshold: at or under 20% of the diluent volume.
    static let defaultLowFraction = 0.2
    static let glowName = "Glow"
    static let glowSubtitle = "GHK-Cu / BPC-157 / TB-500"
    /// Component names only. The user types every amount.
    static let glowComponentNames = ["GHK-Cu", "BPC-157", "TB-500"]
    static let newYork = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: 0)!
    static let maxCompoundLength = 200
    static let maxUnitsLength = 20
    static let maxRouteLength = 200
    static let maxNotesLength = 5000

    // MARK: - Compound matching

    private static let aliases: [String: String] = [
        "mt2": "mt2",
        "mtii": "mt2",
        "melanotan2": "mt2",
        "melanotanii": "mt2",
        "glow": "glow",
        "glowblend": "glow",
        "kisspeptin": "kisspeptin",
        "kisspeptin10": "kisspeptin",
        "kp10": "kisspeptin",
        "nadplus": "nad",
    ]

    /// Lower-cased letters and digits only, with a few aliases folded together.
    /// "BPC-157" == "bpc157" == "BPC 157"; "Melanotan II" == "MT-2" == "mt2".
    static func compoundKey(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let key = String(folded.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        return aliases[key] ?? key
    }

    static func sameCompound(_ lhs: String, _ rhs: String) -> Bool {
        let left = compoundKey(lhs)
        return !left.isEmpty && left == compoundKey(rhs)
    }

    /// Victoria's starting list: exactly MT2 and Glow.
    static func defaultCompounds(person: String) -> [String] {
        if PeptidePerson.normalized(person) == PeptidePerson.victoria {
            return ["MT2", glowName]
        }
        return (ReconMath.roster[PeptidePerson.jonathan] ?? []).compactMap { ReconMath.compounds[$0]?.name }
    }

    /// Compound chips for the log sheet. Agent inventory names replace a matching
    /// default so the bridge gets the assistant's exact string. De-duplicated by key.
    static func compoundOptions(person: String, inventoryCompounds: [String], loggedCompounds: [String]) -> [String] {
        var options = defaultCompounds(person: person)
        let isJonathan = PeptidePerson.normalized(person) == PeptidePerson.jonathan
        if isJonathan {
            for name in inventoryCompounds {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if let index = options.firstIndex(where: { sameCompound($0, trimmed) }) {
                    options[index] = trimmed
                } else {
                    options.append(trimmed)
                }
            }
        }
        for name in loggedCompounds {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !options.contains(where: { sameCompound($0, trimmed) }) else { continue }
            options.append(trimmed)
        }
        return options
    }

    /// Single-component vials name the amount unit; blends do not.
    static func defaultUnits(for vial: PeptideVial?) -> String? {
        guard let vial, !vial.isBlend, vial.components.count == 1 else { return nil }
        let unit = vial.components[0].unit
        return unitOptions.contains(unit) ? unit : nil
    }

    // MARK: - Validation

    static func validate(_ draft: PeptideLogDraft) -> [PeptideDraftField: String] {
        var issues: [PeptideDraftField: String] = [:]
        let compound = draft.trimmedCompound
        if compound.isEmpty {
            issues[.compound] = "Pick or type a compound."
        } else if compound.count > maxCompoundLength {
            issues[.compound] = "Compound is longer than \(maxCompoundLength) characters."
        }
        if draft.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues[.amount] = "Type the amount you took."
        } else if let amount = draft.amount {
            if !(amount > 0) { issues[.amount] = "Amount must be more than 0." }
        } else {
            issues[.amount] = "Amount must be a number."
        }
        if let units = draft.units {
            if !unitOptions.contains(units) || units.count > maxUnitsLength {
                issues[.units] = "Pick the units."
            }
        } else {
            issues[.units] = "Pick the units."
        }
        if !draft.drawnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let drawn = draft.drawnVolume {
                if !(drawn > 0) {
                    issues[.drawn] = "Drawn volume must be more than 0."
                } else if draft.drawnUnit != "mL" && draft.drawnUnit != "units" {
                    issues[.drawn] = "Pick mL or units for the drawn volume."
                }
            } else {
                issues[.drawn] = "Drawn volume must be a number."
            }
        }
        if draft.trimmedSite.count > maxRouteLength {
            issues[.site] = "Site is longer than \(maxRouteLength) characters."
        }
        if draft.trimmedNotes.count > maxNotesLength {
            issues[.notes] = "Notes are longer than \(maxNotesLength) characters."
        }
        return issues
    }

    // MARK: - Concentration and volume

    struct ComponentConcentration: Equatable, Identifiable {
        var name: String
        /// Amount per mL in the component's own unit.
        var perML: Double
        var unit: String
        var id: String { name + "|" + unit }

        var text: String { ReconMath.fmtTrim(perML, 3) + " " + unit + "/mL" }
    }

    enum Concentration: Equatable {
        case calculable([ComponentConcentration])
        case uncalculable(String)

        var reason: String? {
            if case .uncalculable(let reason) = self { return reason }
            return nil
        }

        var components: [ComponentConcentration] {
            if case .calculable(let list) = self { return list }
            return []
        }
    }

    /// Per component per mL, only from a confirmed mix with every number present.
    static func concentration(_ vial: PeptideVial) -> Concentration {
        guard vial.concentrationConfirmed else {
            return .uncalculable("Concentration not confirmed. Tick “I mixed this vial with exactly this diluent volume.”")
        }
        guard let diluent = vial.diluentML, diluent > 0 else {
            return .uncalculable("Diluent volume is missing.")
        }
        guard !vial.components.isEmpty else {
            return .uncalculable("No amount in the vial is entered.")
        }
        var result: [ComponentConcentration] = []
        for component in vial.components {
            let name = component.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? vial.displayName : name
            guard let amount = component.amount, amount > 0 else {
                return .uncalculable("Amount in vial is missing for \(label).")
            }
            guard ReconMath.normalize(amount: amount, unit: component.unit) != nil else {
                return .uncalculable("Unit for \(label) must be mg, mcg or IU.")
            }
            result.append(ComponentConcentration(name: label, perML: ReconMath.clean(amount / diluent), unit: component.unit))
        }
        return .calculable(result)
    }

    /// Volume drawn for one administration, in mL. Nil when it can't be known
    /// from the user's own numbers.
    static func drawnML(
        dose: Double?,
        units: String?,
        drawnVolume: Double?,
        drawnUnit: String?,
        vial: PeptideVial?
    ) -> Double? {
        if let drawnVolume, drawnVolume > 0 {
            return drawnUnit == "units" ? ReconMath.clean(drawnVolume / 100) : drawnVolume
        }
        guard let dose, dose > 0, let units else { return nil }
        if units == "mL" { return dose }
        if units == "units" { return ReconMath.clean(dose / 100) }
        guard let vial, !vial.isBlend, vial.components.count == 1,
              case .calculable = concentration(vial),
              let diluent = vial.diluentML, diluent > 0,
              let amount = vial.components[0].amount, amount > 0,
              let vialNormalized = ReconMath.normalize(amount: amount, unit: vial.components[0].unit),
              let doseNormalized = ReconMath.normalize(amount: dose, unit: units),
              doseNormalized.dimension == vialNormalized.dimension,
              vialNormalized.value > 0 else {
            return nil
        }
        return ReconMath.clean(doseNormalized.value * diluent / vialNormalized.value)
    }

    static func drawnML(for entry: PeptideLogEntry, vial: PeptideVial?) -> Double? {
        drawnML(dose: entry.dose, units: entry.units, drawnVolume: entry.drawnVolume, drawnUnit: entry.drawnUnit, vial: vial)
    }

    struct Remaining: Equatable {
        var calculable: Bool
        var reason: String?
        var remainingML: Double?
        var totalML: Double?
        var fraction: Double?
        var isLow: Bool
        var linkedCount: Int

        static func uncalculable(_ reason: String, linkedCount: Int) -> Remaining {
            Remaining(calculable: false, reason: reason, remainingML: nil, totalML: nil, fraction: nil, isLow: false, linkedCount: linkedCount)
        }
    }

    /// Diluent minus every drawn volume logged from this vial. Never estimated:
    /// one unknown draw makes the whole figure uncalculable.
    /// `incompleteHistory`: some bridge rows couldn't be read, so a dose from
    /// this vial may be missing and the figure would look larger than it is.
    static let incompleteHistoryReason = "Some bridge rows couldn't be read, so a dose from this vial may be missing."

    static func remaining(vial: PeptideVial, entries: [PeptideLogEntry], incompleteHistory: Bool = false) -> Remaining {
        let linked = entries.filter { $0.vialID == vial.id && $0.countsAsTaken }
        if case .uncalculable(let reason) = concentration(vial) {
            return .uncalculable(reason, linkedCount: linked.count)
        }
        if incompleteHistory {
            return .uncalculable(incompleteHistoryReason, linkedCount: linked.count)
        }
        guard let diluent = vial.diluentML, diluent > 0 else {
            return .uncalculable("Diluent volume is missing.", linkedCount: linked.count)
        }
        var drawn = 0.0
        for entry in linked {
            guard let volume = drawnML(for: entry, vial: vial) else {
                let when = entry.date.map(shortDateTime) ?? entry.datetimeRaw
                return .uncalculable(
                    "The \(when) dose (\(amountText(entry.dose, entry.units))) has no drawn volume and can't be converted from this vial.",
                    linkedCount: linked.count
                )
            }
            drawn += volume
        }
        let left = max(ReconMath.clean(diluent - drawn), 0)
        let threshold = vial.lowStockThresholdML.flatMap { $0 > 0 ? $0 : nil } ?? diluent * defaultLowFraction
        return Remaining(
            calculable: true,
            reason: nil,
            remainingML: left,
            totalML: diluent,
            fraction: min(max(left / diluent, 0), 1),
            isLow: left <= threshold + ReconMath.epsilon,
            linkedCount: linked.count
        )
    }

    // MARK: - Formatting

    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value.rounded() == value, abs(value) < 1_000_000 {
            return String(Int(value))
        }
        var text = String(format: "%.4f", value)
        while text.contains("."), text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Amount and units exactly as stored.
    static func amountText(_ dose: Double?, _ units: String?) -> String {
        let parts = [dose.map(number) ?? "", units ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? "no amount" : parts.joined(separator: " ")
    }

    static func mlText(_ value: Double) -> String {
        ReconMath.fmtTrim(value, 2) + " mL"
    }

    static func frequencyText(_ frequency: ReconMath.Frequency) -> String {
        if frequency.type == "perWeek" {
            let count = Int(frequency.n ?? 0)
            return count == 1 ? "1× per week" : "\(count)× per week"
        }
        let text = ReconMath.frequencyText(frequency)
        return text.isEmpty ? "—" : text
    }

    static func scheduleText(_ schedule: PeptideUserSchedule) -> String {
        var parts: [String] = []
        if schedule.amount != nil || !(schedule.units ?? "").isEmpty {
            parts.append(amountText(schedule.amount, schedule.units))
        }
        parts.append(frequencyText(schedule.frequency))
        if let minutes = schedule.timeOfDay {
            parts.append("at " + clockText(minutes: minutes))
        }
        return parts.joined(separator: " · ")
    }

    static func clockText(minutes: Int) -> String {
        let clamped = max(0, min(minutes, 24 * 60 - 1))
        let hour = clamped / 60
        let minute = clamped % 60
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", displayHour, minute, hour < 12 ? "AM" : "PM")
    }

    // MARK: - Dates (America/New_York)

    static let newYorkCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func civilDate(_ date: Date) -> String {
        let parts = newYorkCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Noon on a civil date in New York (safe for display and DatePicker).
    static func date(civil: String, minutes: Int = 12 * 60) -> Date? {
        guard let parts = ReconMath.parseISO(civil) else { return nil }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = minutes / 60
        components.minute = minutes % 60
        return newYorkCalendar.date(from: components)
    }

    static func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func iso8601NewYork(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = newYork
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = newYork
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date) + " ET"
    }

    static func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = newYork
        formatter.dateFormat = "EEE d MMM h:mm a"
        return formatter.string(from: date)
    }

    /// Days since 1970-01-01 for a civil date.
    static func dayIndex(_ iso: String) -> Int? {
        guard let parts = ReconMath.parseISO(iso) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? newYork
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        return Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let start = dayIndex(from), let end = dayIndex(to) else { return nil }
        return end - start
    }

    // MARK: - Schedules and adherence

    /// Civil dates the user's schedule names between `from` and `to` (inclusive).
    /// "perWeek" schedules have no fixed dates and return none.
    static func occurrences(_ schedule: PeptideUserSchedule, from: String, to: String) -> [String] {
        guard schedule.active, ReconMath.parseISO(schedule.startDate) != nil,
              ReconMath.parseISO(from) != nil, ReconMath.parseISO(to) != nil else { return [] }
        var first = max(from, schedule.startDate)
        var last = to
        if let end = schedule.endDate, ReconMath.parseISO(end) != nil, end < last { last = end }
        guard first <= last, let span = daysBetween(first, last) else { return [] }
        if span > 800 { first = ReconMath.addDays(last, -800) }
        var dates: [String] = []
        var cursor = first
        while cursor <= last {
            if includes(schedule.frequency, date: cursor, start: schedule.startDate) {
                dates.append(cursor)
            }
            cursor = ReconMath.addDays(cursor, 1)
        }
        return dates
    }

    static func includes(_ frequency: ReconMath.Frequency, date: String, start: String) -> Bool {
        guard let offset = daysBetween(start, date), offset >= 0 else { return false }
        switch frequency.type {
        case "daily":
            return true
        case "weekly":
            return offset % 7 == 0
        case "weekdays":
            return frequency.days.contains(ReconMath.weekday(date))
        case "everyN":
            guard let interval = frequency.n, interval >= 1, interval == interval.rounded(), interval < 10_000 else { return false }
            return offset % Int(interval) == 0
        default:
            return false
        }
    }

    static func takenDates(person: String, compound: String, entries: [PeptideLogEntry]) -> Set<String> {
        let key = compoundKey(compound)
        let owner = PeptidePerson.normalized(person)
        var dates = Set<String>()
        for entry in entries where entry.countsAsTaken
            && PeptidePerson.normalized(entry.person) == owner
            && compoundKey(entry.compound) == key {
            if let civil = entry.civilDate { dates.insert(civil) }
        }
        return dates
    }

    struct Adherence: Equatable {
        /// Scheduled dates that have passed, plus today when it is already logged.
        var due: Int
        var taken: Int
        var missedDates: [String]
        var todayDue: Bool
        var todayTaken: Bool
        var streak: Int

        var percent: Double? {
            guard due > 0 else { return nil }
            return Double(taken) / Double(due)
        }

        var percentText: String {
            guard let percent else { return "—" }
            return String(Int((percent * 100).rounded())) + "%"
        }
    }

    static func adherence(
        _ schedule: PeptideUserSchedule,
        entries: [PeptideLogEntry],
        from: String,
        to: String,
        today: String
    ) -> Adherence {
        let taken = takenDates(person: schedule.person, compound: schedule.compound, entries: entries)
        if schedule.frequency.type == "perWeek" {
            var weekly = perWeekAdherence(schedule, entries: entries, from: from, to: min(to, today), today: today)
            weekly.streak = currentStreak(schedule, entries: entries, today: today)
            return weekly
        }
        let dates = occurrences(schedule, from: from, to: min(to, today))
        var result = Adherence(due: 0, taken: 0, missedDates: [], todayDue: false, todayTaken: false, streak: 0)
        for date in dates {
            let done = taken.contains(date)
            if date == today {
                result.todayDue = true
                result.todayTaken = done
                if done {
                    result.due += 1
                    result.taken += 1
                }
            } else if done {
                result.due += 1
                result.taken += 1
            } else {
                result.due += 1
                result.missedDates.append(date)
            }
        }
        result.streak = currentStreak(schedule, entries: entries, today: today)
        return result
    }

    /// How far back the current streak looks, independent of report windows.
    static let streakLookbackDays = 400

    /// Consecutive scheduled occurrences (or full weeks for "perWeek") logged,
    /// walking backward from today. Today (or this week) never breaks it.
    static func currentStreak(_ schedule: PeptideUserSchedule, entries: [PeptideLogEntry], today: String) -> Int {
        guard schedule.active, ReconMath.parseISO(schedule.startDate) != nil, ReconMath.parseISO(today) != nil else { return 0 }
        let floor = max(schedule.startDate, ReconMath.addDays(today, -streakLookbackDays))
        guard floor <= today else { return 0 }
        if schedule.frequency.type == "perWeek" {
            let perWeek = Int(schedule.frequency.n ?? 0)
            guard perWeek > 0 else { return 0 }
            let currentWeek = ReconMath.mondayOf(today)
            let firstWeek = ReconMath.mondayOf(floor)
            var week = currentWeek
            var streak = 0
            var guardCount = 0
            while week >= firstWeek && guardCount < 60 {
                let count = perWeekCount(schedule, entries: entries, weekStart: week, from: floor, to: today)
                if week == currentWeek {
                    if count >= perWeek { streak += 1 }
                } else {
                    let due = perWeekDue(schedule, weekStart: week, from: floor, to: today)
                    if due > 0 && count >= due {
                        streak += 1
                    } else {
                        break
                    }
                }
                week = ReconMath.addDays(week, -7)
                guardCount += 1
            }
            return streak
        }
        let taken = takenDates(person: schedule.person, compound: schedule.compound, entries: entries)
        var streak = 0
        for date in occurrences(schedule, from: floor, to: today).reversed() {
            if taken.contains(date) {
                streak += 1
            } else if date == today {
                continue
            } else {
                break
            }
        }
        return streak
    }

    /// Civil dates of the Monday-start week of `weekStart` that fall inside
    /// both [from, to] and the schedule's start/end. Nil when none do.
    private static func perWeekSpan(
        _ schedule: PeptideUserSchedule,
        weekStart: String,
        from lower: String,
        to upper: String
    ) -> (first: String, last: String)? {
        let first = max(weekStart, schedule.startDate, lower)
        var last = min(ReconMath.addDays(weekStart, 6), upper)
        if let end = schedule.endDate, ReconMath.parseISO(end) != nil, end < last { last = end }
        guard first <= last else { return nil }
        return (first, last)
    }

    /// "n times per week" occurrence counter, shared by adherence, streak and
    /// the due list: distinct logged administrations (two on one day count as
    /// two) on dates inside the week, the schedule's start/end and [from, to],
    /// capped at n.
    static func perWeekCount(
        _ schedule: PeptideUserSchedule,
        entries: [PeptideLogEntry],
        weekStart: String,
        from lower: String,
        to upper: String
    ) -> Int {
        let perWeek = Int(schedule.frequency.n ?? 0)
        guard perWeek > 0, let span = perWeekSpan(schedule, weekStart: weekStart, from: lower, to: upper) else { return 0 }
        let key = compoundKey(schedule.compound)
        let owner = PeptidePerson.normalized(schedule.person)
        var count = 0
        for entry in entries where entry.countsAsTaken
            && PeptidePerson.normalized(entry.person) == owner
            && compoundKey(entry.compound) == key {
            guard let civil = entry.civilDate, civil >= span.first, civil <= span.last else { continue }
            count += 1
        }
        return min(count, perWeek)
    }

    /// Doses due in one past week: n, or fewer when only part of the week is
    /// inside the schedule and the reporting window (never more than the days
    /// available).
    static func perWeekDue(_ schedule: PeptideUserSchedule, weekStart: String, from lower: String, to upper: String) -> Int {
        let perWeek = Int(schedule.frequency.n ?? 0)
        guard perWeek > 0, let span = perWeekSpan(schedule, weekStart: weekStart, from: lower, to: upper),
              let days = daysBetween(span.first, span.last) else { return 0 }
        return min(perWeek, days + 1)
    }

    /// "n times per week": each past Monday-start week is due n (fewer for a
    /// partial boundary week); the current week only counts what is logged.
    private static func perWeekAdherence(
        _ schedule: PeptideUserSchedule,
        entries: [PeptideLogEntry],
        from: String,
        to: String,
        today: String
    ) -> Adherence {
        var result = Adherence(due: 0, taken: 0, missedDates: [], todayDue: false, todayTaken: false, streak: 0)
        let perWeek = Int(schedule.frequency.n ?? 0)
        guard schedule.active, perWeek > 0, ReconMath.parseISO(schedule.startDate) != nil else { return result }
        let lower = max(from, schedule.startDate)
        var upper = to
        if let end = schedule.endDate, ReconMath.parseISO(end) != nil, end < upper { upper = end }
        guard lower <= upper else { return result }
        var week = ReconMath.mondayOf(lower)
        let currentWeek = ReconMath.mondayOf(today)
        var guardCount = 0
        while week <= upper && guardCount < 120 {
            let count = perWeekCount(schedule, entries: entries, weekStart: week, from: lower, to: upper)
            if week >= currentWeek {
                result.due += count
                result.taken += count
                if today >= lower && today <= upper {
                    let soFar = perWeekCount(schedule, entries: entries, weekStart: week, from: schedule.startDate, to: today)
                    result.todayDue = soFar < perWeek
                    result.todayTaken = takenDates(person: schedule.person, compound: schedule.compound, entries: entries).contains(today)
                }
            } else {
                let due = perWeekDue(schedule, weekStart: week, from: lower, to: upper)
                result.due += due
                result.taken += min(count, due)
                if count < due { result.missedDates.append(week) }
            }
            week = ReconMath.addDays(week, 7)
            guardCount += 1
        }
        return result
    }

    struct DueItem: Identifiable, Equatable {
        var schedule: PeptideUserSchedule
        var taken: Bool
        /// For "perWeek" schedules: logged so far this week.
        var weekCount: Int?
        var id: String { schedule.id }
    }

    /// Items the user's own schedules name for `date`.
    static func dueItems(date: String, person: String, schedules: [PeptideUserSchedule], entries: [PeptideLogEntry]) -> [DueItem] {
        let owner = PeptidePerson.normalized(person)
        var items: [DueItem] = []
        for schedule in schedules where schedule.active && PeptidePerson.normalized(schedule.person) == owner {
            let taken = takenDates(person: schedule.person, compound: schedule.compound, entries: entries)
            if schedule.frequency.type == "perWeek" {
                guard date >= schedule.startDate, schedule.endDate.map({ date <= $0 }) ?? true else { continue }
                let monday = ReconMath.mondayOf(date)
                let weekCount = perWeekCount(
                    schedule,
                    entries: entries,
                    weekStart: monday,
                    from: schedule.startDate,
                    to: ReconMath.addDays(monday, 6)
                )
                let perWeek = Int(schedule.frequency.n ?? 0)
                if weekCount < perWeek || taken.contains(date) {
                    items.append(DueItem(schedule: schedule, taken: taken.contains(date), weekCount: weekCount))
                }
            } else if !occurrences(schedule, from: date, to: date).isEmpty {
                items.append(DueItem(schedule: schedule, taken: taken.contains(date), weekCount: nil))
            }
        }
        return items
    }

    /// Bridge PLANNED rows: taken once the assistant's row has a completed_id.
    static func plannedAdherence(_ entries: [PeptideLogEntry], person: String, through today: String) -> (due: Int, taken: Int) {
        let owner = PeptidePerson.normalized(person)
        var due = 0
        var taken = 0
        for entry in entries where entry.isPlanned && !entry.voided && PeptidePerson.normalized(entry.person) == owner {
            guard let civil = entry.civilDate, civil <= today else { continue }
            due += 1
            if entry.completedID != nil { taken += 1 }
        }
        return (due, taken)
    }

    // MARK: - Summaries

    struct CompoundTotal: Identifiable, Equatable {
        var compound: String
        var units: String
        var total: Double
        var count: Int
        var id: String { PeptideMath.compoundKey(compound) + "|" + units }

        var text: String {
            units.isEmpty ? "\(count)× (no amount)" : PeptideMath.number(total) + " " + units
        }
    }

    struct DailySummary: Equatable {
        var count: Int
        var totals: [CompoundTotal]
        var first: Date?
        var last: Date?
    }

    /// Totals add only within identical units. mg and mcg stay separate lines.
    static func totals(_ entries: [PeptideLogEntry]) -> [CompoundTotal] {
        var order: [String] = []
        var totals: [String: CompoundTotal] = [:]
        for entry in entries where entry.countsAsTaken {
            let units = (entry.units ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = compoundKey(entry.compound) + "|" + units
            var item: CompoundTotal
            if let existing = totals[key] {
                item = existing
            } else {
                order.append(key)
                item = CompoundTotal(compound: entry.compound, units: units, total: 0, count: 0)
            }
            item.count += 1
            if let dose = entry.dose, !units.isEmpty {
                item.total = ReconMath.clean(item.total + dose)
            }
            totals[key] = item
        }
        return order.compactMap { totals[$0] }
    }

    static func dailySummary(entries: [PeptideLogEntry], date: String, person: String) -> DailySummary {
        let owner = PeptidePerson.normalized(person)
        let day = entries.filter {
            $0.countsAsTaken && PeptidePerson.normalized($0.person) == owner && $0.civilDate == date
        }
        let times = day.compactMap(\.date).sorted()
        return DailySummary(count: day.count, totals: totals(day), first: times.first, last: times.last)
    }

    struct WeekCount: Identifiable, Equatable {
        /// Monday, yyyy-MM-dd.
        var weekStart: String
        var count: Int
        var id: String { weekStart }
    }

    static func weeklyCounts(entries: [PeptideLogEntry], compound: String?, person: String, weeks: Int, today: String) -> [WeekCount] {
        let owner = PeptidePerson.normalized(person)
        let key = compound.map(compoundKey)
        let lastMonday = ReconMath.mondayOf(today)
        let count = max(weeks, 1)
        let starts = (0..<count).map { ReconMath.addDays(lastMonday, -7 * (count - 1 - $0)) }
        var counts: [String: Int] = [:]
        for entry in entries where entry.countsAsTaken && PeptidePerson.normalized(entry.person) == owner {
            if let key, compoundKey(entry.compound) != key { continue }
            guard let civil = entry.civilDate else { continue }
            counts[ReconMath.mondayOf(civil), default: 0] += 1
        }
        return starts.map { WeekCount(weekStart: $0, count: counts[$0] ?? 0) }
    }

    struct CompoundWindowSummary: Equatable, Identifiable {
        var compound: String
        var count7: Int
        var count30: Int
        var count90: Int
        var totals30: [CompoundTotal]
        var lastDose: Date?
        var id: String { PeptideMath.compoundKey(compound) }
    }

    static func compoundSummaries(entries: [PeptideLogEntry], person: String, today: String) -> [CompoundWindowSummary] {
        let owner = PeptidePerson.normalized(person)
        let mine = entries.filter { $0.countsAsTaken && PeptidePerson.normalized($0.person) == owner }
        var order: [String] = []
        var names: [String: String] = [:]
        for entry in mine.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) {
            let key = compoundKey(entry.compound)
            if names[key] == nil {
                names[key] = entry.compound
                order.append(key)
            }
        }
        return order.map { key in
            let rows = mine.filter { compoundKey($0.compound) == key }
            func within(_ days: Int) -> [PeptideLogEntry] {
                let from = ReconMath.addDays(today, -(days - 1))
                return rows.filter { ($0.civilDate ?? "") >= from && ($0.civilDate ?? "") <= today }
            }
            return CompoundWindowSummary(
                compound: names[key] ?? key,
                count7: within(7).count,
                count30: within(30).count,
                count90: within(90).count,
                totals30: totals(within(30)),
                lastDose: rows.compactMap(\.date).max()
            )
        }
    }

    enum DayMarker: Equatable {
        case none
        /// Every scheduled dose that day is logged.
        case allTaken
        /// A scheduled dose that day has no log.
        case missed
        /// Logged, nothing scheduled.
        case unscheduledOnly
    }

    static func dayMarker(
        date: String,
        person: String,
        compound: String?,
        schedules: [PeptideUserSchedule],
        entries: [PeptideLogEntry],
        today: String
    ) -> DayMarker {
        let owner = PeptidePerson.normalized(person)
        let key = compound.map(compoundKey)
        let relevant = schedules.filter {
            $0.active && $0.frequency.type != "perWeek"
                && PeptidePerson.normalized($0.person) == owner
                && (key == nil || compoundKey($0.compound) == key)
        }
        let scheduled = relevant.filter { !occurrences($0, from: date, to: date).isEmpty }
        let logged = entries.contains {
            $0.countsAsTaken && PeptidePerson.normalized($0.person) == owner && $0.civilDate == date
                && (key == nil || compoundKey($0.compound) == key)
        }
        if scheduled.isEmpty {
            return logged ? .unscheduledOnly : .none
        }
        let allTaken = scheduled.allSatisfy {
            takenDates(person: $0.person, compound: $0.compound, entries: entries).contains(date)
        }
        if allTaken { return .allTaken }
        return date < today ? .missed : (logged ? .unscheduledOnly : .none)
    }
}
