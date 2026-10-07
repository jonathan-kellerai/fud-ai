import Foundation
import Testing
@testable import calorietracker

/// Workouts make no network request at all, with no bridge key configured:
/// save, reload, correct, delete, import, the History/Home/Train reads, last
/// performance (the progression input), Progress, and backup/restore.
///
/// Why a stub transport: the app reaches the network through URLSession.shared,
/// so a URLProtocol registered for the test's duration is the only way to
/// prove "no request" without adding hooks to production code. It records
/// every request (no host exemptions) and fails it. A control request proves
/// it is in the path before the flows run. Swift Testing runs suites
/// concurrently in one process even with -parallel-testing-enabled NO, so CI
/// skips this suite in the shared run and runs it alone in its own xcodebuild
/// invocation (ios-build.yml), like PeptideNoNetworkTests. `.serialized` keeps
/// its own tests one at a time.
@MainActor
@Suite(.serialized)
struct WorkoutNoNetworkTests {
    private let started = Date(timeIntervalSince1970: 1_791_300_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("workout-no-network-\(UUID().uuidString)", isDirectory: true)
    }

    /// Registers the tripwire with no bridge key, proves it intercepts, runs
    /// `flows`, lets stray tasks run, then returns every request it saw.
    private func requests(during flows: () async throws -> Void) async throws -> [String] {
        let service = NeonBridgeService.shared
        let savedSettings = service.settings
        service.settings = NeonBridgeSettings(baseURL: NeonBridgeSettings.defaultBaseURL, apiKey: nil)
        URLProtocol.registerClass(WorkoutNetworkTripwire.self)
        defer {
            URLProtocol.unregisterClass(WorkoutNetworkTripwire.self)
            service.settings = savedSettings
            WorkoutNetworkTripwire.log.reset()
        }
        WorkoutNetworkTripwire.log.reset()

        let control = try #require(URL(string: "https://workout-tripwire-control.invalid/ping"))
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(from: control)
        }
        #expect(WorkoutNetworkTripwire.log.snapshot() == ["GET workout-tripwire-control.invalid/ping"])
        WorkoutNetworkTripwire.log.reset()

        try await flows()
        // Anything a flow left running in the background gets its chance to call out.
        try await Task.sleep(for: .milliseconds(500))
        await Task.yield()
        return WorkoutNetworkTripwire.log.snapshot()
    }

    @Test func savingCorrectingAndDeletingStayOnThePhone() async throws {
        let folder = tempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let logURL = folder.appendingPathComponent("WorkoutLog/\(WorkoutLogFile.fileName)")
        let seen = try await requests {
            let drafts = WorkoutDraftStore(directory: folder)
            let log = WorkoutLogStore(persistence: .file(logURL))
            let day = ProgramV2Templates.day1LowerA
            drafts.update(day, startedAt: started) { draft in
                draft.sets[day.exercises[0].name] = [LoggedSet(weight: 180, reps: 15, rir: 4, rpeText: "")]
                draft.conditioningCompleted = true
            }
            try drafts.save(to: log, now: started.addingTimeInterval(3600))
            #expect(drafts.draft == nil)

            let relaunched = WorkoutLogStore(persistence: .file(logURL))
            let id = try #require(relaunched.workouts.first?.id)
            let detail = try #require(relaunched.detail(id: id))
            try relaunched.correct(id: id, with: WorkoutPayload.historyCorrection(
                programVersion: detail.workout.programVersion, programDay: detail.workout.programDay,
                sessionDate: detail.workout.sessionDate, title: "Lower A (fixed)", conditioning: "",
                notesText: "typo", sets: detail.sets.map(EditableBridgeSet.init)))
            #expect(relaunched.record(id: id)?.revisions.count == 1)
            try relaunched.delete(id: id)
            #expect(relaunched.workouts.isEmpty)
            #expect(relaunched.persistError == nil)
        }
        #expect(seen.isEmpty, "Workout requests: \(seen)")
    }

    @Test func importingAndEveryReadStayOnThePhone() async throws {
        let folder = tempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "workout-no-network-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let seen = try await requests {
            let log = WorkoutLogStore(persistence: .file(folder.appendingPathComponent(WorkoutLogFile.fileName)))
            let file = try WorkoutImportFile.load(from: WorkoutImportFixture.url)
            #expect(log.importSummary(of: file).added == 11)
            #expect(try log.importFile(file).added == 11)
            #expect(try log.importFile(file).added == 0)

            // History and Home.
            #expect(log.workouts.count == 11)
            let first = try #require(log.workouts.first)
            #expect(log.detail(id: first.id)?.sets.isEmpty == false)
            // Train's next-in-cycle.
            let body = TrainingProgramBody.bundledV2()
            let progress = TrainProgressStore(defaults: defaults)
            progress.adopt(log, days: body.days)
            #expect(!progress.history.isEmpty)
            // Last performance, the input to the progression rule.
            let last = ExerciseHistoryLoader.load(programDay: "1-mon", log: log)
            #expect(last[LastPerformanceBuilder.key(for: "Leg press")] != nil)
            // Progress's Training card.
            let summary = ProgressTrainingLoader.summary(range: .allTime, details: log.details,
                                                         now: Date(timeIntervalSince1970: 1_791_400_000))
            #expect(summary.totalSessions == 11)
        }
        #expect(seen.isEmpty, "Workout requests: \(seen)")
    }

    @Test func backupRestoreAndDeleteEverythingStayOnThePhone() async throws {
        let folder = tempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "workout-no-network-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let seen = try await requests {
            let source = WorkoutLogStore(persistence: .file(folder.appendingPathComponent("a/\(WorkoutLogFile.fileName)")))
            try source.importFile(try WorkoutImportFile.load(from: WorkoutImportFixture.url))
            let values = CloudBackupService(defaults: defaults, workouts: source).snapshotValues()
            let target = WorkoutLogStore(persistence: .file(folder.appendingPathComponent("b/\(WorkoutLogFile.fileName)")))
            let service = CloudBackupService(defaults: defaults, workouts: target)
            service.applyValues(values)
            #expect(service.errorMessage == nil)
            #expect(target.workouts.count == 11)
            target.deleteAll()
            #expect(target.workouts.isEmpty)
        }
        #expect(seen.isEmpty, "Workout requests: \(seen)")
    }
}

/// Intercepts every request while registered, records it and fails it. Its
/// own class and log (the lock-protected PeptideNetworkRequestLog type), so it
/// never shares state with the peptide tripwire.
/// URLProtocol requires restating inherited unchecked Sendable: this subclass
/// adds no mutable instance state, and its shared log is lock-protected.
nonisolated final class WorkoutNetworkTripwire: URLProtocol, @unchecked Sendable {
    static let log = PeptideNetworkRequestLog()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
