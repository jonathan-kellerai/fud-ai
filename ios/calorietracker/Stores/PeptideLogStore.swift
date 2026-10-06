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
    static let defaultsKey = "peptide.log.v1"
    static let personKey = "peptides.selectedPerson"
    /// Version of the saved file. Version 1 was the bridge-era cache and queue.
    static let fileVersion = 2

    private(set) var vials: [PeptideVial] = []
    private(set) var schedules: [PeptideUserSchedule] = []
    /// Every logged dose, oldest first.
    private(set) var entries: [PeptideLogEntry] = []
    private(set) var persistError: String?
    /// Plain-text note when the saved log couldn't be read in full.
    private(set) var storageNote: String?
    /// Saving would overwrite data that wasn't read: a save from a newer
    /// app, or an older one that couldn't be set aside before upgrading.
    @ObservationIgnored private var savingBlocked = false
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

    /// Entries for one person on one civil date, by time.
    func dayEntries(_ civil: String, person: String, includeVoided: Bool) -> [PeptideLogEntry] {
        let owner = PeptidePerson.normalized(person)
        return entries.filter {
            $0.civilDate == civil && PeptidePerson.normalized($0.person) == owner && (includeVoided || !$0.voided)
        }
    }

    func personVials(person: String, includeFinished: Bool = false) -> [PeptideVial] {
        let owner = PeptidePerson.normalized(person)
        return vials.filter {
            PeptidePerson.normalized($0.person) == owner && (includeFinished || $0.status == .active)
        }
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

    func lowStockVials(person: String?) -> [PeptideVial] {
        vials.filter { vial in
            vial.status == .active
                && (person == nil || PeptidePerson.normalized(vial.person) == PeptidePerson.normalized(person))
                && remaining(for: vial).isLow
        }
    }

    func personSchedules(person: String) -> [PeptideUserSchedule] {
        let owner = PeptidePerson.normalized(person)
        return schedules.filter { PeptidePerson.normalized($0.person) == owner }
    }

    /// Compounds this person has logged before, newest first, one per compound key.
    func loggedCompounds(person: String) -> [String] {
        let owner = PeptidePerson.normalized(person)
        var seen = Set<String>()
        var names: [String] = []
        for entry in entries.reversed() where PeptidePerson.normalized(entry.person) == owner {
            let key = PeptideMath.compoundKey(entry.compound)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            names.append(entry.compound)
        }
        return names
    }

    /// Doses logged on `civil` that count, both people, by time.
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

    /// Saves a dose from what the user typed. Returns its id, or nil when the
    /// draft is not valid. Saving the same id again replaces that entry.
    @discardableResult
    func log(_ draft: PeptideLogDraft, id: String? = nil, now: Date = Date()) -> String? {
        guard PeptideMath.validate(draft).isEmpty, let dose = draft.amount, let units = draft.units else { return nil }
        let entryID = (id ?? UUID().uuidString).lowercased()
        let datetime = PeptideMath.iso8601NewYork(draft.takenAt)
        let entry = PeptideLogEntry(
            id: entryID,
            person: PeptidePerson.normalized(draft.person),
            compound: draft.trimmedCompound,
            dose: dose,
            units: units,
            date: PeptideMath.parseISO8601(datetime),
            datetimeRaw: datetime,
            route: draft.trimmedSite.isEmpty ? nil : draft.trimmedSite,
            notes: draft.trimmedNotes.isEmpty ? nil : draft.trimmedNotes,
            vialID: draft.vialID,
            drawnVolume: draft.drawnVolume,
            drawnUnit: draft.drawnVolume == nil ? nil : draft.drawnUnit,
            createdAt: PeptideMath.iso8601NewYork(now)
        )
        entries.removeAll { $0.id == entryID }
        entries.append(entry)
        didChangeEntries()
        return entryID
    }

    /// Changes a logged dose in place. A reason is required and every changed
    /// field goes into the entry's correction trail. Returns an error
    /// message, or nil when saved.
    @discardableResult
    func correct(_ entry: PeptideLogEntry, reason: String, changes: PeptideCorrectionChanges, now: Date = Date()) -> String? {
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
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return "This entry is no longer here." }
        if entries[index].voided { return "This entry is already voided." }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A reason is required." }
        entries[index] = entries[index].voiding(reason: trimmed, at: PeptideMath.iso8601NewYork(now))
        didChangeEntries()
        return nil
    }

    /// Vial link and drawn volume. No reason needed.
    func updateLocalDetails(for entry: PeptideLogEntry, vialID: String?, drawnVolume: Double?, drawnUnit: String?) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].vialID = vialID
        entries[index].drawnVolume = drawnVolume
        entries[index].drawnUnit = drawnVolume == nil ? nil : (drawnUnit ?? "mL")
        didChange()
    }

    // MARK: Vials and schedules

    func saveVial(_ vial: PeptideVial) {
        if let index = vials.firstIndex(where: { $0.id == vial.id }) {
            vials[index] = vial
        } else {
            vials.append(vial)
        }
        didChange()
    }

    func finishVial(id: String) {
        guard let index = vials.firstIndex(where: { $0.id == id }) else { return }
        vials[index].status = .finished
        didChange()
    }

    func deleteVial(id: String) {
        vials.removeAll { $0.id == id }
        didChange()
    }

    func saveSchedule(_ schedule: PeptideUserSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        didChange()
    }

    func setScheduleActive(id: String, active: Bool) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].active = active
        didChange()
    }

    func deleteSchedule(id: String) {
        schedules.removeAll { $0.id == id }
        didChange()
    }

    // MARK: Archive

    /// Everything on this phone in the archive format.
    func archive(exportedAt: Date?) -> PeptideArchive {
        PeptideArchive(
            exportedAt: exportedAt.map(PeptideMath.iso8601NewYork),
            vials: vials,
            schedules: schedules,
            entries: entries
        )
    }

    /// What importing `archive` would add. A record whose id is already here
    /// (or earlier in the file) is left alone, so importing twice adds nothing.
    func importSummary(of archive: PeptideArchive) -> PeptideImportSummary {
        var summary = PeptideImportSummary(skipped: archive.skipped)
        var vialIDs = Set(vials.map(\.id))
        for vial in archive.vials {
            if vialIDs.insert(vial.id).inserted {
                summary.newVials += 1
                if vial.person == nil { summary.newVialsWithoutPerson += 1 }
            } else {
                summary.alreadyHere += 1
            }
        }
        var scheduleIDs = Set(schedules.map(\.id))
        for schedule in archive.schedules {
            if scheduleIDs.insert(schedule.id).inserted { summary.newSchedules += 1 } else { summary.alreadyHere += 1 }
        }
        var entryIDs = Set(entries.map(\.id))
        for entry in archive.entries {
            if entryIDs.insert(entry.id).inserted { summary.newEntries += 1 } else { summary.alreadyHere += 1 }
        }
        return summary
    }

    /// Adds what `archive` has that this phone doesn't. Records with no
    /// person go to `person`. Nothing already here is changed.
    @discardableResult
    func importArchive(_ archive: PeptideArchive, person: String, now: Date = Date()) -> PeptideImportSummary {
        let summary = importSummary(of: archive)
        guard summary.added > 0 else { return summary }
        for vial in archive.vials where !vials.contains(where: { $0.id == vial.id }) {
            vials.append(vial.vial(defaultPerson: person, now: now))
        }
        for schedule in archive.schedules where !schedules.contains(where: { $0.id == schedule.id }) {
            schedules.append(schedule.schedule(defaultPerson: person, now: now))
        }
        for entry in archive.entries where !entries.contains(where: { $0.id == entry.id }) {
            entries.append(entry)
        }
        didChangeEntries()
        return summary
    }

    /// Replaces everything with `archive` (iCloud restore). A vial or schedule
    /// with no person is Jonathan's, as on any record without one. Saved
    /// first: when it can't be saved, nothing in memory or saved changes and the
    /// reason is returned.
    func replaceAll(with archive: PeptideArchive, now: Date = Date()) -> String? {
        let newVials = archive.vials.map { $0.vial(defaultPerson: PeptidePerson.jonathan, now: now) }
        let newSchedules = archive.schedules.map { $0.schedule(defaultPerson: PeptidePerson.jonathan, now: now) }
        let newEntries = Self.sorted(archive.entries)
        if savingBlocked { return persistError ?? "Peptides can't be saved on this phone right now." }
        if !file.isInMemory, case .failure(let error)? = save(entries: newEntries, vials: newVials, schedules: newSchedules, fallbackOnFailure: false) {
            return error.localizedDescription
        }
        vials = newVials
        schedules = newSchedules
        entries = newEntries
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
        persistError = nil
        storageNote = nil
        omitted = 0
        savingBlocked = false
    }

    // MARK: Private

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
        guard let data = file.read() else { return }
        guard let version = PeptideLogSnapshot.savedVersion(of: data) else {
            file.keepUnreadable(data)
            return
        }
        if version == Self.fileVersion {
            guard let snapshot = try? JSONDecoder().decode(PeptideLogSnapshot.self, from: data) else {
                file.keepUnreadable(data)
                return
            }
            // Records skipped now are dropped by the next save, so they join the count saved with it.
            apply(entries: snapshot.entries, vials: snapshot.vials, schedules: snapshot.schedules, omitted: snapshot.omitted + snapshot.skipped)
        } else if version == 1 {
            upgrade(data)
        } else {
            // Saved by a newer app: never overwrite it.
            savingBlocked = true
            storageNote = "Peptides were saved by a newer version of the app, so they can't be shown here. Update the app to see them."
            persistError = "Changes to peptides aren't saved until the app is updated."
        }
    }

    /// Version 1 → on-device records. The untouched version-1 bytes are set
    /// aside first; if that fails, the records are shown but nothing is saved.
    private func upgrade(_ data: Data) {
        guard let migrated = PeptideLegacyLog.migrate(data) else {
            file.keepUnreadable(data)
            return
        }
        apply(entries: migrated.entries, vials: migrated.vials, schedules: migrated.schedules, omitted: migrated.skipped)
        guard file.keepBeforeUpgrade(data) else {
            savingBlocked = true
            persistError = "Peptides from the earlier version couldn't be backed up on this phone, so changes aren't saved yet."
            return
        }
        persist()
    }

    private func apply(entries: [PeptideLogEntry], vials: [PeptideVial], schedules: [PeptideUserSchedule], omitted: Int) {
        self.entries = Self.sorted(entries)
        self.vials = vials
        self.schedules = schedules
        self.omitted = omitted
        if omitted > 0 {
            let records = omitted == 1 ? "1 saved peptide record" : "\(omitted) saved peptide records"
            storageNote = "\(records) couldn't be read, so \(omitted == 1 ? "it isn't" : "they aren't") listed. Remaining in a vial may be off."
        }
    }

    private func persist() {
        if file.isInMemory || savingBlocked { return }
        switch save(entries: entries, vials: vials, schedules: schedules) {
        case .success?:
            persistError = nil
        case .failure(let error)?:
            persistError = error.localizedDescription
        case nil:
            break
        }
    }

    /// Writes these records as the saved log. Nil when there is no file to write.
    private func save(entries: [PeptideLogEntry], vials: [PeptideVial], schedules: [PeptideUserSchedule], fallbackOnFailure: Bool = true) -> Result<Void, Error>? {
        let snapshot = PeptideLogSnapshot(version: Self.fileVersion, entries: entries, vials: vials, schedules: schedules, omitted: omitted)
        guard let data = try? JSONEncoder().encode(snapshot) else { return .failure(SaveError.encoding) }
        return file.write(data, fallbackOnFailure: fallbackOnFailure)
    }

    private enum SaveError: LocalizedError {
        case encoding

        var errorDescription: String? { "Peptide log couldn't be encoded." }
    }
}

/// The saved file (version 2). One unreadable record never drops the rest.
struct PeptideLogSnapshot: Codable {
    var version: Int
    var entries: [PeptideLogEntry]
    var vials: [PeptideVial]
    var schedules: [PeptideUserSchedule]
    /// Records that were left out of an earlier save because they couldn't
    /// be read (an upgrade, or a damaged save). Saved only when above 0;
    /// older saves without it read as 0.
    var omitted = 0
    /// Records in this save that couldn't be read. Not saved.
    var skipped = 0

    enum CodingKeys: String, CodingKey {
        case version, entries, vials, schedules, omitted
    }

    init(version: Int, entries: [PeptideLogEntry], vials: [PeptideVial], schedules: [PeptideUserSchedule], omitted: Int = 0) {
        self.version = version
        self.entries = entries
        self.vials = vials
        self.schedules = schedules
        self.omitted = omitted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let lossyEntries = (try? container.decode([PeptideLossy<PeptideLogEntry>].self, forKey: .entries)) ?? []
        entries = lossyEntries.compactMap(\.value)
        let lossyVials = (try? container.decode([PeptideLossy<PeptideVial>].self, forKey: .vials)) ?? []
        vials = lossyVials.compactMap(\.value)
        let lossySchedules = (try? container.decode([PeptideLossy<PeptideUserSchedule>].self, forKey: .schedules)) ?? []
        schedules = lossySchedules.compactMap(\.value)
        skipped = (lossyEntries.count - entries.count) + (lossyVials.count - vials.count) + (lossySchedules.count - schedules.count)
        omitted = max((try? container.decodeIfPresent(Int.self, forKey: .omitted)) ?? 0, 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(vials, forKey: .vials)
        try container.encode(schedules, forKey: .schedules)
        if omitted > 0 { try container.encode(omitted, forKey: .omitted) }
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
    func backupArchiveData() -> Data? {
        try? archive(exportedAt: nil).encoded()
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
