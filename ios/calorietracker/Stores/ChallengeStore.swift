import Foundation
import Observation

/// A reward that has unlocked. Unlocks are permanent.
nonisolated struct ChallengeRewardRecord: Codable, Hashable, Sendable {
    var challengeID: UUID
    var rewardKey: String
    var title: String
    var unlockedAt: Date
    var claimedAt: Date?
}

/// What is written to `challenges.v1.json`. Automatic (Health, water, food)
/// values are never part of it.
nonisolated struct ChallengeArchive: Codable, Sendable {
    var version = 1
    var challenges: [Challenge] = []
    var entries: [ChallengeEntry] = []
    /// Keyed by challenge UUID string. Last write wins, so NO replaces YES.
    var checkIns: [String: [ChallengeDay: Bool]] = [:]
    var rewards: [ChallengeRewardRecord] = []
    /// Keyed by challenge UUID string.
    var stakePaidAt: [String: Date] = [:]
}

nonisolated enum ChallengeStoreError: Error, Hashable, Sendable {
    case invalidChallenge
    case unknownChallenge
    case outsideWindow
    case invalidValue
    case notCheckIn
    case notManual
}

/// Owns challenges, manual entries, check-ins and the reward log.
/// `reconcile(now:)` is the single evaluation path: every mutation and every
/// provider refresh ends in it.
@Observable
final class ChallengeStore {
    private(set) var challenges: [Challenge] = []
    private(set) var entries: [ChallengeEntry] = []
    private(set) var checkIns: [UUID: [ChallengeDay: Bool]] = [:]
    private(set) var rewardLog: [ChallengeRewardRecord] = []
    private(set) var stakePaidAt: [UUID: Date] = [:]
    /// Automatic metric values by challenge. In memory only.
    private(set) var autoValues: [UUID: [ChallengeDay: Double]] = [:]
    private(set) var autoAvailability: [UUID: ChallengeAvailability] = [:]
    private(set) var progressByID: [UUID: ChallengeProgress] = [:]
    /// Unlocks not yet shown to the user, oldest first.
    private(set) var pendingUnlocks: [RewardUnlock] = []
    private(set) var lastSaveError: String?
    private(set) var lastPlannedNotifications: [PlannedNotification] = []
    /// The `now` of the latest reconcile, so screens label days from the same clock.
    private(set) var evaluatedAt: Date?

    /// Called with today's planned reminders after every reconcile.
    @ObservationIgnored var onRemindersPlanned: (([PlannedNotification]) -> Void)?

    let fileURL: URL
    private let fixedCalendar: Calendar?

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("challenges.v1.json")
    }

    /// `calendar` is for tests; production buckets days in `Calendar.current` at evaluation time.
    init(fileURL: URL = ChallengeStore.defaultFileURL, calendar: Calendar? = nil) {
        self.fileURL = fileURL
        self.fixedCalendar = calendar
        load()
    }

    var calendar: Calendar { fixedCalendar ?? .current }

    func challenge(id: UUID) -> Challenge? {
        challenges.first { $0.id == id }
    }

    func progress(for id: UUID) -> ChallengeProgress? {
        progressByID[id]
    }

    func entries(for id: UUID) -> [ChallengeEntry] {
        entries.filter { $0.challengeID == id }
    }

    func rewards(for id: UUID) -> [ChallengeRewardRecord] {
        rewardLog.filter { $0.challengeID == id }
    }

    /// Challenges still running or not started, newest first.
    var activeChallenges: [Challenge] {
        challenges
            .filter { progressByID[$0.id]?.status.isFinal != true && $0.endedEarlyAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Mutations

    func create(_ challenge: Challenge, now: Date = Date()) throws {
        let title = challenge.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, ChallengeRules.isValid(challenge), self.challenge(id: challenge.id) == nil else {
            throw ChallengeStoreError.invalidChallenge
        }
        var stored = challenge
        stored.title = title
        challenges.append(stored)
        save()
        reconcile(now: now)
    }

    /// Adds a hand-logged amount to a `.custom` challenge. Same-day amounts add up.
    @discardableResult
    func add(value: Double, day: ChallengeDay, note: String? = nil, to challengeID: UUID, now: Date = Date()) throws -> ChallengeEntry {
        guard let challenge = challenge(id: challengeID) else { throw ChallengeStoreError.unknownChallenge }
        guard !challenge.metric.isAutomatic else { throw ChallengeStoreError.notManual }
        if case .dailyHabit(.checkIn) = challenge.kind { throw ChallengeStoreError.notManual }
        guard value.isFinite, value > 0, value <= ChallengeRules.maxTarget else { throw ChallengeStoreError.invalidValue }
        try requireLoggable(day, in: challenge, now: now)
        let entry = ChallengeEntry(id: UUID(), challengeID: challengeID, day: day, value: value, note: note, createdAt: now)
        entries.append(entry)
        save()
        reconcile(now: now)
        return entry
    }

    /// Records YES or NO for a check-in habit. The latest answer replaces the earlier one.
    func setCheckIn(_ value: Bool, day: ChallengeDay, for challengeID: UUID, now: Date = Date()) throws {
        guard let challenge = challenge(id: challengeID) else { throw ChallengeStoreError.unknownChallenge }
        guard case .dailyHabit(.checkIn) = challenge.kind else { throw ChallengeStoreError.notCheckIn }
        try requireLoggable(day, in: challenge, now: now)
        checkIns[challengeID, default: [:]][day] = value
        save()
        reconcile(now: now)
    }

    func undo(entryID: UUID, now: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries.remove(at: index)
        save()
        reconcile(now: now)
    }

    func endEarly(_ challengeID: UUID, now: Date = Date()) {
        guard let index = challenges.firstIndex(where: { $0.id == challengeID }),
              challenges[index].endedEarlyAt == nil else { return }
        challenges[index].endedEarlyAt = now
        save()
        reconcile(now: now)
    }

    func updateReminder(_ reminder: ChallengeReminder, for challengeID: UUID, now: Date = Date()) {
        guard let index = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        challenges[index].reminder = reminder
        save()
        reconcile(now: now)
    }

    func claim(rewardKey: String, for challengeID: UUID, now: Date = Date()) {
        guard let index = rewardLog.firstIndex(where: { $0.challengeID == challengeID && $0.rewardKey == rewardKey }),
              rewardLog[index].claimedAt == nil else { return }
        rewardLog[index].claimedAt = now
        save()
        reconcile(now: now)
    }

    func markStakePaid(_ challengeID: UUID, now: Date = Date()) {
        guard challenge(id: challengeID)?.stake != nil, stakePaidAt[challengeID] == nil else { return }
        stakePaidAt[challengeID] = now
        save()
        reconcile(now: now)
    }

    /// Provider refresh for an automatic metric. Values stay in memory.
    func setAutoValues(
        _ values: [ChallengeDay: Double],
        availability: ChallengeAvailability,
        for challengeID: UUID,
        now: Date = Date()
    ) {
        autoValues[challengeID] = values
        autoAvailability[challengeID] = availability
        reconcile(now: now)
    }

    /// Removes a pending unlock once the reward screen has shown it.
    func acknowledge(_ unlock: RewardUnlock) {
        guard let index = pendingUnlocks.firstIndex(of: unlock) else { return }
        pendingUnlocks.remove(at: index)
    }

    // MARK: - Reconcile

    /// Recomputes every challenge, persists new unlocks once, queues them for
    /// display and returns today's planned reminders.
    @discardableResult
    func reconcile(now: Date = Date()) -> [PlannedNotification] {
        let calendar = self.calendar
        evaluatedAt = now
        var unlocked: [RewardUnlock] = []
        var items: [(challenge: Challenge, progress: ChallengeProgress)] = []
        for challenge in challenges {
            let progress = ChallengeEngine.progress(
                challenge,
                daily: dailyValues(for: challenge),
                availability: availability(for: challenge),
                now: now,
                calendar: calendar
            )
            progressByID[challenge.id] = progress
            items.append((challenge, progress))
            let already = Set(rewardLog.lazy.filter { $0.challengeID == challenge.id }.map(\.rewardKey))
            unlocked += ChallengeRewardEvaluator.newUnlocks(
                challengeID: challenge.id,
                rewards: challenge.rewards,
                progress: progress,
                alreadyUnlocked: already
            )
        }
        if !unlocked.isEmpty {
            rewardLog += unlocked.map {
                ChallengeRewardRecord(challengeID: $0.challengeID, rewardKey: $0.rewardKey, title: $0.title, unlockedAt: now)
            }
            pendingUnlocks += unlocked
            save()
        }
        let planned = ChallengeReminderPlanner.plan(items, now: now, calendar: calendar)
        lastPlannedNotifications = planned
        onRemindersPlanned?(planned)
        return planned
    }

    /// The per-day values the engine scores for one challenge.
    func dailyValues(for challenge: Challenge) -> [ChallengeDay: Double] {
        if case .dailyHabit(.checkIn) = challenge.kind {
            return (checkIns[challenge.id] ?? [:]).mapValues { $0 ? 1 : 0 }
        }
        if challenge.metric.isAutomatic {
            return autoValues[challenge.id] ?? [:]
        }
        var sums: [ChallengeDay: Double] = [:]
        for entry in entries where entry.challengeID == challenge.id {
            sums[entry.day, default: 0] += entry.value
        }
        return sums
    }

    private func availability(for challenge: Challenge) -> ChallengeAvailability {
        guard challenge.metric.isAutomatic, !challenge.isCheckIn else { return .available }
        // Never score an automatic metric before its first successful read.
        return autoAvailability[challenge.id] ?? .unavailable
    }

    private func requireLoggable(_ day: ChallengeDay, in challenge: Challenge, now: Date) throws {
        let today = ChallengeDay(now, calendar: calendar)
        var lastDay = challenge.endDay
        if let endedAt = challenge.endedEarlyAt {
            lastDay = min(lastDay, ChallengeDay(endedAt, calendar: calendar))
        }
        guard day >= challenge.startDay, day <= lastDay, day <= today else {
            throw ChallengeStoreError.outsideWindow
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let archive = try JSONDecoder.challenges.decode(ChallengeArchive.self, from: data)
            challenges = archive.challenges
            entries = archive.entries
            rewardLog = archive.rewards
            var checkIns: [UUID: [ChallengeDay: Bool]] = [:]
            for (key, days) in archive.checkIns {
                if let id = UUID(uuidString: key) { checkIns[id] = days }
            }
            self.checkIns = checkIns
            var paid: [UUID: Date] = [:]
            for (key, date) in archive.stakePaidAt {
                if let id = UUID(uuidString: key) { paid[id] = date }
            }
            stakePaidAt = paid
        } catch {
            preserveCorruptFile(data)
        }
    }

    /// Keeps an unreadable file as challenges.corrupt-<timestamp>.json and starts empty.
    private func preserveCorruptFile(_ data: Data) {
        let stamp = Int(Date().timeIntervalSince1970)
        let copy = fileURL.deletingLastPathComponent().appendingPathComponent("challenges.corrupt-\(stamp).json")
        do {
            try data.write(to: copy, options: .atomic)
            Self.excludeFromBackup(copy)
        } catch {
            lastSaveError = "Couldn't keep the unreadable challenges file: \(error.localizedDescription)"
        }
    }

    private func save() {
        var archive = ChallengeArchive()
        archive.challenges = challenges
        archive.entries = entries
        archive.rewards = rewardLog
        archive.checkIns = Dictionary(uniqueKeysWithValues: checkIns.map { ($0.key.uuidString, $0.value) })
        archive.stakePaidAt = Dictionary(uniqueKeysWithValues: stakePaidAt.map { ($0.key.uuidString, $0.value) })
        do {
            let data = try JSONEncoder.challenges.encode(archive)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            Self.excludeFromBackup(fileURL)
            lastSaveError = nil
        } catch {
            // Keep the in-memory state; the next successful save writes it.
            lastSaveError = error.localizedDescription
        }
    }

    /// Reward records derive from Health data, so the file stays out of device backups.
    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}

private extension JSONEncoder {
    nonisolated static var challenges: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var challenges: JSONDecoder { JSONDecoder() }
}
