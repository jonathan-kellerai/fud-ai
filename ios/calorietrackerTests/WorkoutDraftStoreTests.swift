import Foundation
import Testing
@testable import calorietracker

/// The in-progress logger session must survive the logger going away and
/// only disappear once the bridge accepts it or the user discards it.
@MainActor
struct WorkoutDraftStoreTests {
    private struct PostFailed: Error {}

    @Test func draftRoundTripsThroughJSON() throws {
        var draft = WorkoutDraft(day: sampleDay(), now: fixedDate)
        draft.sets["Leg press"] = [
            LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "8"),
            LoggedSet(weight: 150.5, reps: 10, rir: 1, rpeText: "8,5"),
        ]
        draft.conditioningCompleted = true

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(WorkoutDraft.self, from: data)

        #expect(decoded == draft)
        #expect(decoded.programDay == "Day1_LowerA")
        #expect(decoded.exercises.map(\.name) == ["Leg press", "Leg curl"])
        #expect(decoded.exercises.first?.restLowerSeconds == 90)
        #expect(decoded.exercises.first?.restUpperSeconds == 120)
        #expect(decoded.sets["Leg press"]?.last?.rpeText == "8,5")
        #expect(decoded.programV2Day.exercises.first?.restSeconds == 90...120)
    }

    @Test func draftSurvivesStoreReinit() throws {
        try withDirectory { directory in
            let day = sampleDay()
            let store = WorkoutDraftStore(directory: directory)
            store.update(day) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "8")]
                draft.conditioningCompleted = true
            }

            let reopened = WorkoutDraftStore(directory: directory)
            let draft = try #require(reopened.existingDraft(for: day))
            #expect(draft.programDay == store.draft?.programDay)
            #expect(draft.sets == store.draft?.sets)
            #expect(draft.sets["Leg press"]?.first?.weight == 145)
            #expect(draft.sets["Leg press"]?.first?.reps == 12)
            #expect(draft.sets["Leg press"]?.first?.rir == 2)
            #expect(draft.sets["Leg press"]?.first?.rpeText == "8")
            #expect(draft.conditioningCompleted)
            #expect(!reopened.hasDraft(otherThan: day))
        }
    }

    @Test func successfulSaveClearsDraft() async throws {
        try await withAsyncDirectory { directory in
            let day = sampleDay()
            let store = WorkoutDraftStore(directory: directory)
            store.update(day) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "8,5")]
                draft.sets["Leg curl"] = [LoggedSet(weight: 60, reps: 15, rir: 1, rpeText: "")]
            }

            try await confirmation("posts the draft to the bridge") { posted in
                try await store.save(now: fixedDate) { payload in
                    posted()
                    #expect(payload.programDay == "Day1_LowerA")
                    #expect(payload.sets.map(\.exercise) == ["Leg press", "Leg curl"])
                    #expect(payload.sets.map(\.order) == [0, 1])
                    #expect(payload.sets.first?.rpe == 8.5)
                    #expect(payload.sets.last?.rpe == nil)
                    #expect(payload.conditioning == nil)
                }
            }

            #expect(store.draft == nil)
            #expect(WorkoutDraftStore(directory: directory).draft == nil)
        }
    }

    @Test func failedSaveKeepsDraft() async throws {
        try await withAsyncDirectory { directory in
            let day = sampleDay()
            let store = WorkoutDraftStore(directory: directory)
            store.update(day) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
            }
            let before = store.draft

            await #expect(throws: PostFailed.self) {
                try await store.save { _ in throw PostFailed() }
            }

            #expect(store.draft != nil)
            #expect(store.draft == before)
            #expect(WorkoutDraftStore(directory: directory).draft?.sets == before?.sets)
        }
    }

    @Test func editsDuringSaveSurviveSuccessfulSave() async throws {
        try await withAsyncDirectory { directory in
            let day = sampleDay()
            let store = WorkoutDraftStore(directory: directory)
            store.update(day) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
            }

            try await store.save(now: fixedDate) { payload in
                #expect(payload.sets.map(\.exercise) == ["Leg press"])
                store.update(day) { draft in
                    draft.sets["Leg curl"] = [LoggedSet(weight: 60, reps: 15, rir: 1, rpeText: "")]
                }
            }

            #expect(store.draft?.sets["Leg curl"]?.first?.weight == 60)
            #expect(store.draft?.sets["Leg press"]?.count == 1)
            let reopened = WorkoutDraftStore(directory: directory)
            #expect(reopened.draft?.sets == store.draft?.sets)
        }
    }

    @Test func payloadKeepsSetsForExercisesNoLongerInDay() {
        var draft = WorkoutDraft(day: sampleDay(), now: fixedDate)
        draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
        draft.sets["Hip thrust"] = [LoggedSet(weight: 185, reps: 10, rir: 2, rpeText: "8")]

        let payload = draft.payload(now: fixedDate)

        #expect(payload.sets.map(\.exercise) == ["Leg press", "Hip thrust"])
        #expect(payload.sets.map(\.order) == [0, 1])
        #expect(payload.sets.last?.load == 185)
        #expect(payload.sets.last?.rpe == 8)
    }

    @Test func discardClearsDraft() throws {
        try withDirectory { directory in
            let day = sampleDay()
            let store = WorkoutDraftStore(directory: directory)
            store.update(day) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
            }
            #expect(store.draft != nil)

            store.discard()

            #expect(store.draft == nil)
            #expect(WorkoutDraftStore(directory: directory).draft == nil)
        }
    }

    @Test func sessionDateIsTheDayTheWorkoutStarted() async throws {
        let started = try localDate(year: 2026, month: 9, day: 29, hour: 23, minute: 50)
        let saved = try localDate(year: 2026, month: 9, day: 30, hour: 0, minute: 20)
        let startedStamp = isoTimestamp(started)
        let savedStamp = isoTimestamp(saved)

        var draft = WorkoutDraft(day: sampleDay(), now: started)
        draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
        let payload = draft.payload(now: saved)
        #expect(draft.startedAt == started)
        #expect(payload.sessionDate == "2026-09-29")
        #expect(payload.openedAtUtc == startedStamp)
        #expect(payload.recordedAtUtc == savedStamp)

        try await withAsyncDirectory { directory in
            let day = sampleDay()
            let store = WorkoutDraftStore(directory: directory)
            store.update(day, startedAt: started) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
            }
            // Later edits never move the start of an existing draft.
            store.update(day, startedAt: saved) { draft in
                draft.sets["Leg curl"] = [LoggedSet(weight: 60, reps: 15, rir: 1, rpeText: "")]
            }
            #expect(store.draft?.startedAt == started)
            #expect(store.draft?.sessionDate == "2026-09-29")

            try await confirmation("posts the start day") { posted in
                try await store.save(now: saved) { payload in
                    posted()
                    #expect(payload.sessionDate == "2026-09-29")
                    #expect(payload.openedAtUtc == startedStamp)
                    #expect(payload.recordedAtUtc == savedStamp)
                }
            }
            #expect(store.draft == nil)
        }
    }

    @Test func draftWrittenBeforeStartDateAndSupersetsStillDecodes() throws {
        let json = """
        {"programDay":"Day1_LowerA","title":"Lower A","conditioning":"8 min steady bike","conditioningMinimum":"5 min",
         "exercises":[{"key":"leg press","name":"Leg press","sets":3,"reps":"10-15","restLowerSeconds":90,
                       "restUpperSeconds":120,"rirTarget":"2","startLoadLb":145,"notes":"Anchor.","loadNote":""}],
         "sets":{"Leg press":[{"weight":145,"reps":12,"rir":2,"rpeText":"8"}]},
         "conditioningCompleted":false,"sessionDate":"2026-09-29","updatedAt":780000000}
        """
        let draft = try JSONDecoder().decode(WorkoutDraft.self, from: Data(json.utf8))
        #expect(draft.startedAt == nil)
        #expect(draft.exercises.first?.supersetGroup == nil)
        #expect(draft.programV2Day.exercises.first?.supersetGroup == nil)
        #expect(draft.sets["Leg press"]?.first?.reps == 12)

        let payload = draft.payload(now: fixedDate)
        #expect(payload.sessionDate == "2026-09-29")
        #expect(payload.openedAtUtc == payload.recordedAtUtc)

        try withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: directory.appendingPathComponent(WorkoutDraftStore.fileName))
            let store = WorkoutDraftStore(directory: directory)
            #expect(store.draft?.programDay == "Day1_LowerA")
            #expect(store.draft?.sets == draft.sets)
        }
    }

    @Test func draftCarriesSupersetGroup() throws {
        let day = TrainingProgramBody.bundledV2().days[3].asProgramV2Day()
        let draft = WorkoutDraft(day: day, now: fixedDate)
        let decoded = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))

        let groups = decoded.programV2Day.exercises.map(\.supersetGroup)
        #expect(groups == day.exercises.map(\.supersetGroup))
        #expect(groups.contains("curl-pressdown"))
    }

    @Test func failedDiskWriteKeepsSetsAndReportsError() throws {
        // A regular file where the draft directory should be makes every write fail.
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-draft-blocked-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let day = sampleDay()
        let store = WorkoutDraftStore(directory: blocked)
        store.update(day) { draft in
            draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
        }

        #expect(store.persistError != nil)
        #expect(store.draft?.sets["Leg press"]?.first?.reps == 12)

        store.dismissPersistError()
        #expect(store.persistError == nil)

        store.update(day) { draft in
            draft.sets["Leg press"]?.append(LoggedSet(weight: 145, reps: 11, rir: 1, rpeText: ""))
        }
        #expect(store.persistError != nil)
        #expect(store.draft?.sets["Leg press"]?.count == 2)

        // The next successful write clears the error.
        try FileManager.default.removeItem(at: blocked)
        store.update(day) { draft in
            draft.conditioningCompleted = true
        }
        #expect(store.persistError == nil)
        #expect(WorkoutDraftStore(directory: blocked).draft?.sets["Leg press"]?.count == 2)
    }

    @Test func goodDirectoryHasNoPersistError() throws {
        try withDirectory { directory in
            let store = WorkoutDraftStore(directory: directory)
            store.update(sampleDay()) { draft in
                draft.sets["Leg press"] = [LoggedSet(weight: 145, reps: 12, rir: 2, rpeText: "")]
            }
            #expect(store.persistError == nil)
        }
    }

    // MARK: - Coach handoff

    @Test func handoffWithoutDraftOpensToday() {
        let today = sampleDay()
        guard case .openToday(let day) = WorkoutHandoffDecision.decide(draft: nil, today: today) else {
            Issue.record("Expected openToday")
            return
        }
        #expect(day.id == today.id)
    }

    @Test func handoffWithSameDayDraftOpensToday() {
        let today = sampleDay()
        let draft = WorkoutDraft(day: today, now: fixedDate)
        guard case .openToday(let day) = WorkoutHandoffDecision.decide(draft: draft, today: today) else {
            Issue.record("Expected openToday")
            return
        }
        #expect(day.id == today.id)
    }

    @Test func handoffWithOtherDayDraftOffersResume() {
        let today = sampleDay()
        var draft = WorkoutDraft(day: otherDay(), now: fixedDate)
        draft.sets["Chest press"] = [LoggedSet(weight: 100, reps: 10, rir: 2, rpeText: "")]
        guard case .offerResume(let offered, let offeredToday) = WorkoutHandoffDecision.decide(draft: draft, today: today) else {
            Issue.record("Expected offerResume")
            return
        }
        #expect(offered == draft)
        #expect(offered.programV2Day.id == "Day2_UpperA")
        #expect(offeredToday.id == today.id)
    }

    // MARK: - Helpers

    private func otherDay() -> ProgramV2Day {
        ProgramV2Day(
            id: "Day2_UpperA",
            title: "Upper A",
            conditioning: "",
            conditioningMinimum: "",
            exercises: [
                ProgramV2Exercise(
                    key: "chest press",
                    name: "Chest press",
                    sets: 3,
                    reps: "8-12",
                    restSeconds: 90...120,
                    rirTarget: "2",
                    startLoadLb: nil,
                    notes: ""
                ),
            ]
        )
    }

    private var fixedDate: Date { Date(timeIntervalSince1970: 1_790_000_000) }

    private func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(Calendar(identifier: .gregorian).date(from: components))
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func sampleDay() -> ProgramV2Day {
        ProgramV2Day(
            id: "Day1_LowerA",
            title: "Lower A",
            conditioning: "8 min steady bike",
            conditioningMinimum: "5 min",
            exercises: [
                ProgramV2Exercise(
                    key: "leg press",
                    name: "Leg press",
                    sets: 3,
                    reps: "10-15",
                    restSeconds: 90...120,
                    rirTarget: "2",
                    startLoadLb: 145,
                    notes: "Anchor."
                ),
                ProgramV2Exercise(
                    key: "leg curl",
                    name: "Leg curl",
                    sets: 2,
                    reps: "12-15",
                    restSeconds: 60...60,
                    rirTarget: "1",
                    startLoadLb: nil,
                    notes: ""
                ),
            ]
        )
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func withAsyncDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-draft-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
