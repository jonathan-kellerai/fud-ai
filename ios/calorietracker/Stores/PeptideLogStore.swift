//
//  PeptideLogStore.swift
//  calorietracker
//
//  Peptides log: the doses, vials and schedules the user entered, saved on
//  this phone only. Logs what the user enters; it sets no doses and
//  recommends no protocol. Nothing here talks to a network.
//

import Foundation

@Observable
@MainActor
final class PeptideLogStore {
    /// Also read by `CloudBackupPolicy`, which leaves this key to the store.
    nonisolated static let defaultsKey = "peptide.log.v1"
    /// Version of the saved file. Version 1 was the bridge-era cache and queue;
    /// version 2 tagged every record with one of two profiles.
    static let fileVersion = 3

    private(set) var vials: [PeptideVial] = []
    private(set) var schedules: [PeptideUserSchedule] = []
    /// Every logged dose, oldest first.
    private(set) var entries: [PeptideLogEntry] = []
    /// Records an earlier build kept under a second profile. Saved, backed up
    /// and never shown in the log until the user keeps or deletes them.
    private(set) var heldAside = PeptideRecordSet()
    /// The user's syringe scale (Settings → Syringe scale). Nil: not recorded.
    /// Copied into each draw when it's saved; changing it never changes a saved draw.
    private(set) var syringeScale: PeptideSyringeScale?
    private(set) var persistError: String?
    /// Plain-text note when the saved log couldn't be read in full.
    private(set) var storageNote: String?
    /// Why the saved log is never overwritten; nil while it can be saved.
    @ObservationIgnored private var readOnly: PeptideLogReadOnly?
    /// Records that couldn't be read and are no longer in the saved log.
    /// Saved with it, so `storageNote` survives a relaunch.
    @ObservationIgnored private var omitted = 0

    private let file: PeptideLogFile

    init(persistence: PeptideLogPersistence = .appGroup) {
        self.file = PeptideLogFile(persistence: persistence, defaultsKey: Self.defaultsKey)
        load()
    }

    /// Explicit nonisolated deinit: the synthesized main-actor-isolated deinit
    /// double-frees a TaskLocal scope on iOS <= 26.2 (swiftlang/swift#88036)
    /// when the store is released inside a task-local context.
    nonisolated deinit {}

    // MARK: Derived

    func entry(id: String) -> PeptideLogEntry? {
        entries.first { $0.id == id }
    }

    /// Entries on one civil date, by time.
    func dayEntries(_ civil: String, includeVoided: Bool) -> [PeptideLogEntry] {
        entries.filter { $0.civilDate == civil && (includeVoided || !$0.voided) }
    }

    /// Active vials, plus finished ones when asked.
    func vialList(includeFinished: Bool = false) -> [PeptideVial] {
        vials.filter { includeFinished || $0.status == .active }
    }

    func vial(id: String?) -> PeptideVial? {
        guard let id else { return nil }
        return vials.first { $0.id == id }
    }

    func remaining(for vial: PeptideVial) -> PeptideMath.Remaining {
        PeptideMath.remaining(vial: vial, entries: entries)
    }

    /// Remaining as if `extra` (a dose being reviewed) were logged too.
    func remaining(for vial: PeptideVial, including extra: PeptideLogEntry) -> PeptideMath.Remaining {
        PeptideMath.remaining(vial: vial, entries: entries + [extra])
    }

    func lowStockVials() -> [PeptideVial] {
        vials.filter { $0.status == .active && remaining(for: $0).isLow }
    }

    /// Compounds logged before, newest first, one per compound key.
    func loggedCompounds() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for entry in entries.reversed() {
            let key = PeptideMath.compoundKey(entry.compound)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            names.append(entry.compound)
        }
        return names
    }

    /// Doses logged on `civil` that count, by time.
    func takenEntries(on civil: String) -> [PeptideLogEntry] {
        entries.filter { $0.countsAsTaken && $0.civilDate == civil }
    }

    /// What keeps the Home card visible: an active schedule or vial, or a dose today.
    func hasLocalActivity(today civil: String) -> Bool {
        if schedules.contains(where: \.active) { return true }
        if vials.contains(where: { $0.status == .active }) { return true }
        return !takenEntries(on: civil).isEmpty
    }

    // MARK: Logging

    /// Saves a draw from what the user typed. Returns its id, or nil when the
    /// draft is not valid or the log can't change (`persistError` says why).
    /// Saving the same id again replaces that entry.
    @discardableResult
    func log(_ draft: PeptideLogDraft, id: String? = nil, now: Date = Date()) -> String? {
        guard PeptideMath.validate(draft).isEmpty, canChange() else { return nil }
        let entryID = (id ?? UUID().uuidString).lowercased()
        let entry = entry(from: draft, id: entryID, now: now)
        entries.removeAll { $0.id == entryID }
        entries.append(entry)
        didChangeEntries()
        return entryID
    }

    /// The entry `draft` would save, with its snapshot: the syringe scale in
    /// force (this draw's own, else Settings) and the linked vial's
    /// concentration and confirmation, copied now and never re-read.
    func entry(from draft: PeptideLogDraft, id: String, now: Date = Date()) -> PeptideLogEntry {
        let datetime = PeptideMath.iso8601NewYork(draft.takenAt)
        let linked = vial(id: draft.vialID)
        return PeptideLogEntry(
            id: id,
            compound: draft.trimmedCompound,
            date: PeptideMath.parseISO8601(datetime),
            datetimeRaw: datetime,
            route: draft.trimmedSite.isEmpty ? nil : draft.trimmedSite,
            notes: draft.trimmedNotes.isEmpty ? nil : draft.trimmedNotes,
            vialID: linked?.id,
            drawnVolume: draft.draw,
            drawnUnit: draft.draw == nil ? nil : draft.drawUnit,
            createdAt: PeptideMath.iso8601NewYork(now),
            syringeScaleAtSave: draft.scaleOverride ?? syringeScale,
            vialConcentrationAtSave: linked.flatMap(PeptideMath.milligramsPerML),
            concentrationConfirmedAtSave: linked?.concentrationConfirmed ?? false,
            vialIDAtSave: linked?.id
        )
    }

    /// Settings → Syringe scale. Saved drafts keep the scale they were saved with.
    func setSyringeScale(_ scale: PeptideSyringeScale?) {
        guard canChange(), scale != syringeScale else { return }
        syringeScale = scale
        didChange()
    }

    /// Changes a logged dose in place. A reason is required and every changed
    /// field goes into the entry's correction trail. Returns an error
    /// message, or nil when saved.
    @discardableResult
    func correct(_ entry: PeptideLogEntry, reason: String, changes: PeptideCorrectionChanges, now: Date = Date()) -> String? {
        guard canChange() else { return persistError }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return "This entry is no longer here." }
        if entries[index].voided { return "This entry is voided." }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A reason is required." }
        guard !changes.isEmpty else { return "Nothing changed." }
        entries[index] = entries[index].corrected(changes, reason: trimmed, at: PeptideMath.iso8601NewYork(now))
        didChangeEntries()
        return nil
    }

    /// "Delete" means void with a reason: the entry stays in history, struck through.
    @discardableResult
    func void(_ entry: PeptideLogEntry, reason: String, now: Date = Date()) -> String? {
        guard canChange() else { return persistError }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return "This entry is no longer here." }
        if entries[index].voided { return "This entry is already voided." }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A reason is required." }
        entries[index] = entries[index].voiding(reason: trimmed, at: PeptideMath.iso8601NewYork(now))
        didChangeEntries()
        return nil
    }

    // MARK: Vials and schedules

    func saveVial(_ vial: PeptideVial) {
        guard canChange() else { return }
        if let index = vials.firstIndex(where: { $0.id == vial.id }) {
            vials[index] = vial
        } else {
            vials.append(vial)
        }
        didChange()
    }

    func finishVial(id: String) {
        guard canChange(), let index = vials.firstIndex(where: { $0.id == id }) else { return }
        vials[index].status = .finished
        didChange()
    }

    func deleteVial(id: String) {
        guard canChange() else { return }
        vials.removeAll { $0.id == id }
        didChange()
    }

    func saveSchedule(_ schedule: PeptideUserSchedule) {
        guard canChange() else { return }
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        didChange()
    }

    func setScheduleActive(id: String, active: Bool) {
        guard canChange(), let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].active = active
        didChange()
    }

    func deleteSchedule(id: String) {
        guard canChange() else { return }
        schedules.removeAll { $0.id == id }
        didChange()
    }

    // MARK: Second profile

    /// Records an earlier build kept under a second profile, still waiting
    /// for the user's choice.
    var heldAsideCount: Int { heldAside.count }

    /// "Keep them in my log": the held-aside records join this log (a record
    /// whose id is already here is left as it is) and the choice is saved.
    func keepHeldAside() {
        guard canChange(), !heldAside.isEmpty else { return }
        let merged = PeptideRecordSet(entries: entries, vials: vials, schedules: schedules).adding(heldAside)
        entries = Self.sorted(merged.entries)
        vials = merged.vials
        schedules = merged.schedules
        heldAside = PeptideRecordSet()
        didChange()
    }

    /// "Delete them": the held-aside records are removed and the choice is saved.
    func deleteHeldAside() {
        guard canChange(), !heldAside.isEmpty else { return }
        heldAside = PeptideRecordSet()
        didChange()
    }

    // MARK: Recon Bench

    /// Recon Bench's save (build 67): the mixes the user typed there join
    /// Vials unconfirmed, the second profile's held aside (see
    /// `ReconBenchMigration`). Its untouched bytes are kept next to the log
    /// first, so Delete Everything removes them with it. True once they're
    /// saved here, so the old save can go. False, with nothing changed, when
    /// the bytes have no mixes to move or can't be kept or saved.
    func adoptReconBench(_ data: Data, now: Date = Date()) -> Bool {
        guard let found = ReconBenchMigration.vials(from: data, now: now),
              !found.own.isEmpty || !found.heldAside.isEmpty else { return false }
        guard !file.isInMemory, canChange(), readOnly == nil, file.keepBeforeUpgrade(data, label: "recon-bench-pre-v3", now: now) else {
            return false
        }
        let new = newRecords(in: found)
        vials += new.own.vials
        heldAside = heldAside.adding(new.heldAside)
        persist()
        return persistError == nil
    }

    // MARK: Archive

    /// Everything on this phone in the archive format, held-aside records included.
    func archive(exportedAt: Date?) -> PeptideArchive {
        PeptideArchive(
            exportedAt: exportedAt.map(PeptideMath.iso8601NewYork),
            vials: vials,
            schedules: schedules,
            entries: entries,
            heldAside: heldAside,
            syringeScale: syringeScale
        )
    }

    /// What importing `archive` would add. A record whose id is already here
    /// (in the log or held aside, or earlier in the file) is left alone, so
    /// importing twice adds nothing. Records an older file tagged with the
    /// second profile are held aside, not added to the log.
    func importSummary(of archive: PeptideArchive) -> PeptideImportSummary {
        let file = archive.records(now: Date())
        let new = newRecords(in: file)
        return PeptideImportSummary(
            newVials: new.own.vials.count,
            newSchedules: new.own.schedules.count,
            newEntries: new.own.entries.count,
            heldAside: new.heldAside.count,
            alreadyHere: file.own.count + file.heldAside.count - new.own.count - new.heldAside.count,
            skipped: archive.skipped
        )
    }

    /// Adds what `archive` has that this phone doesn't: the user's own records
    /// to this log, second-profile records to those held aside for the user's
    /// choice. Nothing already here is changed. Adds nothing (an empty
    /// summary) when the log can't change; `persistError` says why.
    @discardableResult
    func importArchive(_ archive: PeptideArchive, now: Date = Date()) -> PeptideImportSummary {
        guard canChange() else { return PeptideImportSummary() }
        let summary = importSummary(of: archive)
        guard summary.total > 0 else { return summary }
        let new = newRecords(in: archive.records(now: now))
        entries += new.own.entries
        vials += new.own.vials
        schedules += new.own.schedules
        heldAside = heldAside.adding(new.heldAside)
        didChangeEntries()
        return summary
    }

    /// `file`'s records whose id isn't on this phone, in the log or held aside.
    private func newRecords(in file: PeptideRecordsByProfile) -> PeptideRecordsByProfile {
        let here = PeptideRecordSet(entries: entries, vials: vials, schedules: schedules).adding(heldAside)
        let own = here.newRecords(in: file.own)
        return PeptideRecordsByProfile(own: own, heldAside: here.adding(own).newRecords(in: file.heldAside))
    }

    /// Replaces everything with `archive` (iCloud restore). Records the
    /// backup holds aside stay held aside. Saved first: when it can't be
    /// saved, nothing in memory or saved changes and the reason is returned.
    func replaceAll(with archive: PeptideArchive, now: Date = Date()) -> String? {
        var replacement = archive.records(now: now)
        replacement.own.entries = Self.sorted(replacement.own.entries)
        if !canChange() || readOnly != nil { return persistError ?? "Peptides can't be saved on this phone right now." }
        if !file.isInMemory, case .failure(let error)? = save(replacement, scale: archive.syringeScale, fallbackOnFailure: false) {
            return error.localizedDescription
        }
        vials = replacement.own.vials
        schedules = replacement.own.schedules
        entries = replacement.own.entries
        heldAside = replacement.heldAside
        syringeScale = archive.syringeScale
        persistError = nil
        return nil
    }

    /// Delete Everything: the saved log, its set-aside copies, the
    /// UserDefaults fallback and everything in memory.
    func deleteAll() {
        file.removeAll()
        entries = []
        vials = []
        schedules = []
        heldAside = PeptideRecordSet()
        syringeScale = nil
        persistError = nil
        storageNote = nil
        omitted = 0
        readOnly = nil
    }

    /// Why changes are refused now, with nothing changed (the saved log isn't
    /// open yet, or couldn't be copied aside). Nil while changes are made. Views read it after a change.
    var changeRefusal: String? { readOnly?.refusal }

    /// A saved log that couldn't be opened (the phone was locked at launch) is
    /// read again. Every change asks first; until it opens nothing changes.
    func reloadIfNotOpened() {
        guard readOnly == .notOpened else { return }
        readOnly = nil
        storageNote = nil
        persistError = nil
        load()
    }

    // MARK: Private

    /// Every change asks first. False, with nothing changed and `persistError`
    /// saying why, while the saved log on disk isn't what memory holds.
    private func canChange() -> Bool {
        reloadIfNotOpened()
        guard let refusal = readOnly?.refusal else { return true }
        persistError = refusal
        return false
    }

    private func didChangeEntries() {
        entries = Self.sorted(entries)
        didChange()
    }

    private func didChange() {
        persist()
    }

    private static func sorted(_ list: [PeptideLogEntry]) -> [PeptideLogEntry] {
        list.sorted { lhs, rhs in
            let left = lhs.date ?? .distantPast
            let right = rhs.date ?? .distantPast
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
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
            storageNote = "The saved peptide log couldn't be opened, so peptides aren't shown yet. Unlock the phone and reopen the app to try again."
            return
        case .data(let bytes):
            data = bytes
        }
        guard let version = PeptideLogSnapshot.savedVersion(of: data) else {
            setAsideUnreadable(data)
            return
        }
        if version == Self.fileVersion || version == 2 {
            guard let snapshot = try? JSONDecoder().decode(PeptideLogSnapshot.self, from: data) else {
                setAsideUnreadable(data)
                return
            }
            // Records skipped now are dropped by the next save, so they join the count saved with it.
            apply(snapshot.records, omitted: snapshot.omitted + snapshot.skipped)
            syringeScale = snapshot.syringeScale
            if version == 2 {
                // Version 2 tagged records with a profile: keep its bytes, then save version 3.
                // That copy holds any skipped records too; if it fails, nothing is saved.
                keepAsideThenSave(data, label: "pre-v3")
            } else if snapshot.skipped > 0, !file.keepUnreadable(data) {
                // The next save would drop the skipped records, and they are on disk nowhere else.
                readOnly = .unreadableNotKept
                storageNote = Self.unreadableNotKeptNote
            }
        } else if version == 1 {
            upgrade(data)
        } else {
            // Saved by a newer app: never overwrite it.
            readOnly = .newerVersion
            storageNote = "Peptides were saved by a newer version of the app, so they can't be shown here. Update the app to see them."
            persistError = "Changes to peptides aren't saved until the app is updated."
        }
    }

    /// Version 1 → on-device records. The untouched version-1 bytes are set
    /// aside first; if that fails, the records are shown but nothing is saved.
    private func upgrade(_ data: Data) {
        guard let migrated = PeptideLegacyLog.migrate(data) else {
            setAsideUnreadable(data)
            return
        }
        apply(migrated.records, omitted: migrated.skipped)
        keepAsideThenSave(data, label: "pre-local")
    }

    /// Bytes that can't be read are copied aside before a new log is started.
    /// When the copy fails the log turns read-only, so a save can never write
    /// over the only copy of those records.
    private func setAsideUnreadable(_ data: Data) {
        guard !file.keepUnreadable(data) else { return }
        readOnly = .unreadableNotKept
        storageNote = Self.unreadableNotKeptNote
    }

    private static let unreadableNotKeptNote = "The saved peptide log couldn't be read in full or copied aside, so it was left as it is. Close and reopen the app to try again."

    /// Writes the untouched bytes of an older save next to it, then saves in
    /// the current version. If the copy can't be made, nothing is saved.
    private func keepAsideThenSave(_ data: Data, label: String) {
        guard file.keepBeforeUpgrade(data, label: label) else {
            readOnly = .upgradeNotKept
            persistError = "Peptides from the earlier version couldn't be backed up on this phone, so changes aren't saved yet."
            return
        }
        persist()
    }

    private func apply(_ records: PeptideRecordsByProfile, omitted: Int) {
        entries = Self.sorted(records.own.entries)
        vials = records.own.vials
        schedules = records.own.schedules
        heldAside = records.heldAside
        self.omitted = omitted
        if omitted > 0 {
            let records = omitted == 1 ? "1 saved peptide record" : "\(omitted) saved peptide records"
            storageNote = "\(records) couldn't be read, so \(omitted == 1 ? "it isn't" : "they aren't") listed. Remaining in a vial may be off."
        }
    }

    private func persist() {
        if file.isInMemory || readOnly != nil { return }
        let records = PeptideRecordsByProfile(
            own: PeptideRecordSet(entries: entries, vials: vials, schedules: schedules),
            heldAside: heldAside
        )
        switch save(records, scale: syringeScale) {
        case .success?:
            persistError = nil
        case .failure(let error)?:
            persistError = error.localizedDescription
        case nil:
            break
        }
    }

    /// Writes these records as the saved log. Nil when there is no file to write.
    private func save(
        _ records: PeptideRecordsByProfile,
        scale: PeptideSyringeScale?,
        fallbackOnFailure: Bool = true
    ) -> Result<Void, Error>? {
        var snapshot = PeptideLogSnapshot(
            version: Self.fileVersion,
            entries: records.own.entries,
            vials: records.own.vials,
            schedules: records.own.schedules,
            heldAside: records.heldAside,
            omitted: omitted
        )
        snapshot.syringeScale = scale
        guard let data = try? JSONEncoder().encode(snapshot) else { return .failure(SaveError.encoding) }
        return file.write(data, fallbackOnFailure: fallbackOnFailure)
    }

    private enum SaveError: LocalizedError {
        case encoding

        var errorDescription: String? { "Peptide log couldn't be encoded." }
    }
}

/// Why the saved peptide log is never overwritten.
enum PeptideLogReadOnly: Equatable {
    /// Saved by a newer app. Changes are shown but not saved.
    case newerVersion
    /// An older save that couldn't be set aside before upgrading. Changes are shown but not saved.
    case upgradeNotKept
    /// The file is there but couldn't be opened (locked before first unlock).
    /// Changes are refused: memory holds none of it.
    case notOpened
    /// Bytes that couldn't be read (the whole file, or records skipped while
    /// reading it) and couldn't be copied aside. Changes are refused: a save
    /// would drop them.
    case unreadableNotKept

    /// Why a change is refused, nothing changed; nil when changes are shown but not saved.
    var refusal: String? {
        switch self {
        case .newerVersion, .upgradeNotKept: nil
        case .notOpened: "Peptides can't be changed until the saved log opens."
        case .unreadableNotKept: "Peptides can't be changed until the saved log can be copied aside."
        }
    }

    /// Why the iCloud backup can't carry the peptides, as a clause.
    var backupBlock: String {
        switch self {
        case .newerVersion: "Peptides were saved by a newer version of the app"
        case .upgradeNotKept: "Peptides from the earlier version couldn't be copied aside on this phone"
        case .notOpened: "Peptides couldn't be read on this phone"
        case .unreadableNotKept: "Peptides couldn't be read in full on this phone"
        }
    }
}

/// The saved file (version 3; version 2 reads the same way). One unreadable
/// record never drops the rest. Records a version-2 save tagged with the
/// second profile, and those in `held_aside`, are held aside.
struct PeptideLogSnapshot: Codable {
    var version: Int
    var entries: [PeptideLogEntry]
    var vials: [PeptideVial]
    var schedules: [PeptideUserSchedule]
    /// Waiting for the user to keep or delete them. Saved only when there are some.
    var heldAside = PeptideRecordSet()
    /// Settings → Syringe scale. Saved only when recorded.
    var syringeScale: PeptideSyringeScale?
    /// Records that were left out of an earlier save because they couldn't
    /// be read (an upgrade, or a damaged save). Saved only when above 0;
    /// older saves without it read as 0.
    var omitted = 0
    /// Records in this save that couldn't be read. Not saved.
    var skipped = 0

    var records: PeptideRecordsByProfile {
        PeptideRecordsByProfile(own: PeptideRecordSet(entries: entries, vials: vials, schedules: schedules), heldAside: heldAside)
    }

    enum CodingKeys: String, CodingKey {
        case version, entries, vials, schedules, omitted
        case heldAside = "held_aside"
        case syringeScale = "syringe_scale"
    }

    private enum HeldAsideKeys: String, CodingKey {
        case entries, vials, schedules
    }

    init(
        version: Int,
        entries: [PeptideLogEntry],
        vials: [PeptideVial],
        schedules: [PeptideUserSchedule],
        heldAside: PeptideRecordSet = PeptideRecordSet(),
        omitted: Int = 0
    ) {
        self.version = version
        self.entries = entries
        self.vials = vials
        self.schedules = schedules
        self.heldAside = heldAside
        self.omitted = omitted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        var malformed = 0
        let lossyEntries = Self.list(PeptideProfiled<PeptideLogEntry>.self, in: container, .entries, malformed: &malformed)
        let lossyVials = Self.list(PeptideProfiled<PeptideVial>.self, in: container, .vials, malformed: &malformed)
        let lossySchedules = Self.list(PeptideProfiled<PeptideUserSchedule>.self, in: container, .schedules, malformed: &malformed)
        let sorted = PeptideRecordsByProfile(
            entries: lossyEntries.compactMap(\.value),
            vials: lossyVials.compactMap(\.value),
            schedules: lossySchedules.compactMap(\.value)
        )
        entries = sorted.own.entries
        vials = sorted.own.vials
        schedules = sorted.own.schedules
        var held = sorted.heldAside
        var heldLossy = 0
        if (try? container.decodeNil(forKey: .heldAside)) == false {
            if let nested = try? container.nestedContainer(keyedBy: HeldAsideKeys.self, forKey: .heldAside) {
                let heldEntries = Self.list(PeptideLogEntry.self, in: nested, .entries, malformed: &malformed)
                let heldVials = Self.list(PeptideVial.self, in: nested, .vials, malformed: &malformed)
                let heldSchedules = Self.list(PeptideUserSchedule.self, in: nested, .schedules, malformed: &malformed)
                held.entries += heldEntries.compactMap(\.value)
                held.vials += heldVials.compactMap(\.value)
                held.schedules += heldSchedules.compactMap(\.value)
                heldLossy = heldEntries.count + heldVials.count + heldSchedules.count
            } else {
                malformed += 1
            }
        }
        heldAside = held
        let read = sorted.own.count + held.count
        skipped = lossyEntries.count + lossyVials.count + lossySchedules.count + heldLossy - read + malformed
        omitted = max((try? container.decodeIfPresent(Int.self, forKey: .omitted)) ?? 0, 0)
        let scale = (try? container.decodeIfPresent(Int.self, forKey: .syringeScale)).flatMap { $0 }
        syringeScale = scale.flatMap(PeptideSyringeScale.init(rawValue:))
    }

    /// One saved list, each record read on its own. Absent (or null) is an
    /// empty list. One that is there but isn't a list counts as one record
    /// that couldn't be read, so its bytes are kept aside before a save drops them.
    private static func list<Key: CodingKey, Value: Decodable>(
        _ type: Value.Type,
        in container: KeyedDecodingContainer<Key>,
        _ key: Key,
        malformed: inout Int
    ) -> [PeptideLossy<Value>] {
        do {
            return try container.decodeIfPresent([PeptideLossy<Value>].self, forKey: key) ?? []
        } catch {
            malformed += 1
            return []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(vials, forKey: .vials)
        try container.encode(schedules, forKey: .schedules)
        if !heldAside.isEmpty {
            var held = container.nestedContainer(keyedBy: HeldAsideKeys.self, forKey: .heldAside)
            try held.encode(heldAside.entries, forKey: .entries)
            try held.encode(heldAside.vials, forKey: .vials)
            try held.encode(heldAside.schedules, forKey: .schedules)
        }
        if omitted > 0 { try container.encode(omitted, forKey: .omitted) }
        try container.encodeIfPresent(syringeScale?.rawValue, forKey: .syringeScale)
    }

    /// The `version` of a saved log (1 when absent, as version-1 saves read).
    /// Nil when the bytes aren't a JSON object.
    static func savedVersion(of data: Data) -> Int? {
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { return nil }
        return probe.version ?? 1
    }

    private struct VersionProbe: Decodable {
        var version: Int?

        enum CodingKeys: String, CodingKey {
            case version
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try? container.decodeIfPresent(Int.self, forKey: .version)
        }
    }
}

// MARK: - iCloud backup

extension PeptideLogStore: CloudBackupPeptides {
    /// The archive without an export time, so unchanged peptides back up to the same bytes.
    /// Blocked while the saved log is read-only, so peptides this app couldn't
    /// read (or a newer app saved) are never backed up as what memory shows.
    func backupArchiveData() -> CloudBackupPart {
        reloadIfNotOpened()
        if let readOnly { return .blocked(reason: readOnly.backupBlock) }
        guard let data = try? archive(exportedAt: nil).encoded() else {
            return .blocked(reason: "Peptides couldn't be packed for the backup")
        }
        return .include(data)
    }

    /// Replaces the peptides only with a whole backup that was saved; otherwise
    /// the phone's peptides stay as they are and the reason is returned.
    func restoreArchiveData(_ data: Data) -> String? {
        let reason: String
        do {
            guard let problem = replaceAll(with: try PeptideArchive.decode(data, complete: true)) else { return nil }
            reason = problem
        } catch {
            reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        return "Peptides weren't restored, so the ones on this phone were kept. " + reason
    }
}
