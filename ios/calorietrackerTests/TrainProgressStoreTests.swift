import Foundation
import Testing
@testable import calorietracker

/// Today's pick and the completed-session cache survive relaunches, and the
/// pick only ever applies to the day it was made.
@MainActor
struct TrainProgressStoreTests {
    private let body = TrainingProgramBody.bundledV2()
    private var eastern: Calendar { ProgramWeekRules.easternCalendar }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "TrainProgressStoreTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    private func day(_ civil: String) -> Date {
        SessionDateFormatting.date(from: civil, calendar: eastern)!
    }

    private func remote(_ programDay: String, _ date: String, kind: String = "COMPLETED") -> RemoteWorkout {
        RemoteWorkout(
            id: UUID().uuidString,
            kind: kind,
            programVersion: "program-v2",
            programDay: programDay,
            title: "",
            units: "lb",
            sessionDate: date,
            conditioning: nil,
            notes: [],
            contentHash: nil,
            synthetic: nil,
            recordedAt: nil
        )
    }

    private func plan(_ store: TrainProgressStore, _ civil: String, draft: WorkoutDraft? = nil) -> TrainingDayResolution {
        TrainingProgramSchedule.resolution(body, on: day(civil),
            context: store.context(draft: draft, days: body.days), calendar: eastern)
    }

    @Test func overrideSurvivesARestartAndExpiresTheNextDay() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        TrainProgressStore(defaults: defaults).setOverride(dayIndex: 3, on: day("2026-10-06"), calendar: eastern)

        let relaunched = TrainProgressStore(defaults: defaults)
        #expect(relaunched.override == TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3))
        #expect(plan(relaunched, "2026-10-06").plan == .session(dayIndex: 3, name: "Pull / Hinge", stepsTarget: 10_000))
        #expect(plan(relaunched, "2026-10-07").reason == .cycle)
    }

    @Test func clearingTheOverrideRemovesItFromDisk() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        store.setOverride(dayIndex: 4, on: day("2026-10-06"), calendar: eastern)
        store.clearOverride()
        #expect(store.override == nil)
        #expect(TrainProgressStore(defaults: defaults).override == nil)
    }

    @Test func choosingTheSuggestedDayClearsAndAnotherDaySets() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        store.replaceHistory(with: [remote("1-mon", "2026-09-28"), remote("2-tue", "2026-09-29"),
                                    remote("3-wed", "2026-09-30"), remote("4-thu", "2026-10-01")], days: body.days)
        store.choose(dayIndex: 3, in: body, on: day("2026-10-06"), draft: nil, calendar: eastern)
        #expect(store.override == TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3))
        store.choose(dayIndex: 1, in: body, on: day("2026-10-06"), draft: nil, calendar: eastern)
        #expect(store.override == nil)
        #expect(TrainProgressStore(defaults: defaults).override == nil)
    }

    @Test func historyCacheRoundTripsAndTheBridgeListReplacesIt() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        store.replaceHistory(with: [
            remote("1-mon", "2026-09-28"), remote("2-tue", "2026-09-29"),
            remote("3-wed", "2026-09-30"), remote("4-thu", "2026-10-01T00:00:00.000Z"),
            remote("Workout", "2026-10-02", kind: "strength"),
        ], days: body.days)
        #expect(store.history.map(\.dayIndex) == [1, 2, 3, 4])

        let relaunched = TrainProgressStore(defaults: defaults)
        #expect(relaunched.history == store.history)
        #expect(plan(relaunched, "2026-10-06").plan == .session(dayIndex: 1, name: "Lower A", stepsTarget: 10_000))

        relaunched.replaceHistory(with: [remote("1-mon", "2026-10-05")], days: body.days)
        #expect(TrainProgressStore(defaults: defaults).history == [CompletedProgramSession(dayIndex: 1, sessionDate: "2026-10-05")])
    }

    @Test func aRecordedSaveAdvancesTheCardWithoutABridgeList() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        store.setOverride(dayIndex: 3, on: day("2026-10-06"), calendar: eastern)
        store.recordCompleted(programDay: "3-wed", title: "Pull / Hinge", sessionDate: "2026-10-06")
        let today = plan(store, "2026-10-06")
        #expect(today.reason == .loggedToday)
        #expect(today.plan == .session(dayIndex: 3, name: "Pull / Hinge", stepsTarget: 10_000))
        #expect(plan(TrainProgressStore(defaults: defaults), "2026-10-07").plan
                == .session(dayIndex: 4, name: "Upper Physique", stepsTarget: 10_000))
        store.recordCompleted(programDay: "not a day", title: "", sessionDate: "2026-10-07")
        #expect(store.history.count == 1)
    }

    @Test func aSaveOnTheOverridesDateConsumesIt() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        store.setOverride(dayIndex: 3, on: day("2026-10-06"), calendar: eastern)
        store.recordCompleted(programDay: "3-wed", title: "Pull / Hinge", sessionDate: "2026-10-06")
        #expect(store.override == nil)
        #expect(defaults.data(forKey: TrainProgressStore.overrideKey) == nil)
        #expect(TrainProgressStore(defaults: defaults).override == nil)
    }

    @Test func aBridgeListWithASessionOnTheOverridesDateConsumesIt() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        store.setOverride(dayIndex: 3, on: day("2026-10-06"), calendar: eastern)
        // Logged on another device (the gym PWA), so it arrives only with the list.
        store.replaceHistory(with: [remote("4-thu", "2026-10-01"), remote("Day3_PullHinge", "2026-10-06")],
                             days: body.days)
        #expect(store.override == nil)
        #expect(defaults.data(forKey: TrainProgressStore.overrideKey) == nil)
        #expect(TrainProgressStore(defaults: defaults).override == nil)
    }

    @Test func todaysOverrideSurvivesASaveDatedYesterday() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        let picked = TodayWorkoutOverride(date: "2026-10-06", dayIndex: 3)
        store.setOverride(dayIndex: 3, on: day("2026-10-06"), calendar: eastern)
        store.recordCompleted(programDay: "1-mon", title: "Lower A", sessionDate: "2026-10-05")
        #expect(store.override == picked)
        store.replaceHistory(with: [remote("1-mon", "2026-10-05")], days: body.days)
        #expect(store.override == picked)
        #expect(TrainProgressStore(defaults: defaults).override == picked)
    }

    @Test func contextCarriesTodaysDraft() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrainProgressStore(defaults: defaults)
        var draft = WorkoutDraft(day: body.programV2Day(for: body.days[1], on: day("2026-10-06")), now: day("2026-10-06"))
        draft.sessionDate = "2026-10-06"
        #expect(store.context(draft: draft, days: body.days).inProgress
                == TrainingDayContext.Draft(dayIndex: 2, sessionDate: "2026-10-06"))
        #expect(plan(store, "2026-10-06", draft: draft).reason == .inProgress)
        #expect(store.context(draft: nil, days: body.days).inProgress == nil)
    }
}
