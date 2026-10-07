//
//  WorkoutLogStore.swift
//  calorietracker
//
//  The workout log: every JL workout the user saved, corrected or deleted,
//  kept on this phone only. History, last performance (and so the progression
//  rule), next-in-cycle, Home and Progress all read it. Nothing here talks to
//  a network.
//

import Foundation

@Observable
@MainActor
final class WorkoutLogStore {
    /// Version of the saved file.
    static let fileVersion = 1

    /// Every record, deleted ones included, newest session first.
    private(set) var records: [StoredWorkout] = []
    /// Set when the last change couldn't be saved; that change was not made.
    private(set) var persistError: String?
    /// Plain-text note when the saved log couldn't be read in full.
    private(set) var storageNote: String?
    /// Why the saved log is shown but never overwritten (a newer app's log,
    /// unreadable bytes that couldn't be kept aside, or a file that couldn't be
    /// opened); nil while it can be saved.
    @ObservationIgnored private var readOnly: WorkoutLogError?
    /// Records that couldn't be read and are no longer in the saved log.
    @ObservationIgnored private var omitted = 0
    /// ISO-8601 of the first import that added workouts.
    private(set) var importedAt: String?

    private let file: WorkoutLogFile

    init(persistence: WorkoutLogPersistence = .applicationSupport) {
        file = WorkoutLogFile(persistence: persistence)
        load()
    }

    /// Explicit nonisolated deinit: the synthesized main-actor-isolated deinit
    /// double-frees a TaskLocal scope on iOS <= 26.2 (swiftlang/swift#88036)
    /// when the store is released inside a task-local context.
    nonisolated deinit {}

    // MARK: Reads

    /// Workouts not deleted, newest session first.
    var workouts: [RemoteWorkout] {
        records.filter { !$0.isDeleted }.map(\.workout)
    }

    /// Workouts not deleted, with their sets, newest session first.
    var details: [WorkoutDetailResponse] {
        records.filter { !$0.isDeleted }.map(\.detail)
    }

    func detail(id: String) -> WorkoutDetailResponse? {
        guard let record = records.first(where: { $0.workout.id == id }), !record.isDeleted else { return nil }
        return record.detail
    }

    func record(id: String) -> StoredWorkout? {
        records.first { $0.workout.id == id }
    }

    /// True once a file import added workouts. From then on the log holds the
    /// bridge-era history too, so next-in-cycle reads only the log.
    var hasImportedHistory: Bool { importedAt != nil }

    // MARK: Changes

    /// Saves a finished session under `id` (the draft's record id). Saving the
    /// same id again replaces that workout instead of adding a second one, so a
    /// save repeated after a crash can't duplicate it. A workout deleted since
    /// stays deleted and the save throws, so the draft is kept, not lost silently.
    /// Throws, changing nothing, when the log can't be written.
    func save(_ payload: WorkoutPayload, id: String) throws {
        reloadIfNotOpened()
        let record = StoredWorkout(id: id, payload: payload)
        var next = records
        if let index = next.firstIndex(where: { $0.workout.id == id }) {
            if next[index].isDeleted { throw WorkoutLogError.deletedSinceSaved }
            next[index].workout = record.workout
            next[index].sets = record.sets
        } else {
            next.append(record)
        }
        try commit(next)
    }

    /// Replaces a workout's title, conditioning, notes and sets in place. The
    /// version it replaces is kept in `revisions`. Throws, changing nothing,
    /// when the workout is gone or the log can't be written.
    func correct(id: String, with payload: WorkoutPayload, now: Date = Date()) throws {
        reloadIfNotOpened()
        guard let index = records.firstIndex(where: { $0.workout.id == id && !$0.isDeleted }) else {
            throw WorkoutLogError.notFound
        }
        let old = records[index]
        let replaced = StoredWorkout(id: id, payload: payload)
        var next = records
        next[index].workout = RemoteWorkout(
            id: id,
            kind: old.workout.kind,
            programVersion: old.workout.programVersion,
            programDay: old.workout.programDay,
            title: replaced.workout.title,
            units: old.workout.units,
            sessionDate: old.workout.sessionDate,
            conditioning: replaced.workout.conditioning,
            notes: replaced.workout.notes,
            // The hash described the replaced content; that version keeps it.
            contentHash: nil,
            synthetic: old.workout.synthetic,
            recordedAt: old.workout.recordedAt,
            sourceFingerprint: old.workout.sourceFingerprint
        )
        next[index].sets = replaced.sets
        next[index].revisions.append(WorkoutRevision(
            replacedAt: Self.timestamp(now),
            workout: old.workout,
            sets: old.sets
        ))
        try commit(next)
    }

    /// Deletes a workout. A record without its sets stays behind, keeping every
    /// id and content hash it carried, so a re-import of any version of it adds
    /// nothing. Throws, changing nothing, when the workout is gone or the log
    /// can't be written.
    func delete(id: String, now: Date = Date()) throws {
        reloadIfNotOpened()
        guard let index = records.firstIndex(where: { $0.workout.id == id && !$0.isDeleted }) else {
            throw WorkoutLogError.notFound
        }
        var next = records
        next[index].delete(at: Self.timestamp(now))
        try commit(next)
    }

    // MARK: Import

    /// What importing `file` would add, without changing anything.
    func importSummary(of file: WorkoutImportFile) -> WorkoutImportSummary {
        let (new, duplicates) = newWorkouts(in: file)
        return WorkoutImportSummary(added: new.count, duplicates: duplicates, skipped: file.skipped)
    }

    /// Adds the file's workouts that aren't on this phone yet; nothing already
    /// here changes, so importing the same file again adds nothing. The saved
    /// log is copied aside first (`pre-import`). Throws, changing nothing,
    /// when that copy or the save fails or the log is read-only.
    @discardableResult
    func importFile(_ file: WorkoutImportFile, now: Date = Date()) throws -> WorkoutImportSummary {
        reloadIfNotOpened()
        if let readOnly { throw readOnly }
        let (new, duplicates) = newWorkouts(in: file)
        let summary = WorkoutImportSummary(added: new.count, duplicates: duplicates, skipped: file.skipped)
        guard !new.isEmpty else { return summary }
        switch self.file.read() {
        case .data(let saved):
            guard self.file.keepBeforeImport(saved, now: now) else { throw WorkoutLogError.copyBeforeImport }
        case .missing:
            break
        case .failed(let error):
            throw error
        }
        try commit(records + new, importedAt: Self.timestamp(now))
        return summary
    }

    /// The file's workouts whose id and content hash aren't already in the log
    /// (deleted ones included) or earlier in the file, and how many were.
    private func newWorkouts(in file: WorkoutImportFile) -> (new: [StoredWorkout], duplicates: Int) {
        var ids = Set(records.flatMap(\.ids))
        var hashes = Set(records.flatMap(\.contentHashes))
        var new: [StoredWorkout] = []
        var duplicates = 0
        for detail in file.workouts {
            let hash = detail.workout.contentHash
            let knownHash = hash.map { hashes.contains($0) } ?? false
            if ids.contains(detail.workout.id) || knownHash {
                duplicates += 1
                continue
            }
            ids.insert(detail.workout.id)
            if let hash { hashes.insert(hash) }
            new.append(StoredWorkout(workout: detail.workout, sets: detail.sets))
        }
        return (new, duplicates)
    }

    // MARK: Backup and reset

    /// The log for the iCloud backup: the saved file's format. Blocked while the
    /// log is read-only, so workouts this app can't read are never backed up over.
    func backupData() -> CloudBackupPart {
        if let readOnly {
            let reason = switch readOnly {
            case .newerVersion: "Workouts were saved by a newer version of the app"
            case .notOpened: "Workouts couldn't be read on this phone"
            default: "Workouts couldn't be read in full on this phone"
            }
            return .blocked(reason: reason)
        }
        guard let data = snapshot(of: records, importedAt: importedAt).encoded() else {
            return .blocked(reason: "Workouts couldn't be packed for the backup")
        }
        return .include(data)
    }

    /// iCloud restore replaces every workout. Strict: the whole log must read,
    /// and it is saved before it is shown. Otherwise the phone's workouts are
    /// kept and the reason is returned.
    func restoreBackupData(_ data: Data) -> String? {
        guard WorkoutLogSnapshot.savedVersion(of: data) == Self.fileVersion,
              let restored = try? JSONDecoder().decode(WorkoutLogSnapshot.self, from: data),
              restored.skipped == 0 else {
            return "Workouts in this backup couldn't be read, so the ones on this phone were kept."
        }
        reloadIfNotOpened()
        switch readOnly {
        case .newerVersion?:
            return "Workouts can't be restored until the app is updated, so the ones on this phone were kept."
        case .notOpened?:
            return "Workouts weren't restored because the saved workout log couldn't be opened, so it was left as it is."
        case .some:
            return "Workouts weren't restored because the saved workout log couldn't be kept aside, so it was left as it is."
        case nil:
            break
        }
        let sorted = Self.sorted(restored.workouts)
        let replacement = WorkoutLogSnapshot(version: Self.fileVersion, workouts: sorted,
                                             omitted: restored.omitted, importedAt: restored.importedAt)
        if case .failure(let error)? = write(replacement) {
            return "Workouts weren't restored (\(error.localizedDescription)), so the ones on this phone were kept."
        }
        records = sorted
        omitted = restored.omitted
        importedAt = restored.importedAt
        persistError = nil
        storageNote = Self.omittedNote(omitted)
        return nil
    }

    /// Delete Everything: the saved log, every copy set aside next to it, and
    /// everything in memory.
    func deleteAll() {
        file.removeAll()
        records = []
        persistError = nil
        storageNote = nil
        omitted = 0
        importedAt = nil
        readOnly = nil
    }

    /// A saved log that couldn't be opened (the phone was locked at launch) is
    /// read again. Every change asks first; until it opens nothing is saved.
    func reloadIfNotOpened() {
        guard readOnly == .notOpened else { return }
        readOnly = nil
        storageNote = nil
        load()
    }

    // MARK: Private

    /// Saves `next` first; memory changes only once it is saved.
    private func commit(_ next: [StoredWorkout], importedAt: String? = nil) throws {
        if let readOnly {
            persistError = readOnly.localizedDescription
            throw readOnly
        }
        let sorted = Self.sorted(next)
        let imported = self.importedAt ?? importedAt
        switch write(snapshot(of: sorted, importedAt: imported)) {
        case .failure(let error)?:
            persistError = error.localizedDescription
            throw error
        case .success?, nil:
            records = sorted
            self.importedAt = imported
            persistError = nil
        }
    }

    /// Newest session first; on one day the later recording first.
    static func sorted(_ list: [StoredWorkout]) -> [StoredWorkout] {
        list.sorted { lhs, rhs in
            let left = String(lhs.workout.sessionDate.prefix(10))
            let right = String(rhs.workout.sessionDate.prefix(10))
            if left != right { return left > right }
            let leftRecorded = lhs.workout.recordedAt ?? ""
            let rightRecorded = rhs.workout.recordedAt ?? ""
            if leftRecorded != rightRecorded { return leftRecorded > rightRecorded }
            return lhs.workout.id < rhs.workout.id
        }
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: Persistence

    private func load() {
        let data: Data
        switch file.read() {
        case .missing:
            return
        case .failed:
            // The file is there but its bytes are unknown: an empty log saved now would replace them.
            readOnly = .notOpened
            storageNote = WorkoutLogError.notOpened.localizedDescription
            return
        case .data(let bytes):
            data = bytes
        }
        guard let version = WorkoutLogSnapshot.savedVersion(of: data) else {
            setAsideUnreadable(data)
            return
        }
        if version > Self.fileVersion {
            // Saved by a newer app: never overwrite it.
            readOnly = .newerVersion
            storageNote = "Workouts were saved by a newer version of the app, so they can't be shown here. Update the app to see them."
            return
        }
        guard let snapshot = try? JSONDecoder().decode(WorkoutLogSnapshot.self, from: data) else {
            setAsideUnreadable(data)
            return
        }
        records = Self.sorted(snapshot.workouts)
        importedAt = snapshot.importedAt
        // Records skipped now are dropped by the next save, so they join the count saved with it.
        omitted = snapshot.omitted + snapshot.skipped
        if let note = Self.omittedNote(omitted) {
            storageNote = note
        }
        if snapshot.skipped > 0, !file.keepUnreadable(data) {
            // The next save would drop the skipped records, and they are on disk nowhere else.
            readOnly = .unreadableNotKept
            storageNote = WorkoutLogError.unreadableNotKept.localizedDescription
        }
    }

    /// A log that can't be read is copied aside before a new one is started.
    /// When the copy fails the log turns read-only, so a save can never write
    /// over the only copy of those workouts.
    private func setAsideUnreadable(_ data: Data) {
        if file.keepUnreadable(data) {
            storageNote = "The saved workout log couldn't be read. It was kept aside on this phone and a new log was started."
        } else {
            readOnly = .unreadableNotKept
            storageNote = WorkoutLogError.unreadableNotKept.localizedDescription
        }
    }

    private static func omittedNote(_ omitted: Int) -> String? {
        guard omitted > 0 else { return nil }
        return omitted == 1
            ? "1 saved workout couldn't be read, so it isn't listed."
            : "\(omitted) saved workouts couldn't be read, so they aren't listed."
    }

    private func snapshot(of list: [StoredWorkout], importedAt: String?) -> WorkoutLogSnapshot {
        WorkoutLogSnapshot(version: Self.fileVersion, workouts: list, omitted: omitted, importedAt: importedAt)
    }

    /// Writes a snapshot as the saved log. Nil when there is no file to write (in memory).
    private func write(_ snapshot: WorkoutLogSnapshot) -> Result<Void, Error>? {
        if file.isInMemory { return nil }
        guard let data = snapshot.encoded() else { return .failure(WorkoutLogError.encoding) }
        return file.write(data) ?? .failure(WorkoutLogError.noLocation)
    }
}

enum WorkoutLogError: LocalizedError, Equatable {
    case notFound
    case newerVersion
    case encoding
    case noLocation
    case copyBeforeImport
    case deletedSinceSaved
    case unreadableNotKept
    case notOpened

    var errorDescription: String? {
        switch self {
        case .notFound: "That workout isn't on this phone any more."
        case .newerVersion: "Workouts can't be saved until the app is updated."
        case .encoding: "The workout log couldn't be encoded."
        case .noLocation: "There's no place on this phone to save workouts."
        case .copyBeforeImport: "The workout log couldn't be copied before the import, so nothing was imported."
        case .deletedSinceSaved: "This workout was saved and then deleted in Workout History. Discard it to start fresh."
        case .unreadableNotKept: "The saved workout log couldn't be read in full or copied aside, so it was left as it is and workouts can't be saved. Close and reopen the app to try again."
        case .notOpened: "The saved workout log couldn't be opened, so workouts aren't shown and can't be saved yet. Unlock the phone and reopen the app to try again."
        }
    }
}

/// The saved file. One unreadable record never drops the rest.
struct WorkoutLogSnapshot: Codable {
    var version: Int
    var workouts: [StoredWorkout]
    /// Records left out of an earlier save because they couldn't be read.
    /// Saved only when above 0; absent reads as 0.
    var omitted: Int = 0
    /// ISO-8601 of the first import that added workouts; absent before one.
    var importedAt: String?
    /// Records that couldn't be read in this file (decode only).
    var skipped: Int = 0

    enum CodingKeys: String, CodingKey {
        case version, workouts, omitted
        case importedAt = "imported_at"
    }

    init(version: Int, workouts: [StoredWorkout], omitted: Int, importedAt: String?) {
        self.version = version
        self.workouts = workouts
        self.omitted = omitted
        self.importedAt = importedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let rows = try container.decode([WorkoutLossy<StoredWorkout>].self, forKey: .workouts)
        workouts = rows.compactMap(\.value)
        skipped = rows.count - workouts.count
        omitted = (try? container.decodeIfPresent(Int.self, forKey: .omitted)) ?? 0
        importedAt = try? container.decodeIfPresent(String.self, forKey: .importedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(workouts, forKey: .workouts)
        if omitted > 0 {
            try container.encode(omitted, forKey: .omitted)
        }
        try container.encodeIfPresent(importedAt, forKey: .importedAt)
    }

    /// Stable bytes: sorted keys, so the same log always encodes the same.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// The `version` of saved bytes, or nil when they aren't a log at all.
    static func savedVersion(of data: Data) -> Int? {
        struct Probe: Decodable { let version: Int }
        return (try? JSONDecoder().decode(Probe.self, from: data))?.version
    }
}

#if DEBUG
extension WorkoutLogStore {
    /// Visual QA seeds whole records into an in-memory log. Release builds
    /// keep only the persistence-based initializer.
    convenience init(visualQARecords: [StoredWorkout]) {
        self.init(persistence: .inMemory)
        records = Self.sorted(visualQARecords)
    }
}
#endif

extension WorkoutLogStore: CloudBackupWorkouts {}
