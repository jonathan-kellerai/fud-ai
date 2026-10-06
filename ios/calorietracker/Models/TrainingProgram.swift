//
//  TrainingProgram.swift
//  calorietracker
//
//  Versioned training programs from the Neon bridge, plus the calendar-day
//  helpers the Train tab uses for session dates and rest days.
//

import Foundation

enum ProgramWeekday: String, CaseIterable, Identifiable, Codable, Hashable {
    case mon, tue, wed, thu, fri, sat, sun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mon: "Monday"
        case .tue: "Tuesday"
        case .wed: "Wednesday"
        case .thu: "Thursday"
        case .fri: "Friday"
        case .sat: "Saturday"
        case .sun: "Sunday"
        }
    }

    /// `Calendar` weekday, Sunday = 1.
    var calendarWeekday: Int {
        switch self {
        case .sun: 1
        case .mon: 2
        case .tue: 3
        case .wed: 4
        case .thu: 5
        case .fri: 6
        case .sat: 7
        }
    }

    static func from(calendarWeekday: Int) -> ProgramWeekday? {
        allCases.first { $0.calendarWeekday == calendarWeekday }
    }

    static func parse(_ raw: String) -> ProgramWeekday? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = ProgramWeekday(rawValue: value) {
            return exact
        }
        let aliases: [String: ProgramWeekday] = [
            "monday": .mon,
            "tuesday": .tue,
            "wednesday": .wed,
            "thursday": .thu,
            "friday": .fri,
            "saturday": .sat,
            "sunday": .sun
        ]
        if let alias = aliases[value] {
            return alias
        }
        let prefix = String(value.prefix(3))
        return ProgramWeekday(rawValue: prefix)
    }
}

enum TrainingProgramStatus: String, Codable, Hashable {
    case draft
    case active
    case archived
}

struct TrainingProgramConditioning: Codable, Equatable, Hashable {
    var minutes: Int
    var description: String
}

enum ExerciseRest {
    static var fallbackSeconds: Int { RestTimerSettings.defaultSeconds }

    static func resolvedSeconds(restSec: Int?, notes: String?, exerciseName: String) -> Int {
        if let restSec { return restSec }
        if let fromNotes = lowerBoundSeconds(in: notes) { return fromNotes }
        if let bundled = ProgramV2Templates.restLowerBound(matching: exerciseName) { return bundled }
        return fallbackSeconds
    }

    /// Only a `Rest:` seconds expression. `2-3 s eccentric` later in the note must not match.
    static func lowerBoundSeconds(in notes: String?) -> Int? {
        guard let notes else { return nil }
        return firstInteger(
            in: notes,
            pattern: #"(?i)\brest:\s*(\d+)\s*(?:-\s*\d+)?(?:\s*\([^)]*\))?\s*s\b"#
        )
    }

    static func startLoadPounds(from loadNote: String?) -> Double? {
        guard let loadNote else { return nil }
        if let pounds = firstNumber(in: loadNote, pattern: #"(?i)(\d+(?:\.\d+)?)\s*lb\b"#) {
            return pounds
        }
        if loadNote.range(of: "bodyweight", options: .caseInsensitive) != nil {
            return firstNumber(in: loadNote, pattern: #"(\d+(?:\.\d+)?)"#)
        }
        return nil
    }

    private static func firstInteger(in text: String, pattern: String) -> Int? {
        guard let number = firstCapture(in: text, pattern: pattern) else { return nil }
        return Int(number)
    }

    private static func firstNumber(in text: String, pattern: String) -> Double? {
        guard let number = firstCapture(in: text, pattern: pattern) else { return nil }
        return Double(number)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }
}

struct TrainingProgramExercise: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var order: Int
    var name: String
    var sets: Int
    var reps: String
    var rir: String
    var rpe: Double?
    var restSec: Int?
    var loadNote: String?
    var substitutions: [String]
    var notes: String?
    /// Consecutive exercises sharing a group are done as a superset.
    var supersetGroup: String?

    init(
        id: UUID = UUID(),
        order: Int,
        name: String,
        sets: Int,
        reps: String,
        rir: String = "",
        rpe: Double? = nil,
        restSec: Int? = nil,
        loadNote: String? = nil,
        substitutions: [String] = [],
        notes: String? = nil,
        supersetGroup: String? = nil
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.sets = sets
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.restSec = restSec
        self.loadNote = loadNote
        self.substitutions = substitutions
        self.notes = notes
        self.supersetGroup = supersetGroup
    }

    enum CodingKeys: String, CodingKey {
        case order, name, sets, reps, rir, rpe
        case restSec = "rest_sec"
        case loadNote = "load_note"
        case substitutions, notes
        case supersetGroup = "superset_group"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sets = try container.decodeIfPresent(Int.self, forKey: .sets) ?? 0
        reps = Self.stringOrNumber(container, key: .reps)
        rir = Self.stringOrNumber(container, key: .rir)
        rpe = Self.optionalDouble(container, key: .rpe)
        restSec = try container.decodeIfPresent(Int.self, forKey: .restSec)
        loadNote = try container.decodeIfPresent(String.self, forKey: .loadNote)
        substitutions = try container.decodeIfPresent([String].self, forKey: .substitutions) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        supersetGroup = try container.decodeIfPresent(String.self, forKey: .supersetGroup)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(sets, forKey: .sets)
        try container.encode(reps, forKey: .reps)
        if rir.isEmpty {
            try container.encodeNil(forKey: .rir)
        } else {
            try container.encode(rir, forKey: .rir)
        }
        try container.encodeIfPresent(rpe, forKey: .rpe)
        if let restSec {
            try container.encode(restSec, forKey: .restSec)
        } else {
            try container.encodeNil(forKey: .restSec)
        }
        try container.encodeIfPresent(loadNote, forKey: .loadNote)
        try container.encode(substitutions, forKey: .substitutions)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(supersetGroup, forKey: .supersetGroup)
    }

    private static func stringOrNumber(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String {
        if let text = try? container.decode(String.self, forKey: key) {
            return text
        }
        if let whole = try? container.decode(Int.self, forKey: key) {
            return String(whole)
        }
        if let number = try? container.decode(Double.self, forKey: key) {
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        }
        return ""
    }

    private static func optionalDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let number = try? container.decode(Double.self, forKey: key) {
            return number
        }
        if let whole = try? container.decode(Int.self, forKey: key) {
            return Double(whole)
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    var resolvedRestSeconds: Int {
        ExerciseRest.resolvedSeconds(restSec: restSec, notes: notes, exerciseName: name)
    }

    var parsedStartLoadLb: Double? {
        ExerciseRest.startLoadPounds(from: loadNote)
    }
}

struct TrainingProgramDay: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var dayIndex: Int
    var weekday: String
    var name: String
    var conditioning: TrainingProgramConditioning?
    var exercises: [TrainingProgramExercise]

    enum CodingKeys: String, CodingKey {
        case dayIndex = "day_index"
        case weekday, name, conditioning, exercises
    }

    var weekdayLabel: String {
        ProgramWeekday.parse(weekday)?.displayName ?? weekday
    }

    var conditioningSummary: String {
        guard let conditioning else { return "No conditioning" }
        let description = conditioning.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            return "\(conditioning.minutes) min"
        }
        if description.lowercased().hasPrefix("\(conditioning.minutes) min") {
            return description
        }
        return "\(conditioning.minutes) min \(description)"
    }

    func asProgramV2Day() -> ProgramV2Day {
        ProgramV2Day(
            id: "\(dayIndex)-\(weekday)",
            title: name,
            conditioning: conditioningSummary,
            conditioningMinimum: "",
            exercises: exercises.sorted { $0.order < $1.order }.map { exercise in
                let rest = exercise.resolvedRestSeconds
                return ProgramV2Exercise(
                    key: exercise.name.lowercased(),
                    name: exercise.name,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    restSeconds: rest...rest,
                    rirTarget: exercise.rir,
                    startLoadLb: exercise.parsedStartLoadLb,
                    notes: exercise.notes ?? "",
                    loadNote: exercise.loadNote ?? "",
                    supersetGroup: exercise.supersetGroup
                )
            }
        )
    }
}

struct TrainingProgramBody: Codable, Equatable, Hashable {
    /// One builder for every dated session surface. Resume uses its saved snapshot.
    func programV2Day(for day: TrainingProgramDay, on date: Date) -> ProgramV2Day {
        ProgramWeekRules.apply(to: day.asProgramV2Day(), dayIndex: day.dayIndex, on: date, body: self)
    }

    var startDate: String
    var dailyStepsTarget: Int
    var weeks: Int?
    var reductionWeek: Int?
    var restWeekdays: [String]
    var notes: String?
    var days: [TrainingProgramDay]

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case dailyStepsTarget = "daily_steps_target"
        case weeks
        case reductionWeek = "reduction_week"
        case restWeekdays = "rest_weekdays"
        case notes, days
    }

    init(
        startDate: String,
        dailyStepsTarget: Int,
        weeks: Int?,
        reductionWeek: Int?,
        restWeekdays: [String],
        notes: String?,
        days: [TrainingProgramDay]
    ) {
        self.startDate = startDate
        self.dailyStepsTarget = dailyStepsTarget
        self.weeks = weeks
        self.reductionWeek = reductionWeek
        self.restWeekdays = restWeekdays
        self.notes = notes
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        dailyStepsTarget = try container.decodeIfPresent(Int.self, forKey: .dailyStepsTarget) ?? 0
        weeks = try container.decodeIfPresent(Int.self, forKey: .weeks)
        reductionWeek = try container.decodeIfPresent(Int.self, forKey: .reductionWeek)
        restWeekdays = try container.decodeIfPresent([String].self, forKey: .restWeekdays) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        days = try container.decodeIfPresent([TrainingProgramDay].self, forKey: .days) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(dailyStepsTarget, forKey: .dailyStepsTarget)
        if let weeks {
            try container.encode(weeks, forKey: .weeks)
        } else {
            try container.encodeNil(forKey: .weeks)
        }
        if let reductionWeek {
            try container.encode(reductionWeek, forKey: .reductionWeek)
        } else {
            try container.encodeNil(forKey: .reductionWeek)
        }
        try container.encode(restWeekdays, forKey: .restWeekdays)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(days, forKey: .days)
    }

    func normalizedForSave() -> TrainingProgramBody {
        var copy = self
        for index in copy.days.indices {
            copy.days[index].dayIndex = index + 1
            copy.days[index].weekday = ProgramWeekday.parse(copy.days[index].weekday)?.rawValue ?? copy.days[index].weekday
            for exerciseIndex in copy.days[index].exercises.indices {
                copy.days[index].exercises[exerciseIndex].order = exerciseIndex
            }
            if let conditioning = copy.days[index].conditioning,
               conditioning.minutes == 0,
               conditioning.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.days[index].conditioning = nil
            }
        }
        copy.restWeekdays = copy.restWeekdays.compactMap { ProgramWeekday.parse($0)?.rawValue }
        return copy
    }

    static func blank(on date: Date = Date(), calendar: Calendar = .current) -> TrainingProgramBody {
        TrainingProgramBody(
            startDate: SessionDateFormatting.calendarDateString(from: date, calendar: calendar),
            dailyStepsTarget: 10_000,
            weeks: 4,
            reductionWeek: nil,
            restWeekdays: [ProgramWeekday.sat.rawValue, ProgramWeekday.sun.rawValue],
            notes: "",
            days: [
                TrainingProgramDay(
                    dayIndex: 1,
                    weekday: ProgramWeekday.mon.rawValue,
                    name: "Day 1",
                    conditioning: TrainingProgramConditioning(minutes: 8, description: ""),
                    exercises: []
                )
            ]
        )
    }

    static func bundledV2() -> TrainingProgramBody {
        let templates: [(ProgramV2Day, ProgramWeekday)] = [
            (ProgramV2Templates.day1LowerA, .mon),
            (ProgramV2Templates.day2UpperPush, .tue),
            (ProgramV2Templates.day3PullHinge, .wed),
            (ProgramV2Templates.day4UpperPhysique, .thu),
            (ProgramV2Templates.day5LowerBCond, .fri)
        ]
        let days = templates.enumerated().map { index, pair in
            let (template, weekday) = pair
            return TrainingProgramDay(
                dayIndex: index + 1,
                weekday: weekday.rawValue,
                name: template.title,
                conditioning: Self.splitConditioning(template.conditioning),
                exercises: template.exercises.enumerated().map { exerciseIndex, exercise in
                    TrainingProgramExercise(
                        order: exerciseIndex,
                        name: exercise.name,
                        sets: exercise.sets,
                        reps: exercise.reps,
                        rir: exercise.rirTarget,
                        restSec: exercise.restSeconds.lowerBound,
                        loadNote: exercise.startLoadLb.map { "Start \(Int($0)) lb" },
                        notes: exercise.notes.isEmpty ? nil : exercise.notes,
                        supersetGroup: exercise.supersetGroup
                    )
                }
            )
        }
        return TrainingProgramBody(
            startDate: "2026-09-28",
            dailyStepsTarget: 10_000,
            weeks: 6,
            reductionWeek: 4,
            restWeekdays: [ProgramWeekday.sat.rawValue, ProgramWeekday.sun.rawValue],
            notes: "Bundled Program V2",
            days: days
        )
    }

    private static func splitConditioning(_ text: String) -> TrainingProgramConditioning {
        let marker = " min "
        guard let range = text.range(of: marker),
              let minutes = Int(text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)) else {
            return TrainingProgramConditioning(minutes: 0, description: text)
        }
        return TrainingProgramConditioning(minutes: minutes, description: String(text[range.upperBound...]))
    }
}

struct TrainingProgramRecord: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var lineageId: String
    var version: Int
    var name: String
    var status: TrainingProgramStatus
    var parentId: String?
    var createdAt: String?
    var activatedAt: String?
    var createdBy: String?
    var changeReason: String?
    var body: TrainingProgramBody?

    enum CodingKeys: String, CodingKey {
        case id
        case lineageId = "lineage_id"
        case version, name, status
        case parentId = "parent_id"
        case createdAt = "created_at"
        case activatedAt = "activated_at"
        case createdBy = "created_by"
        case changeReason = "change_reason"
        case body
    }

    static func bundledV2() -> TrainingProgramRecord {
        TrainingProgramRecord(
            id: "bundled-program-v2",
            lineageId: "bundled-program-v2",
            version: 2,
            name: "Program V2",
            status: .active,
            parentId: nil,
            createdAt: nil,
            activatedAt: nil,
            createdBy: "app",
            changeReason: nil,
            body: .bundledV2()
        )
    }
}

struct TrainingProgramListResponse: Codable {
    let programs: [TrainingProgramRecord]
}

struct TrainingProgramEnvelope: Codable {
    let program: TrainingProgramRecord?
}

struct ProgramCreateRequest: Encodable {
    var name: String
    var body: TrainingProgramBody
    var parentId: String?
    var changeReason: String?
    var createdBy: String

    enum CodingKeys: String, CodingKey {
        case name, body
        case parentId = "parent_id"
        case changeReason = "change_reason"
        case createdBy = "created_by"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encodeIfPresent(changeReason, forKey: .changeReason)
        try container.encode(createdBy, forKey: .createdBy)
    }
}

struct ProgramPatchRequest: Encodable {
    var name: String?
    var body: TrainingProgramBody?
    var changeReason: String?

    enum CodingKeys: String, CodingKey {
        case name, body
        case changeReason = "change_reason"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(changeReason, forKey: .changeReason)
    }
}

struct ProgramReviseRequest: Encodable {
    var body: TrainingProgramBody
    var name: String?
    var changeReason: String
    var activate: Bool?
    var createdBy: String? = nil

    enum CodingKeys: String, CodingKey {
        case body, name
        case changeReason = "change_reason"
        case activate
        case createdBy = "created_by"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(changeReason, forKey: .changeReason)
        try container.encodeIfPresent(activate, forKey: .activate)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
    }
}

enum ActiveProgramCache {
    static let storageKey = "jl.physical.activeProgram.v1"

    static func load() -> TrainingProgramRecord? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(TrainingProgramRecord.self, from: data)
    }

    static func save(_ record: TrainingProgramRecord) {
        guard record.body != nil, record.id != TrainingProgramRecord.bundledV2().id else { return }
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum SessionDateFormatting {
    /// Session dates are civil dates. `2026-09-24T00:00:00.000Z` must stay Sep 24
    /// in America/New_York instead of rolling back to Sep 23.
    static func displayString(from raw: String) -> String {
        guard let date = civilDate(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    static func calendarDateString(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from calendarDay: String, calendar: Calendar = .current) -> Date? {
        guard let parts = yearMonthDay(from: calendarDay) else { return nil }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        return calendar.date(from: components)
    }

    static func yearMonthDay(from raw: String) -> (year: Int, month: Int, day: Int)? {
        let dayPart = String(raw.prefix(10))
        let pieces = dayPart.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]),
              dayPart.count == 10 else {
            return nil
        }
        return (year, month, day)
    }

    private static func civilDate(from raw: String) -> Date? {
        guard let parts = yearMonthDay(from: raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        return calendar.date(from: components)
    }
}

enum ResolvedTrainingDay: Equatable {
    case session(dayIndex: Int, name: String, stepsTarget: Int)
    case rest(stepsTarget: Int, nextName: String, nextWeekday: String)
    case upcoming(name: String, weekday: String, stepsTarget: Int)

    var stepsTarget: Int {
        switch self {
        case .session(_, _, let steps), .rest(let steps, _, _), .upcoming(_, _, let steps):
            return steps
        }
    }

    var nextLabel: String? {
        switch self {
        case .rest(_, let nextName, let nextWeekday):
            return TrainingNextSession(name: nextName, weekday: nextWeekday).label
        case .session, .upcoming:
            return nil
        }
    }
}

/// The program session on the next non-rest date, with the cycle applied.
struct TrainingNextSession: Equatable {
    var name: String
    var weekday: String

    /// "Next: Upper Push Wednesday".
    var label: String {
        "Next: \(name) \(weekday)"
    }
}

/// Why today's card shows what it shows: the subtitle and the Change control.
struct TrainingDayResolution: Equatable {
    enum Reason: Equatable {
        case upcoming
        case loggedToday
        case changed
        case inProgress
        case cycle
        case rest
        case weekComplete
    }

    var plan: ResolvedTrainingDay
    var reason: Reason
    /// Program week of the date; nil before the start or without a start date.
    var week: Int?
    /// What comes after today's session once it is logged; nil otherwise
    /// (rest cards carry their next session in `plan`).
    var next: TrainingNextSession?

    /// "Next: Upper Push Wednesday" under a session logged today.
    var nextLabel: String? {
        next?.label
    }

    /// "Week 2 · Day 1 · Next in cycle". Nil where the card has nothing to add.
    var subtitle: String? {
        let weekPart = week.map { "Week \($0)" }
        switch plan {
        case .session(let dayIndex, _, _):
            let status: String
            switch reason {
            case .loggedToday: status = "Logged today"
            case .changed: status = "Changed for today"
            case .inProgress: status = "In progress"
            case .cycle, .upcoming, .rest, .weekComplete: status = "Next in cycle"
            }
            return ([weekPart, "Day \(dayIndex)", status].compactMap { $0 }).joined(separator: " · ")
        case .rest:
            guard reason == .weekComplete else { return nil }
            return weekPart.map { "\($0) complete" } ?? "Week complete"
        case .upcoming:
            return nil
        }
    }

    /// One lifting session per day: once one is logged today it cannot be swapped.
    var canChange: Bool {
        reason != .upcoming && reason != .loggedToday
    }

    var isChanged: Bool {
        reason == .changed
    }

    /// The program day the card shows; nil on rest and upcoming cards.
    var dayIndex: Int? {
        if case .session(let dayIndex, _, _) = plan { return dayIndex }
        return nil
    }
}

/// One row of the Change workout sheet.
struct TrainingWorkoutOption: Equatable, Identifiable {
    var dayIndex: Int
    var name: String
    var exerciseCount: Int
    var conditioning: String

    var id: Int { dayIndex }

    var title: String {
        "Day \(dayIndex) · \(name)"
    }

    var detail: String {
        let exercises = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        return "\(exercises) · \(conditioning)"
    }

    func accessibilityLabel(suggested: Bool, selected: Bool) -> String {
        var parts = ["Day \(dayIndex)", name,
                     exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises",
                     "conditioning \(conditioning)"]
        if suggested { parts.append("suggested") }
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

enum TrainingProgramSchedule {
    /// Today's program day. Precedence: a session already completed today,
    /// then today's pick from the Change sheet, then an unsaved session
    /// started today, then rest weekdays, then the next day in the cycle.
    static func resolve(
        _ body: TrainingProgramBody,
        on date: Date,
        context: TrainingDayContext,
        calendar: Calendar = .current
    ) -> ResolvedTrainingDay {
        resolution(body, on: date, context: context, calendar: calendar).plan
    }

    static func resolution(
        _ body: TrainingProgramBody,
        on date: Date,
        context: TrainingDayContext,
        calendar: Calendar = .current
    ) -> TrainingDayResolution {
        let steps = body.dailyStepsTarget
        let todayKey = SessionDateFormatting.calendarDateString(from: date, calendar: calendar)
        let today = SessionDateFormatting.yearMonthDay(from: todayKey)
        let start = SessionDateFormatting.yearMonthDay(from: body.startDate)

        if let today, let start, compare(today, start) == .orderedAscending {
            if let upcoming = firstSession(in: body, onOrAfter: start, calendar: calendar) {
                return TrainingDayResolution(
                    plan: .upcoming(name: upcoming.day.name, weekday: upcoming.weekday.displayName, stepsTarget: steps),
                    reason: .upcoming,
                    week: nil,
                    next: nil
                )
            }
        }

        let week = start == nil ? nil : ProgramWeekRules.weekNumber(civilDay: todayKey, body: body)
        func session(_ dayIndex: Int, _ reason: TrainingDayResolution.Reason) -> TrainingDayResolution? {
            guard let day = body.days.first(where: { $0.dayIndex == dayIndex }) else { return nil }
            return TrainingDayResolution(
                plan: .session(dayIndex: day.dayIndex, name: day.name, stepsTarget: steps),
                reason: reason,
                week: week,
                next: nil
            )
        }
        func rest(_ reason: TrainingDayResolution.Reason) -> TrainingDayResolution {
            let plan: ResolvedTrainingDay
            if let next = nextSession(in: body, after: date, history: context.history, calendar: calendar) {
                plan = .rest(stepsTarget: steps, nextName: next.day.name, nextWeekday: next.weekday.displayName)
            } else {
                plan = .rest(stepsTarget: steps, nextName: "Workout", nextWeekday: "")
            }
            return TrainingDayResolution(plan: plan, reason: reason, week: week, next: nil)
        }

        if let done = ProgramCycle.completed(on: todayKey, in: context.history),
           var logged = session(done.dayIndex, .loggedToday) {
            if let next = nextSession(in: body, after: date, history: context.history, calendar: calendar) {
                logged.next = TrainingNextSession(name: next.day.name, weekday: next.weekday.displayName)
            }
            return logged
        }
        if let override = context.override, override.date == todayKey,
           let changed = session(override.dayIndex, .changed) {
            return changed
        }
        if let draft = context.inProgress, draft.sessionDate == todayKey,
           let resumed = session(draft.dayIndex, .inProgress) {
            return resumed
        }
        if isRest(body, on: date, calendar: calendar) {
            return rest(.rest)
        }
        switch ProgramCycle.suggestion(body: body, history: context.history, on: todayKey) {
        case .day(let dayIndex, _):
            return session(dayIndex, .cycle) ?? rest(.rest)
        case .weekComplete:
            return rest(.weekComplete)
        case nil:
            return rest(.rest)
        }
    }

    /// The cycle's day for the Change sheet's "Suggested" tag: today's
    /// session ignoring the override, or on a rest day the next session.
    static func suggestedDayIndex(
        _ body: TrainingProgramBody,
        on date: Date,
        context: TrainingDayContext,
        calendar: Calendar = .current
    ) -> Int? {
        switch resolve(body, on: date, context: context.withoutOverride, calendar: calendar) {
        case .session(let dayIndex, _, _):
            return dayIndex
        case .rest:
            return nextSession(in: body, after: date, history: context.history, calendar: calendar)?.day.dayIndex
        case .upcoming:
            return nil
        }
    }

    /// Today's override after picking `dayIndex`: none when the pick is the
    /// session today would have anyway, else the pick for today's date.
    static func overrideAfterPicking(
        _ dayIndex: Int,
        in body: TrainingProgramBody,
        on date: Date,
        context: TrainingDayContext,
        calendar: Calendar = .current
    ) -> TodayWorkoutOverride? {
        if case .session(let planned, _, _) = resolve(body, on: date, context: context.withoutOverride, calendar: calendar),
           planned == dayIndex {
            return nil
        }
        return TodayWorkoutOverride(
            date: SessionDateFormatting.calendarDateString(from: date, calendar: calendar),
            dayIndex: dayIndex
        )
    }

    /// Every program day, dated for `date` so week rules (reduction week) show.
    static func workoutOptions(_ body: TrainingProgramBody, on date: Date) -> [TrainingWorkoutOption] {
        body.days.sorted { $0.dayIndex < $1.dayIndex }.map { day in
            let dated = body.programV2Day(for: day, on: date)
            return TrainingWorkoutOption(
                dayIndex: day.dayIndex,
                name: day.name,
                exerciseCount: dated.exercises.count,
                conditioning: dated.conditioning
            )
        }
    }

    static func programDay(in body: TrainingProgramBody, matching resolved: ResolvedTrainingDay) -> TrainingProgramDay? {
        guard case .session(let dayIndex, let name, _) = resolved else { return nil }
        return body.days.first { $0.dayIndex == dayIndex && $0.name == name }
            ?? body.days.first { $0.dayIndex == dayIndex }
            ?? body.days.first { $0.name == name }
    }

    private static func isRest(_ body: TrainingProgramBody, on date: Date, calendar: Calendar) -> Bool {
        guard let weekday = weekday(on: date, calendar: calendar) else { return false }
        let rest = Set(body.restWeekdays.compactMap { ProgramWeekday.parse($0) })
        return rest.contains(weekday)
    }

    /// Day 1 (lowest index) on the first non-rest date on or after the start.
    private static func firstSession(
        in body: TrainingProgramBody,
        onOrAfter start: (year: Int, month: Int, day: Int),
        calendar: Calendar
    ) -> (day: TrainingProgramDay, weekday: ProgramWeekday)? {
        guard let origin = date(from: start, calendar: calendar),
              let first = body.days.min(by: { $0.dayIndex < $1.dayIndex }) else { return nil }
        for offset in 0..<21 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: origin),
                  let weekday = weekday(on: candidate, calendar: calendar),
                  !isRest(body, on: candidate, calendar: calendar) else {
                continue
            }
            return (first, weekday)
        }
        return nil
    }

    /// The cycle's pick on the first later non-rest date that has a session.
    private static func nextSession(
        in body: TrainingProgramBody,
        after date: Date,
        history: [CompletedProgramSession],
        calendar: Calendar
    ) -> (day: TrainingProgramDay, weekday: ProgramWeekday)? {
        let start = SessionDateFormatting.yearMonthDay(from: body.startDate)
        for offset in 1..<21 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date),
                  let parts = SessionDateFormatting.yearMonthDay(
                    from: SessionDateFormatting.calendarDateString(from: candidate, calendar: calendar)
                  ) else {
                continue
            }
            if let start, compare(parts, start) == .orderedAscending {
                return firstSession(in: body, onOrAfter: start, calendar: calendar)
            }
            guard !isRest(body, on: candidate, calendar: calendar),
                  let weekday = weekday(on: candidate, calendar: calendar) else {
                continue
            }
            let key = SessionDateFormatting.calendarDateString(from: candidate, calendar: calendar)
            if case .day(let dayIndex, _) = ProgramCycle.suggestion(body: body, history: history, on: key),
               let day = body.days.first(where: { $0.dayIndex == dayIndex }) {
                return (day, weekday)
            }
        }
        return nil
    }

    private static func weekday(on date: Date, calendar: Calendar) -> ProgramWeekday? {
        ProgramWeekday.from(calendarWeekday: calendar.component(.weekday, from: date))
    }

    private static func date(
        from parts: (year: Int, month: Int, day: Int),
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        return calendar.date(from: components)
    }

    private static func compare(
        _ lhs: (year: Int, month: Int, day: Int),
        _ rhs: (year: Int, month: Int, day: Int)
    ) -> ComparisonResult {
        if lhs.year != rhs.year { return lhs.year < rhs.year ? .orderedAscending : .orderedDescending }
        if lhs.month != rhs.month { return lhs.month < rhs.month ? .orderedAscending : .orderedDescending }
        if lhs.day != rhs.day { return lhs.day < rhs.day ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}
