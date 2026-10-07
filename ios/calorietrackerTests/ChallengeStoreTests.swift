import Foundation
import Testing
@testable import calorietracker

@MainActor
struct ChallengeStoreTests {
    private typealias F = ChallengeEngineTests

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("challenge-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("challenges.v1.json")
    }

    private func store(_ url: URL) -> ChallengeStore {
        ChallengeStore(fileURL: url, calendar: F.newYork())
    }

    private func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    private var swings: Challenge { F.challenge(.total(10_000)) }

    private var stepsChallenge: Challenge {
        var challenge = F.challenge(.total(100_000), metric: .steps)
        challenge.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        challenge.title = "100K STEPS"
        return challenge
    }

    @Test func roundTripsChallengesEntriesCheckInsAndRewards() throws {
        let url = tempFile()
        let first = store(url)
        let now = F.at(2026, 10, 14)
        try first.create(swings, now: now)
        try first.add(value: 2_600, day: F.start, note: "first set", to: swings.id, now: now)
        var habit = F.challenge(.dailyHabit(.checkIn))
        habit.id = UUID()
        habit.title = "NO ALCOHOL"
        try first.create(habit, now: now)
        try first.setCheckIn(true, day: F.start, for: habit.id, now: now)

        let reloaded = store(url)
        #expect(reloaded.challenges.map(\.title) == ["10K KB SWINGS", "NO ALCOHOL"])
        #expect(reloaded.entries(for: swings.id).map(\.value) == [2_600])
        #expect(reloaded.entries(for: swings.id).first?.note == "first set")
        #expect(reloaded.checkIns[habit.id]?[F.start] == true)
        #expect(reloaded.rewards(for: swings.id).map(\.rewardKey) == ["percent.25"])
        #expect(reloaded.lastSaveError == nil)
    }

    @Test func mainFileIsExcludedFromBackup() throws {
        let url = tempFile()
        let challenges = store(url)
        try challenges.create(swings, now: F.at(2026, 10, 14))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(isExcludedFromBackup(url))
    }

    @Test func corruptFileIsKeptAsideAndTheStoreStartsEmpty() throws {
        let url = tempFile()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let challenges = store(url)
        #expect(challenges.challenges.isEmpty)
        let copies = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("challenges.corrupt-") && $0.hasSuffix(".json") }
        #expect(copies.count == 1)
        if let name = copies.first {
            let copy = directory.appendingPathComponent(name)
            #expect(try Data(contentsOf: copy) == Data("{not json".utf8))
            #expect(isExcludedFromBackup(copy))
        }
    }

    @Test func clearAllForgetsEverythingAndDeletesTheFiles() throws {
        let url = tempFile()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let challenges = store(url)
        let now = F.at(2026, 10, 14)
        try challenges.create(swings, now: now)
        try challenges.add(value: 2_600, day: F.start, to: swings.id, now: now)
        challenges.markStakePaid(swings.id, now: now)
        #expect(!challenges.rewardLog.isEmpty)
        let unrelated = directory.appendingPathComponent("other.json")
        try Data("keep".utf8).write(to: unrelated)

        var replanned: [PlannedNotification]?
        challenges.onRemindersPlanned = { replanned = $0 }
        challenges.clearAll(now: now)

        #expect(challenges.challenges.isEmpty)
        #expect(challenges.entries.isEmpty)
        #expect(challenges.checkIns.isEmpty)
        #expect(challenges.rewardLog.isEmpty)
        #expect(challenges.stakePaidAt.isEmpty)
        #expect(challenges.pendingUnlocks.isEmpty)
        #expect(challenges.progressByID.isEmpty)
        #expect(challenges.lastSaveError == nil)
        #expect(replanned?.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers == ["other.json"])
        #expect(store(url).challenges.isEmpty)
    }

    @Test func clearAllOnAnEmptyStoreIsHarmless() {
        let url = tempFile()
        let challenges = store(url)
        challenges.clearAll(now: F.at(2026, 10, 14))
        #expect(challenges.challenges.isEmpty)
        #expect(challenges.lastSaveError == nil)
    }

    @Test func writeFailureKeepsMemoryAndReportsTheError() throws {
        // The parent "directory" is a regular file, so every write fails.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("challenge-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        let challenges = store(blocker.appendingPathComponent("challenges.v1.json"))
        try challenges.create(swings, now: F.at(2026, 10, 14))
        #expect(challenges.challenges.count == 1)
        #expect(challenges.lastSaveError != nil)
    }

    @Test func undoRemovesTheEntry() throws {
        let challenges = store(tempFile())
        let now = F.at(2026, 10, 14)
        try challenges.create(swings, now: now)
        let entry = try challenges.add(value: 50, day: F.start, to: swings.id, now: now)
        challenges.undo(entryID: entry.id, now: now)
        #expect(challenges.entries(for: swings.id).isEmpty)
        #expect(challenges.progress(for: swings.id)?.total == 0)
    }

    @Test func rejectsOutOfWindowFutureAndBadValues() throws {
        let challenges = store(tempFile())
        let now = F.at(2026, 10, 14)
        try challenges.create(swings, now: now)
        #expect(throws: ChallengeStoreError.outsideWindow) {
            try challenges.add(value: 50, day: F.start.adding(days: -1), to: swings.id, now: now)
        }
        #expect(throws: ChallengeStoreError.outsideWindow) {
            try challenges.add(value: 50, day: F.start.adding(days: 5), to: swings.id, now: now)
        }
        #expect(throws: ChallengeStoreError.invalidValue) {
            try challenges.add(value: .nan, day: F.start, to: swings.id, now: now)
        }
        #expect(throws: ChallengeStoreError.invalidValue) {
            try challenges.add(value: 0, day: F.start, to: swings.id, now: now)
        }
        #expect(throws: ChallengeStoreError.notCheckIn) {
            try challenges.setCheckIn(true, day: F.start, for: swings.id, now: now)
        }
        #expect(throws: ChallengeStoreError.invalidChallenge) {
            try challenges.create(F.challenge(.total(.infinity)), now: now)
        }
        #expect(challenges.entries.isEmpty)
    }

    @Test func checkInNoReplacesYes() throws {
        let challenges = store(tempFile())
        let now = F.at(2026, 10, 12, hour: 21)
        var habit = F.challenge(.dailyHabit(.checkIn))
        habit.id = UUID()
        try challenges.create(habit, now: now)
        try challenges.setCheckIn(true, day: F.start, for: habit.id, now: now)
        #expect(challenges.progress(for: habit.id)?.todayHit == true)
        try challenges.setCheckIn(false, day: F.start, for: habit.id, now: now)
        #expect(challenges.progress(for: habit.id)?.todayHit == false)
        #expect(challenges.progress(for: habit.id)?.hitDays == 0)
    }

    @Test func automaticMetricIsUnavailableUntilItsFirstRead() throws {
        let challenges = store(tempFile())
        try challenges.create(stepsChallenge, now: F.at(2026, 10, 14))
        #expect(challenges.progress(for: stepsChallenge.id)?.status == .noData)
        challenges.setAutoValues([:], availability: .unavailable, for: stepsChallenge.id, now: F.at(2026, 10, 14))
        #expect(challenges.progress(for: stepsChallenge.id)?.status == .noData)
        #expect(challenges.lastPlannedNotifications.isEmpty)
    }

    @Test func automaticCrossingUnlocksOnceAcrossRefreshAndReload() throws {
        let url = tempFile()
        let challenges = store(url)
        let now = F.at(2026, 10, 14)
        try challenges.create(stepsChallenge, now: now)
        #expect(challenges.rewards(for: stepsChallenge.id).isEmpty)

        let steps = F.daily([12_000, 14_000])
        challenges.setAutoValues(steps, availability: .available, for: stepsChallenge.id, now: now)
        #expect(challenges.rewards(for: stepsChallenge.id).map(\.rewardKey) == ["percent.25"])
        #expect(challenges.pendingUnlocks.map(\.rewardKey) == ["percent.25"])

        // A duplicate refresh adds nothing.
        challenges.setAutoValues(steps, availability: .available, for: stepsChallenge.id, now: now)
        #expect(challenges.rewards(for: stepsChallenge.id).count == 1)
        #expect(challenges.pendingUnlocks.count == 1)

        // A downward correction keeps the unlock.
        challenges.setAutoValues(F.daily([2_000]), availability: .available, for: stepsChallenge.id, now: now)
        #expect(challenges.rewards(for: stepsChallenge.id).count == 1)

        // Reload: health numbers are gone from memory, the unlock stays, and
        // refreshing again does not duplicate it.
        let reloaded = store(url)
        #expect(reloaded.autoValues.isEmpty)
        #expect(reloaded.rewards(for: stepsChallenge.id).count == 1)
        reloaded.setAutoValues(steps, availability: .available, for: stepsChallenge.id, now: now)
        #expect(reloaded.rewards(for: stepsChallenge.id).count == 1)
        #expect(reloaded.pendingUnlocks.isEmpty)

        // No step value ever reaches the file.
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!text.contains("12000"))
        #expect(!text.contains("14000"))
    }

    @Test func claimAndStakeAreRecordedOnce() throws {
        let url = tempFile()
        let challenges = store(url)
        let now = F.at(2026, 10, 14)
        var staked = swings
        staked.stake = ChallengeStake(text: "$20 to Sam")
        try challenges.create(staked, now: now)
        try challenges.add(value: 2_500, day: F.start, to: staked.id, now: now)
        challenges.claim(rewardKey: "percent.25", for: staked.id, now: now)
        let later = now.addingTimeInterval(60)
        challenges.claim(rewardKey: "percent.25", for: staked.id, now: later)
        #expect(challenges.rewards(for: staked.id).first?.claimedAt == now)
        challenges.markStakePaid(staked.id, now: now)
        challenges.markStakePaid(staked.id, now: later)
        let reloaded = store(url)
        #expect(reloaded.stakePaidAt[staked.id] == now)
        #expect(reloaded.rewards(for: staked.id).first?.claimedAt == now)
    }

    @Test func everyMutationReplansReminders() throws {
        let challenges = store(tempFile())
        var planned: [[PlannedNotification]] = []
        challenges.onRemindersPlanned = { planned.append($0) }
        let morning = F.at(2026, 10, 14, hour: 9)
        try challenges.create(swings, now: morning)
        #expect(planned.last?.map(\.id) == ["challenge.\(swings.id.uuidString).nudge"])
        try challenges.add(value: 2_000, day: F.start, to: swings.id, now: morning)
        #expect(planned.last?.isEmpty == true)
        challenges.endEarly(swings.id, now: morning)
        #expect(planned.count == 3)
        #expect(challenges.progress(for: swings.id)?.status.isFinal == true)
    }
}
