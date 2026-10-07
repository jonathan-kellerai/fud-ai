//
//  TrainProgressStore.swift
//  calorietracker
//
//  What decides today's program day besides the program itself: completed
//  sessions (from the on-device workout log) and today's pick from the Change
//  sheet. Both survive relaunches.
//

import Foundation
import Observation

@Observable
final class TrainProgressStore {
    static let shared = TrainProgressStore()

    static let historyKey = "jl.physical.trainHistory.v1"
    static let overrideKey = "jl.physical.todayOverride.v1"

    private(set) var history: [CompletedProgramSession]
    private(set) var override: TodayWorkoutOverride?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        history = Self.decode([CompletedProgramSession].self, defaults.data(forKey: Self.historyKey)) ?? []
        override = Self.decode(TodayWorkoutOverride.self, defaults.data(forKey: Self.overrideKey))
    }

    /// Replaces the completed sessions outright (Visual QA and tests).
    func replaceHistory(with workouts: [RemoteWorkout], days: [TrainingProgramDay]) {
        history = workouts.compactMap { CompletedProgramSession(remote: $0, days: days) }
        persistHistory()
        clearOverrideIfConsumed()
    }

    /// Completed sessions from the on-device workout log. Until a file import
    /// has brought the bridge-era history into the log, the sessions cached
    /// from the last bridge list (builds before 70) count too, so upgrading
    /// doesn't restart the cycle. That cache isn't rewritten before then, so a
    /// workout deleted from the log never lingers in it.
    func adopt(_ log: WorkoutLogStore, days: [TrainingProgramDay]) {
        let fromLog = log.workouts.compactMap { CompletedProgramSession(remote: $0, days: days) }
        if log.hasImportedHistory {
            history = fromLog
            persistHistory()
        } else {
            let cached = Self.decode([CompletedProgramSession].self, defaults.data(forKey: Self.historyKey)) ?? []
            history = cached + fromLog.filter { !cached.contains($0) }
        }
        clearOverrideIfConsumed()
    }

    /// Picking a day in the Change sheet. Picking the day today would have
    /// anyway clears the override.
    func choose(
        dayIndex: Int,
        in body: TrainingProgramBody,
        on date: Date,
        draft: WorkoutDraft?,
        calendar: Calendar = .current
    ) {
        let next = TrainingProgramSchedule.overrideAfterPicking(
            dayIndex,
            in: body,
            on: date,
            context: context(draft: draft, days: body.days),
            calendar: calendar
        )
        if let next {
            setOverride(dayIndex: next.dayIndex, on: date, calendar: calendar)
        } else {
            clearOverride()
        }
    }

    func setOverride(dayIndex: Int, on date: Date, calendar: Calendar = .current) {
        let picked = TodayWorkoutOverride(
            date: SessionDateFormatting.calendarDateString(from: date, calendar: calendar),
            dayIndex: dayIndex
        )
        override = picked
        if let data = try? JSONEncoder().encode(picked) {
            defaults.set(data, forKey: Self.overrideKey)
        }
    }

    func clearOverride() {
        override = nil
        defaults.removeObject(forKey: Self.overrideKey)
    }

    func context(draft: WorkoutDraft?, days: [TrainingProgramDay]) -> TrainingDayContext {
        let inProgress = draft.flatMap { draft -> TrainingDayContext.Draft? in
            guard let dayIndex = CompletedProgramSession.dayIndex(
                programDay: draft.programDay, title: draft.title, days: days
            ) else { return nil }
            return TrainingDayContext.Draft(dayIndex: dayIndex, sessionDate: draft.sessionDate)
        }
        return TrainingDayContext(history: history, override: override, inProgress: inProgress)
    }

    private func clearOverrideIfConsumed() {
        if let override, override.isConsumed(by: history) {
            clearOverride()
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
