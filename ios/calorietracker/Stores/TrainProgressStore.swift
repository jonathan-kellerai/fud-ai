//
//  TrainProgressStore.swift
//  calorietracker
//
//  What decides today's program day besides the program itself: completed
//  sessions (the last bridge list, plus saves since) and today's pick from
//  the Change sheet. Both survive relaunches so offline launches keep the day.
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

    /// The bridge list is the source of truth once it loads; it replaces the cache.
    func replaceHistory(with workouts: [RemoteWorkout], days: [TrainingProgramDay]) {
        history = workouts.compactMap { CompletedProgramSession(remote: $0, days: days) }
        persistHistory()
        clearOverrideIfConsumed()
    }

    /// A save the bridge accepted, so the card advances even if the next
    /// list fails. The next successful list replaces it.
    func recordCompleted(programDay: String, title: String, sessionDate: String, now: Date = Date()) {
        guard let dayIndex = CompletedProgramSession.dayIndex(programDay: programDay, title: title, days: []) else {
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        history.append(CompletedProgramSession(
            dayIndex: dayIndex,
            sessionDate: sessionDate,
            recordedAt: formatter.string(from: now)
        ))
        persistHistory()
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
