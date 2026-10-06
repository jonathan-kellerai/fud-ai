//
//  ProgramCycle.swift
//  calorietracker
//
//  Program V2 sequence rule: order beats calendar. The next workout is the
//  program day after the last one completed this program week; a new week
//  always starts at Day 1 (missed days do not carry over).
//

import Foundation

/// One completed program session: bridge history or a save the app just made.
struct CompletedProgramSession: Codable, Equatable, Hashable {
    var dayIndex: Int
    /// Civil date `yyyy-MM-dd` the session was done on.
    var sessionDate: String
    /// Bridge `recorded_at`; only orders two sessions on the same date.
    var recordedAt: String?

    init(dayIndex: Int, sessionDate: String, recordedAt: String? = nil) {
        self.dayIndex = dayIndex
        self.sessionDate = sessionDate
        self.recordedAt = recordedAt
    }

    /// Nil for rows that are not real completed program sessions.
    init?(remote: RemoteWorkout, days: [TrainingProgramDay]) {
        guard remote.kind.uppercased() == "COMPLETED",
              remote.synthetic != true,
              SessionDateFormatting.yearMonthDay(from: remote.sessionDate) != nil,
              let dayIndex = Self.dayIndex(programDay: remote.programDay, title: remote.title, days: days)
        else { return nil }
        self.init(dayIndex: dayIndex, sessionDate: String(remote.sessionDate.prefix(10)), recordedAt: remote.recordedAt)
    }

    /// `"4-thu"` (iOS) or `"Day4_UpperPhysique"` (PWA, Program V1), else the
    /// program day whose name matches the title. Indexes the program does not
    /// have are ignored.
    static func dayIndex(programDay: String, title: String, days: [TrainingProgramDay]) -> Int? {
        let raw = programDay.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let parsed = leadingIndex(raw) ?? leadingIndex(raw.hasPrefix("day") ? String(raw.dropFirst(3)) : "") {
            if days.isEmpty || days.contains(where: { $0.dayIndex == parsed }) { return parsed }
            return nil
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }
        return days.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name }?.dayIndex
    }

    /// Digits at the start of `text` followed by `-`, `_`, a space, or nothing.
    private static func leadingIndex(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.isEmpty || rest.hasPrefix("-") || rest.hasPrefix("_") || rest.hasPrefix(" ") else { return nil }
        return value
    }
}

/// The program day picked for one civil date from the Change sheet.
struct TodayWorkoutOverride: Codable, Equatable {
    /// Civil date `yyyy-MM-dd`; the override means nothing on any other date.
    var date: String
    var dayIndex: Int
}

/// Everything besides the program and the date that decides today's workout.
struct TrainingDayContext: Equatable {
    /// An unsaved logger session.
    struct Draft: Equatable {
        var dayIndex: Int
        var sessionDate: String
    }

    var history: [CompletedProgramSession]
    var override: TodayWorkoutOverride?
    var inProgress: Draft?

    init(history: [CompletedProgramSession] = [], override: TodayWorkoutOverride? = nil, inProgress: Draft? = nil) {
        self.history = history
        self.override = override
        self.inProgress = inProgress
    }

    static let empty = TrainingDayContext()

    /// The same context without today's pick, for "what would the cycle say".
    var withoutOverride: TrainingDayContext {
        TrainingDayContext(history: history, override: nil, inProgress: inProgress)
    }
}

enum ProgramCycle {
    enum Suggestion: Equatable {
        /// `week` is nil only when the program has no usable start date.
        case day(dayIndex: Int, week: Int?)
        /// Every program day after the week's last session is done.
        case weekComplete(week: Int?)
    }

    /// The cycle's pick for `civilDay`, from sessions completed earlier in the
    /// same program week. Nil before the program starts or with no days.
    static func suggestion(
        body: TrainingProgramBody,
        history: [CompletedProgramSession],
        on civilDay: String
    ) -> Suggestion? {
        let days = body.days.sorted { $0.dayIndex < $1.dayIndex }
        guard let first = days.first else { return nil }
        let hasStart = SessionDateFormatting.yearMonthDay(from: body.startDate) != nil
        if hasStart && civilDay < String(body.startDate.prefix(10)) { return nil }
        let week = ProgramWeekRules.weekNumber(civilDay: civilDay, body: weekBody(body))
        let shownWeek = hasStart ? week : nil

        let thisWeek = history.enumerated().filter { _, session in
            session.sessionDate < civilDay
                && ProgramWeekRules.weekNumber(civilDay: session.sessionDate, body: weekBody(body)) == week
                && days.contains { $0.dayIndex == session.dayIndex }
        }
        let latest = thisWeek.max { lhs, rhs in
            if lhs.element.sessionDate != rhs.element.sessionDate {
                return lhs.element.sessionDate < rhs.element.sessionDate
            }
            let lhsRecorded = lhs.element.recordedAt ?? ""
            let rhsRecorded = rhs.element.recordedAt ?? ""
            if lhsRecorded != rhsRecorded { return lhsRecorded < rhsRecorded }
            return lhs.offset < rhs.offset
        }
        guard let last = latest?.element else {
            return .day(dayIndex: first.dayIndex, week: shownWeek)
        }
        guard let next = days.first(where: { $0.dayIndex > last.dayIndex }) else {
            return .weekComplete(week: shownWeek)
        }
        return .day(dayIndex: next.dayIndex, week: shownWeek)
    }

    /// The latest session completed on `civilDay` itself.
    static func completed(on civilDay: String, in history: [CompletedProgramSession]) -> CompletedProgramSession? {
        history.enumerated()
            .filter { $0.element.sessionDate == civilDay }
            .max { lhs, rhs in
                let lhsRecorded = lhs.element.recordedAt ?? ""
                let rhsRecorded = rhs.element.recordedAt ?? ""
                if lhsRecorded != rhsRecorded { return lhsRecorded < rhsRecorded }
                return lhs.offset < rhs.offset
            }?
            .element
    }

    /// Weeks still group Monday–Sunday when a program has no usable start
    /// date; the week number is then not shown.
    private static func weekBody(_ body: TrainingProgramBody) -> TrainingProgramBody {
        guard SessionDateFormatting.yearMonthDay(from: body.startDate) == nil else { return body }
        var anchored = body
        anchored.startDate = "2000-01-03"
        return anchored
    }
}
