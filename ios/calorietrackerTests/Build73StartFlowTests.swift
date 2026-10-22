import Foundation
import Testing
@testable import calorietracker

/// Build 73: one unsaved session on Today, the logger sheet survives the first
/// set, the rest screen says what it is logging, and programs live on the phone.
extension WorkoutDraftStoreTests {
    private static var iosRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func todayShowsOnlyResumeWhenTheDraftIsThePlannedDay() {
        let day = ProgramV2Templates.day2UpperPush
        let draft = WorkoutDraft(day: day, now: Date())
        #expect(TodayWorkoutAction.decide(draft: draft, plannedDayID: day.id) == .resume)
        #expect(TodayWorkoutAction.decide(draft: draft, plannedDayID: "Day9_Other") == .resumeOtherOrStart)
        #expect(TodayWorkoutAction.decide(draft: draft, plannedDayID: nil) == .resumeOtherOrStart)
        #expect(TodayWorkoutAction.decide(draft: nil, plannedDayID: day.id) == .start)
    }

    /// Build 71 put `.sheet(item: $loggingDay)` on the Home card ForEach, which
    /// copies it onto every card section. The first logged set creates the draft,
    /// the Today section gains the Resume row, and the logger was dismissed.
    @Test func homeLoggerSheetIsHostedOnceOutsideTheCardForEach() throws {
        let cards = try String(contentsOf: Self.iosRoot.appendingPathComponent("calorietracker/Views/HomeV2Cards.swift"), encoding: .utf8)
        let home = try String(contentsOf: Self.iosRoot.appendingPathComponent("calorietracker/Views/Home/HomeView.swift"), encoding: .utf8)
        #expect(!cards.contains(".sheet(item: $loggingDay)"))
        #expect(home.components(separatedBy: ".sheet(item: $workoutLoggingDay)").count == 2)
    }

    @Test func loggingTheLastSupersetMemberAlwaysRestartsRest() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ProgramV2Templates.day4UpperPhysique
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        let pair = try #require(entry.order(in: store).blocks.first { $0.isSuperset })
        let last = try #require(pair.exercises.last)
        rest.start(seconds: 5) // a stale countdown from an earlier set
        // Partner skipped: the round is incomplete, but a set was logged.
        let index = try #require(entry.log(last, at: 0, in: store, startedAt: Date(),
            value: LoggedSet(weight: 25, reps: 12, rir: 2, rpeText: "")))
        entry.startRestAfterLogging(last, at: index, in: store, rest: rest)
        #expect(rest.duration == SupersetGrouping.supersetRestSeconds(for: pair))
    }

    @Test func loggingAFirstSupersetMemberStopsAStaleRest() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ProgramV2Templates.day4UpperPhysique
        let store = WorkoutDraftStore(directory: directory)
        let entry = WorkoutSetEntry(day: day)
        let rest = RestSession()
        let pair = try #require(entry.order(in: store).blocks.first { $0.isSuperset })
        let first = try #require(pair.exercises.first)
        rest.start(seconds: 50)
        let index = try #require(entry.log(first, at: 0, in: store, startedAt: Date(),
            value: LoggedSet(weight: 25, reps: 12, rir: 2, rpeText: "")))
        entry.startRestAfterLogging(first, at: index, in: store, rest: rest)
        #expect(!rest.isActive)
    }

    @Test func restEntrySaysExerciseSetAndWhetherItAddsOrEdits() {
        let exercise = ProgramV2Exercise(key: "chest", name: "Chest Press", sets: 2, reps: "8-12",
            restSeconds: 90...120, rirTarget: "3-4 RIR", startLoadLb: 100, notes: "")
        func next(_ editing: Bool) -> RestNextSet {
            RestNextSet(step: ExerciseStep(exerciseName: "Chest Press", setIndex: 1), exercise: exercise,
                value: LoggedSet(weight: 100, reps: 10, rir: 3, rpeText: ""), targetChips: [], reference: "",
                referenceLoad: 100, reason: "", isHold: false, isEditing: editing)
        }
        #expect(next(false).headline == "Chest Press · Set 2 of 2")
        #expect(next(false).modeLabel.hasPrefix("ADDING SET 2"))
        #expect(next(false).logLabel == "Log Set 2 · 100 × 10")
        #expect(next(true).modeLabel.hasPrefix("EDITING SET 2"))
        #expect(next(true).logLabel == "Save Set 2 · 100 × 10")
    }

    // MARK: Programs on the phone

    private func bundledV3() throws -> TrainingProgramRecord {
        let data = try Data(contentsOf: Self.iosRoot.appendingPathComponent("calorietracker/Resources/ProgramV3.json"))
        return try #require(LocalProgramStore.decodeSeed(data))
    }

    @Test func bundledV3IsTheApprovedFourDayProgram() throws {
        let v3 = try bundledV3()
        let body = try #require(v3.body)
        #expect(v3.name == "Program V3")
        #expect(body.startDate == "2026-10-19")
        #expect(body.days.map(\.weekday) == ["mon", "tue", "thu", "fri"])
    }

    @Test func seedReplacesAnOldActiveProgramAndLeavesTheDraftAlone() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let drafts = WorkoutDraftStore(directory: directory)
        drafts.update(ProgramV2Templates.day2UpperPush) { $0.sets["x"] = [LoggedSet(weight: 1, reps: 1, rir: 1, rpeText: "")] }
        let draftBefore = drafts.draft

        let store = LocalProgramStore(directory: directory, defaults: defaults, mirrorsActiveProgram: false)
        let v3 = try bundledV3()
        store.seedIfNeeded(seed: v3)
        #expect(store.activeProgramNow()?.id == v3.id)

        // A later edit activates a new version and archives V3; reseeding does not undo it.
        let created = try await store.createProgram(name: "Mine", body: try #require(v3.body))
        try await store.activateProgram(id: created.id)
        store.seedIfNeeded(seed: v3)
        let all = try await store.listPrograms()
        #expect(store.activeProgramNow()?.id == created.id)
        #expect(all.filter { $0.status == .active }.count == 1)
        #expect(all.first { $0.id == v3.id }?.status == .archived)
        #expect(WorkoutDraftStore(directory: directory).draft == draftBefore)
    }
}
