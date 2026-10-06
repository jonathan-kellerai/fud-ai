//
//  PeptideLogStore.swift
//  calorietracker
//
//  Peptides log: cached bridge rows, an offline write queue, and the user's own
//  vials and schedules (device only). Logs what the user enters; it sets no
//  doses and recommends no protocol. Bridge inventory, schedules and PLANNED
//  rows belong to the peptide assistant and are read-only here.
//

import Foundation

// MARK: - Bridge client

/// The bridge calls the store makes. Tests and Visual QA pass their own.
@MainActor
protocol PeptideBridgeClient: AnyObject {
    /// One history window, voided rows included.
    func fetchAdministrations(from: String, to: String, limit: Int) async throws -> PeptideAdministrationList
    func fetchToday(date: String) async throws -> PeptideTodayResponse
    func fetchInventory() async throws -> [PeptideInventoryItem]
    func create(_ payload: PeptideCreatePayload) async throws -> PeptideAdministration
    func correct(rowID: String, reason: String, changes: PeptideCorrectionChanges) async throws -> PeptideAdministration
    func voidRow(rowID: String, reason: String) async throws -> PeptideAdministration
}

@MainActor
final class NeonPeptideBridgeClient: PeptideBridgeClient {
    private var service: NeonBridgeService { NeonBridgeService.shared }

    init() {}

    func fetchAdministrations(from: String, to: String, limit: Int) async throws -> PeptideAdministrationList {
        try await service.peptideAdministrations(from: from, to: to, includeVoided: true, limit: limit)
    }

    func fetchToday(date: String) async throws -> PeptideTodayResponse {
        try await service.peptidesToday(date: date, includeVoided: true)
    }

    func fetchInventory() async throws -> [PeptideInventoryItem] {
        try await service.peptideInventory()
    }

    func create(_ payload: PeptideCreatePayload) async throws -> PeptideAdministration {
        try await service.postPeptideAdministration(body: payload.body())
    }

    func correct(rowID: String, reason: String, changes: PeptideCorrectionChanges) async throws -> PeptideAdministration {
        try await service.patchPeptideAdministration(id: rowID, body: [
            "action": "correct",
            "reason": reason,
            "changes": changes.dictionary(),
        ])
    }

    func voidRow(rowID: String, reason: String) async throws -> PeptideAdministration {
        try await service.patchPeptideAdministration(id: rowID, body: [
            "action": "void",
            "reason": reason,
        ])
    }
}

// MARK: - Store

@Observable
@MainActor
final class PeptideLogStore {
    static let defaultsKey = "peptide.log.v1"
    static let personKey = "peptides.selectedPerson"
    static let historyDays = 400
    static let readOnlyMessage = "Recorded by the peptide assistant. It can't be changed in the app."
    static let unknownOriginMessage = "This entry wasn't recorded by this app, so it can't be changed here."
    static let historyUnavailableMessage = "Bridge needs the history update. Showing today and what's saved on this phone."
    static let cancelledCreateReason = "Removed in the app before it synced."
    static let keyConflictMessage = "The bridge already has a different entry with this request ID. Refresh, then retry."
    static let alreadyCompletedMissingMessage = "The bridge says this dose is already logged, but that entry isn't in the synced history yet. Refresh, then retry."
    static let cancelUnconfirmedMessage = "Removed in the app, but an earlier send may have reached the bridge and that entry isn't in the synced history yet. Refresh to check."
    static let plannedTakenElsewhereMessage = "This planned dose was already marked taken somewhere else, so these details weren't saved. Discard this, or log it again as a new dose."
    /// History is fetched in windows of this many days, each with this row limit.
    static let historyWindowDays = 90
    static let historyLimit = 5000

    static func message(readOnly entry: PeptideLogEntry) -> String {
        entry.isAgentRow || entry.isPlanned ? readOnlyMessage : unknownOriginMessage
    }

    /// Cached bridge rows by id (last 400 days).
    private(set) var rows: [String: PeptideAdministration] = [:]
    private(set) var pendingOps: [PeptidePendingOp] = []
    private(set) var meta: [String: PeptideLocalMeta] = [:]
    private(set) var vials: [PeptideVial] = []
    private(set) var schedules: [PeptideUserSchedule] = []
    /// Peptide-assistant inventory mirror. Memory only, shown verbatim.
    private(set) var inventory: [PeptideInventoryItem] = []
    /// Bridge rows merged with queued creates, oldest first.
    private(set) var entries: [PeptideLogEntry] = []
    private(set) var lastSync: Date?
    private(set) var lastSyncError: String?
    private(set) var historyUnavailable = false
    private(set) var isRefreshing = false
    private(set) var isFlushing = false
    private(set) var persistError: String?
    /// Bridge rows in the last refresh that couldn't be read (no id).
    private(set) var skippedRowCount = 0
    /// True only after a refresh where every history window answered, none
    /// reached its row limit and no row was skipped. Saved with the log; older
    /// saves read as false until the next full refresh.
    private(set) var historyComplete = false
    /// The queued create being sent right now, if any.
    private(set) var inFlightOpID: String?
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private let file: PeptideLogFile
    private let client: any PeptideBridgeClient
    private let autoFlush: Bool

    init(
        persistence: PeptideLogPersistence = .appGroup,
        client: (any PeptideBridgeClient)? = nil,
        autoFlush: Bool = true
    ) {
        self.file = PeptideLogFile(persistence: persistence, defaultsKey: Self.defaultsKey)
        self.client = client ?? NeonPeptideBridgeClient()
        self.autoFlush = autoFlush
        load()
        rebuildEntries()
    }

    /// Explicit nonisolated deinit: the synthesized main-actor-isolated deinit
    /// double-frees a TaskLocal scope on iOS <= 26.2 (swiftlang/swift#88036)
    /// when the store is released inside a task-local context.
    nonisolated deinit {}

    // MARK: Derived

    var pendingCount: Int { pendingOps.filter { !$0.failed }.count }
    var failedCount: Int { pendingOps.filter(\.failed).count }

    /// Shown when some bridge rows couldn't be read.
    var syncWarning: String? {
        guard skippedRowCount > 0 else { return nil }
        let rows = skippedRowCount == 1 ? "1 row" : "\(skippedRowCount) rows"
        return "\(rows) from the bridge couldn't be read, so they aren't listed. Remaining in vials isn't calculated until they can be."
    }

    /// A queued create the bridge may already have (in flight, timed out,
    /// offline after sending, or in an idempotency conflict).
    func isCreateUncertain(_ entry: PeptideLogEntry) -> Bool {
        guard let opID = entry.pendingOpID, let op = pendingOps.first(where: { $0.id == opID }) else { return false }
        return op.kind == .create && (op.isUncertain || op.isReconciling || op.id == inFlightOpID)
    }

    func entry(id: String, clientRequestID: String? = nil) -> PeptideLogEntry? {
        if let match = entries.first(where: { $0.id == id }) { return match }
        if let clientRequestID {
            let key = clientRequestID.lowercased()
            return entries.first { $0.clientRequestID?.lowercased() == key }
        }
        return nil
    }

    /// COMPLETED entries for one person on one civil date, by time.
    func dayEntries(_ civil: String, person: String, includeVoided: Bool) -> [PeptideLogEntry] {
        let owner = PeptidePerson.normalized(person)
        return entries.filter {
            $0.isCompleted && $0.civilDate == civil && PeptidePerson.normalized($0.person) == owner
                && (includeVoided || !$0.voided)
        }
    }

    /// The assistant's PLANNED rows for one person on one civil date.
    func plannedEntries(_ civil: String, person: String) -> [PeptideLogEntry] {
        let owner = PeptidePerson.normalized(person)
        return entries.filter {
            $0.isPlanned && !$0.voided && $0.civilDate == civil && PeptidePerson.normalized($0.person) == owner
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
        PeptideMath.remaining(vial: vial, entries: entries, incompleteHistory: historyBlocksRemaining(for: vial))
    }

    /// Remaining as if `extra` (a dose being reviewed) were logged too.
    func remaining(for vial: PeptideVial, including extra: PeptideLogEntry) -> PeptideMath.Remaining {
        PeptideMath.remaining(vial: vial, entries: entries + [extra], incompleteHistory: historyBlocksRemaining(for: vial))
    }

    /// Remaining is uncalculable while bridge history isn't fully synced: a
    /// dose from the vial could be in history that hasn't loaded. Exception: a
    /// phone that has never synced history (no lastSync) and whose vial has
    /// no doses from the bridge computes from what's on the phone, since the
    /// vial and its links exist only here and every linked dose is local.
    func historyBlocksRemaining(for vial: PeptideVial) -> Bool {
        if historyComplete && skippedRowCount == 0 { return false }
        if lastSync != nil { return true }
        return entries.contains { $0.vialID == vial.id && $0.rowID != nil }
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
        for entry in entries.reversed() where entry.isCompleted && PeptidePerson.normalized(entry.person) == owner {
            let key = PeptideMath.compoundKey(entry.compound)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            names.append(entry.compound)
        }
        return names
    }

    func inventoryItem(id: String?) -> PeptideInventoryItem? {
        guard let id else { return nil }
        return inventory.first { $0.id == id }
    }

    /// Local data that should keep the Home card visible.
    func hasLocalActivity(today civil: String) -> Bool {
        if !pendingOps.isEmpty { return true }
        if schedules.contains(where: \.active) { return true }
        if vials.contains(where: { $0.status == .active }) { return true }
        return entries.contains { $0.isCompleted && !$0.voided && $0.civilDate == civil && !$0.isAgentRow }
    }

    // MARK: Logging

    /// Queues a completed administration from what the user typed. Returns the
    /// client_request_id, or nil when the draft is not valid.
    @discardableResult
    func log(_ draft: PeptideLogDraft, clientRequestID: String? = nil) -> String? {
        guard PeptideMath.validate(draft).isEmpty, let dose = draft.amount, let units = draft.units else { return nil }
        let crid = (clientRequestID ?? UUID().uuidString).lowercased()
        let payload = PeptideCreatePayload(
            clientRequestID: crid,
            plannedID: nil,
            datetime: PeptideMath.iso8601NewYork(draft.takenAt),
            dose: dose,
            units: units,
            compound: draft.trimmedCompound,
            route: draft.trimmedSite.isEmpty ? nil : draft.trimmedSite,
            notes: draft.trimmedNotes.isEmpty ? nil : draft.trimmedNotes,
            sourceVial: nil,
            person: PeptidePerson.normalized(draft.person)
        )
        enqueueCreate(payload)
        let local = PeptideLocalMeta(
            key: crid,
            vialID: draft.vialID,
            drawnVolume: draft.drawnVolume,
            drawnUnit: draft.drawnVolume == nil ? nil : draft.drawnUnit
        )
        if local.isEmpty {
            meta[crid] = nil
        } else {
            meta[crid] = local
        }
        didChange()
        scheduleFlush()
        return crid
    }

    /// "Mark taken" on the assistant's PLANNED row. `dose` is only sent when the
    /// user changed it. Person is omitted so the bridge uses the planned row's.
    @discardableResult
    func logPlanned(plannedID: String, takenAt: Date, dose: Double?, notes: String?, clientRequestID: String) -> String {
        let crid = clientRequestID.lowercased()
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let payload = PeptideCreatePayload(
            clientRequestID: crid,
            plannedID: plannedID,
            datetime: PeptideMath.iso8601NewYork(takenAt),
            dose: dose,
            units: nil,
            compound: nil,
            route: nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            sourceVial: nil,
            person: nil
        )
        enqueueCreate(payload)
        didChange()
        return crid
    }

    /// Message for a queued create that the bridge refused, if any.
    func failureMessage(forOp id: String) -> String? {
        guard let op = pendingOps.first(where: { $0.id == id.lowercased() || $0.id == id }), op.failed else { return nil }
        return op.lastError ?? "The bridge didn't accept this entry."
    }

    /// Message for the latest refused correction or void of a bridge row, if any.
    func failureMessage(forRow rowID: String) -> String? {
        guard let op = pendingOps.last(where: { $0.rowID == rowID && $0.failed }) else { return nil }
        return op.lastError ?? "The bridge didn't accept this change."
    }

    func isQueued(_ id: String) -> Bool {
        pendingOps.contains { $0.id == id.lowercased() || $0.id == id }
    }

    /// Edits a queued create in place (no reason needed), or queues a correction
    /// for a bridge row. Returns an error message, or nil when accepted.
    @discardableResult
    func correct(_ entry: PeptideLogEntry, reason: String, changes: PeptideCorrectionChanges) -> String? {
        if !entry.isEditableInApp { return Self.message(readOnly: entry) }
        if entry.isPendingCreate {
            guard let opID = entry.pendingOpID,
                  let index = pendingOps.firstIndex(where: { $0.id == opID }),
                  var payload = pendingOps[index].create else {
                return "This entry is no longer in the queue."
            }
            if pendingOps[index].cancelReason != nil { return "This entry is being removed." }
            // In flight or uncertain: the edited payload is compared with what
            // the bridge returns and the difference is queued as a correction.
            changes.apply(to: &payload)
            pendingOps[index].create = payload
            pendingOps[index].failed = false
            pendingOps[index].lastError = nil
            didChange()
            scheduleFlush()
            return nil
        }
        guard let rowID = entry.rowID else { return "This entry isn't saved yet." }
        return correct(rowID: rowID, recordedVia: entry.recordedVia, reason: reason, changes: changes)
    }

    @discardableResult
    func correct(rowID: String, recordedVia: String?, reason: String, changes: PeptideCorrectionChanges) -> String? {
        let row = rows[rowID]
        if let refusal = Self.readOnlyRefusal(recordedVia: recordedVia ?? row?.recordedVia, row: row) {
            return refusal
        }
        if row?.voided == true { return "This entry is voided." }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A reason is required." }
        guard !changes.isEmpty else { return "Nothing changed." }
        let scheduled = row.map { $0.plannedId != nil || $0.scheduleId != nil } ?? false
        if scheduled && (changes.compound != nil || changes.units != nil || changes.sourceVial != nil) {
            return "Compound and units can't be changed on a scheduled dose. Void it and log it again."
        }
        pendingOps.append(.makeCorrect(rowID: rowID, reason: trimmed, changes: changes))
        didChange()
        scheduleFlush()
        return nil
    }

    /// "Delete" means void with a reason. A queued create that was never sent
    /// is simply removed. One the bridge may already have keeps its queue
    /// entry with the cancellation; once the bridge returns the row (the retry
    /// replays idempotently), a void with this reason is queued for it.
    @discardableResult
    func void(_ entry: PeptideLogEntry, reason: String) -> String? {
        if !entry.isEditableInApp { return Self.message(readOnly: entry) }
        if entry.isPendingCreate {
            guard let opID = entry.pendingOpID else { return "This entry is no longer in the queue." }
            cancelCreate(opID: opID, reason: reason)
            return nil
        }
        guard let rowID = entry.rowID else { return "This entry isn't saved yet." }
        return void(rowID: rowID, recordedVia: entry.recordedVia, reason: reason)
    }

    private func cancelCreate(opID: String, reason: String) {
        guard let index = pendingOps.firstIndex(where: { $0.id == opID }) else { return }
        let op = pendingOps[index]
        let neverSent = !op.isUncertain && !op.isReconciling && op.id != inFlightOpID
        if op.kind != .create || neverSent {
            pendingOps.remove(at: index)
            if op.kind == .create { meta[op.id] = nil }
        } else {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingOps[index].cancelReason = trimmed.isEmpty ? Self.cancelledCreateReason : trimmed
            pendingOps[index].failed = false
            pendingOps[index].lastError = nil
            scheduleFlush()
        }
        didChange()
    }

    /// Only rows recorded by this app (recorded_via == "app") can change.
    private static func readOnlyRefusal(recordedVia: String?, row: PeptideAdministration?) -> String? {
        if recordedVia == "peptide-agent" || row?.status.uppercased() == "PLANNED" { return readOnlyMessage }
        if recordedVia != "app" { return unknownOriginMessage }
        return nil
    }

    @discardableResult
    func void(rowID: String, recordedVia: String?, reason: String) -> String? {
        let row = rows[rowID]
        if let refusal = Self.readOnlyRefusal(recordedVia: recordedVia ?? row?.recordedVia, row: row) {
            return refusal
        }
        if row?.voided == true { return "This entry is already voided." }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A reason is required." }
        pendingOps.append(.makeVoid(rowID: rowID, reason: trimmed))
        didChange()
        scheduleFlush()
        return nil
    }

    /// Device-only vial link and drawn volume. No reason needed.
    func updateLocalDetails(for entry: PeptideLogEntry, vialID: String?, drawnVolume: Double?, drawnUnit: String?) {
        let key = entry.metaKey
        let local = PeptideLocalMeta(
            key: key,
            vialID: vialID,
            drawnVolume: drawnVolume,
            drawnUnit: drawnVolume == nil ? nil : (drawnUnit ?? "mL")
        )
        meta[key] = local.isEmpty ? nil : local
        didChange()
    }

    func retry(opID: String) {
        guard let index = pendingOps.firstIndex(where: { $0.id == opID }) else { return }
        pendingOps[index].failed = false
        pendingOps[index].lastError = nil
        // A create stuck in an idempotency conflict is sent again; the bridge
        // answers with the conflict and reconciliation runs after a refresh.
        pendingOps[index].reconciling = nil
        pendingOps[index].reconcileCause = nil
        didChange()
        scheduleFlush()
    }

    /// Drops a refused write. A create the bridge may already have is
    /// cancelled instead (voided there once it answers), never just forgotten.
    /// A failed create whose bridge row is already known (its follow-up
    /// couldn't be queued) is simply dropped: the bridge row stays as it is.
    func discard(opID: String) {
        guard let op = pendingOps.first(where: { $0.id == opID }) else { return }
        if op.kind == .create && op.failed, let row = matchedRow(for: op) {
            pendingOps.removeAll { $0.id == opID }
            if row.clientRequestID?.lowercased() != op.id.lowercased() { meta[op.id] = nil }
            didChange()
            return
        }
        if op.kind == .create {
            cancelCreate(opID: opID, reason: "")
            return
        }
        pendingOps.removeAll { $0.id == opID }
        didChange()
    }

    // MARK: Vials and schedules (device only)

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

    // MARK: Sync

    func refreshIfStale(maxAge: TimeInterval = 300, now: Date = Date()) async {
        if let lastSync, now.timeIntervalSince(lastSync) < maxAge, lastSyncError == nil {
            await flush()
            return
        }
        await refresh(now: now)
    }

    /// History for both people plus the assistant's inventory, then the queue.
    /// Cached rows are kept when the bridge can't be reached.
    func refresh(now: Date = Date()) async {
        await refreshRows(now: now)
        await flush()
    }

    /// Sends queued writes one at a time. Network and 5xx failures stay queued
    /// with the same client_request_id; 4xx answers wait for Retry or Discard.
    /// A call made while a pass is running waits for it (and for a follow-up
    /// pass when new writes were queued meanwhile), so callers can rely on the
    /// queue having been tried when this returns.
    func flush() async {
        if let running = flushTask {
            await running.value
            if let again = flushTask {
                await again.value
                return
            }
            guard pendingOps.contains(where: { !$0.failed && !$0.isReconciling }) else { return }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runFlush()
            self.flushTask = nil
        }
        flushTask = task
        await task.value
    }

    private func runFlush() async {
        isFlushing = true
        var needsRefresh = false
        var attempted = Set<String>()
        // Writes queued during the pass (a void for a just-created row, a
        // follow-up correction) are picked up by the same loop.
        while let op = pendingOps.first(where: { !$0.failed && !$0.isReconciling && !attempted.contains($0.id) }) {
            let id = op.id
            attempted.insert(id)
            let wasUncertain = op.isUncertain
            if op.kind == .create, let index = pendingOps.firstIndex(where: { $0.id == id }) {
                // From here the bridge may commit the row even if no answer arrives.
                pendingOps[index].outcomeUncertain = true
                persist()
            }
            inFlightOpID = id
            let outcome = await send(op)
            inFlightOpID = nil
            let index = pendingOps.firstIndex(where: { $0.id == id })
            var stop = false
            switch outcome {
            case .success(let row):
                upsert(row)
                if let index {
                    let current = pendingOps[index]
                    let result: FollowUp = current.kind == .create
                        ? followUp(for: current, row: row, sent: op.create, isOwnCopy: true)
                        : .nothingToDo
                    settle(opID: id, result)
                }
            case .alreadyDone:
                if let index {
                    if pendingOps[index].kind == .create {
                        // Kept (saved) until the completed row is found and
                        // any void or correction for it is queued.
                        pendingOps[index].reconciling = true
                        pendingOps[index].reconcileCause = PeptidePendingOp.causeAlreadyCompleted
                        pendingOps[index].attempts += 1
                        pendingOps[index].lastError = nil
                    } else {
                        pendingOps.remove(at: index)
                    }
                }
                needsRefresh = true
            case .keyConflict:
                // Keep the user's edits queued until the server row is found
                // and the correction is queued (see reconcilePending()).
                if let index {
                    pendingOps[index].reconciling = true
                    pendingOps[index].attempts += 1
                    pendingOps[index].lastError = nil
                }
                needsRefresh = true
            case .rejected(let message):
                if let index {
                    if pendingOps[index].kind == .create && pendingOps[index].cancelReason != nil {
                        if wasUncertain {
                            // This send was refused, but an earlier one may
                            // have committed: keep the cancellation and look
                            // for the row on the next refresh.
                            pendingOps[index].reconciling = true
                            pendingOps[index].reconcileCause = PeptidePendingOp.causeRejectedAfterUncertain
                            pendingOps[index].attempts += 1
                            pendingOps[index].lastError = nil
                            needsRefresh = true
                        } else {
                            // Removed by the user and the only send was refused: nothing to undo.
                            let removed = pendingOps.remove(at: index)
                            meta[removed.id] = nil
                        }
                    } else {
                        pendingOps[index].failed = true
                        pendingOps[index].attempts += 1
                        pendingOps[index].lastError = message
                        if pendingOps[index].kind == .create {
                            // A refusal means this send wasn't committed.
                            pendingOps[index].outcomeUncertain = wasUncertain ? true : nil
                        }
                    }
                }
            case .offline(let message):
                if let index {
                    pendingOps[index].attempts += 1
                    pendingOps[index].lastError = message
                }
                stop = true
            }
            didChange()
            if stop { break }
        }
        isFlushing = false
        if needsRefresh {
            // Reconciliation (see reconcilePending()) runs inside the refresh.
            await refreshRows(now: Date())
        }
    }

    // MARK: Private

    private enum SendOutcome {
        case success(PeptideAdministration)
        case alreadyDone
        case keyConflict
        case rejected(String)
        case offline(String)
    }

    private func send(_ op: PeptidePendingOp) async -> SendOutcome {
        do {
            switch op.kind {
            case .create:
                guard let payload = op.create else { return .rejected("Nothing to send.") }
                return .success(try await client.create(payload))
            case .correct:
                guard let rowID = op.rowID, let changes = op.changes else { return .rejected("Nothing to send.") }
                return .success(try await client.correct(rowID: rowID, reason: op.reason ?? "", changes: changes))
            case .void:
                guard let rowID = op.rowID else { return .rejected("Nothing to send.") }
                return .success(try await client.voidRow(rowID: rowID, reason: op.reason ?? ""))
            }
        } catch let error as PeptideBridgeWriteError {
            return Self.classify(error, kind: op.kind)
        } catch let error as NeonBridgeError {
            if case .httpError(let status, let message) = error {
                return Self.classify(
                    PeptideBridgeWriteError(status: status, code: message, message: message ?? "HTTP \(status)"),
                    kind: op.kind
                )
            }
            return .offline(error.localizedDescription)
        } catch {
            return .offline(error.localizedDescription)
        }
    }

    private static func classify(_ error: PeptideBridgeWriteError, kind: PeptidePendingKind) -> SendOutcome {
        let code = error.code ?? ""
        if error.status == 409 {
            if code == "already_completed" { return .alreadyDone }
            if code == "idempotency_key_conflict" { return .keyConflict }
            if code == "voided" { return kind == .void ? .alreadyDone : .rejected("This entry was voided on the bridge.") }
            if code == "conflict" { return .rejected("This entry changed somewhere else. Refresh, then retry.") }
            return .rejected(error.message)
        }
        if error.status == 403 && code == "read_only" { return .rejected(readOnlyMessage) }
        // A missing or wrong bridge key is not the entry's fault: keep it queued.
        if error.status == 401 { return .offline("Add the bridge key in Train › Bridge to sync peptides.") }
        if error.status == 408 || error.status == 429 || error.status >= 500 { return .offline(error.message) }
        if (400..<500).contains(error.status) { return .rejected(error.message) }
        return .offline(error.message)
    }

    private func refreshRows(now: Date) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let today = PeptideMath.civilDate(now)
        let from = ReconMath.addDays(today, -(Self.historyDays - 8))
        let to = ReconMath.addDays(today, 7)
        var fetched: [PeptideAdministration] = []
        var skipped = 0
        var truncated = false
        var failure: Error?
        var windowStart = from
        var windows = 0
        // Bounded windows, each with an explicit limit. A full window is
        // reported as truncated; nothing already cached is dropped.
        while windowStart <= to && windows < 10 {
            let windowEnd = min(ReconMath.addDays(windowStart, Self.historyWindowDays - 1), to)
            do {
                let page = try await client.fetchAdministrations(from: windowStart, to: windowEnd, limit: Self.historyLimit)
                fetched.append(contentsOf: page.administrations)
                skipped += page.skippedRows
                if page.administrations.count + page.skippedRows >= Self.historyLimit { truncated = true }
            } catch {
                failure = error
                break
            }
            windowStart = ReconMath.addDays(windowEnd, 1)
            windows += 1
        }
        // Whatever arrived is merged, even when a later window failed.
        mergeFetched(fetched)
        // Complete only when every window answered, none hit the limit and
        // nothing was skipped (the /today fallback is never complete).
        historyComplete = failure == nil && !truncated && skipped == 0 && windowStart > to
        if let failure {
            if fetched.isEmpty && Self.isMissingRoute(failure) {
                historyUnavailable = true
                do {
                    let response = try await client.fetchToday(date: today)
                    mergeFetched(response.planned + response.completed)
                    skippedRowCount = response.skippedRows
                    lastSyncError = nil
                    lastSync = now
                    reconcilePending()
                } catch {
                    lastSyncError = Self.message(for: error)
                }
            } else {
                lastSyncError = Self.message(for: failure)
            }
        } else {
            historyUnavailable = false
            skippedRowCount = skipped
            lastSyncError = truncated
                ? "Some history wasn't loaded: a \(Self.historyWindowDays)-day window reached the \(Self.historyLimit)-row limit."
                : nil
            lastSync = now
            reconcilePending()
        }
        if let items = try? await client.fetchInventory() {
            inventory = items
        }
        isRefreshing = false
        didChange()
    }

    private static func isMissingRoute(_ error: Error) -> Bool {
        if case NeonBridgeError.httpError(let status, _) = error { return status == 404 || status == 405 }
        if let write = error as? PeptideBridgeWriteError { return write.status == 404 || write.status == 405 }
        return false
    }

    private static func message(for error: Error) -> String {
        if case NeonBridgeError.httpError(let status, _) = error, status == 401 || status == 503 {
            return "Add the bridge key in Train › Bridge to sync peptides."
        }
        return error.localizedDescription
    }

    /// Upsert by id only. The bridge never hard-deletes (voids come back as
    /// voided rows), so a row missing from a response is never removed here.
    private func mergeFetched(_ fetched: [PeptideAdministration]) {
        for row in fetched {
            upsert(row)
        }
    }

    /// Keeps the cached copy when it is newer (an older GET racing a newer
    /// POST/PATCH answer).
    private func upsert(_ row: PeptideAdministration) {
        guard !row.id.isEmpty else { return }
        if let cached = rows[row.id], Self.isNewer(cached, than: row) { return }
        rows[row.id] = row
    }

    static func isNewer(_ lhs: PeptideAdministration, than rhs: PeptideAdministration) -> Bool {
        guard let left = lhs.updatedAt, let right = rhs.updatedAt else { return false }
        if let leftDate = PeptideMath.parseISO8601(left), let rightDate = PeptideMath.parseISO8601(right) {
            return leftDate > rightDate
        }
        return false
    }

    private func row(forClientRequestID crid: String) -> PeptideAdministration? {
        let key = crid.lowercased()
        return rows.values.first { $0.clientRequestID?.lowercased() == key }
    }

    /// What happened to the follow-up write of a create whose row is known.
    private enum FollowUp {
        /// A void or correction was added to the queue.
        case queued
        /// Nothing left to send (or it was already queued).
        case nothingToDo
        /// It can't be sent (not the app's own completed row); the message says why.
        case refused(String)
    }

    /// Same ownership rule as the public correct/void paths: only COMPLETED
    /// rows recorded by this app (recorded_via == "app") can change.
    private static func ownershipRefusal(_ row: PeptideAdministration) -> String? {
        if let refusal = readOnlyRefusal(recordedVia: row.recordedVia, row: row) { return refusal }
        if row.status.uppercased() != "COMPLETED" { return readOnlyMessage }
        return nil
    }

    /// Queues a void for a row the user removed before it synced.
    private func queueVoid(for row: PeptideAdministration, reason: String) -> FollowUp {
        if row.voided { return .nothingToDo }
        if pendingOps.contains(where: { $0.kind == .void && $0.rowID == row.id }) { return .nothingToDo }
        if let refusal = Self.ownershipRefusal(row) {
            return .refused("Removed in the app, but the bridge entry can't be voided here. " + refusal)
        }
        guard !row.id.isEmpty else { return .refused("The bridge entry has no id, so it can't be voided.") }
        pendingOps.append(.makeVoid(rowID: row.id, reason: reason))
        return .queued
    }

    /// The follow-up for a create once its bridge row is known. `isOwnCopy`:
    /// the row carries this create's client_request_id (or is the POST answer).
    /// Otherwise it is a completion of the same planned dose made elsewhere.
    private func followUp(
        for op: PeptidePendingOp,
        row: PeptideAdministration,
        sent: PeptideCreatePayload?,
        isOwnCopy: Bool
    ) -> FollowUp {
        guard let payload = op.create else { return .nothingToDo }
        if let reason = op.cancelReason {
            // Someone else's completion isn't the app's to void.
            return isOwnCopy ? queueVoid(for: row, reason: reason) : .nothingToDo
        }
        if isOwnCopy {
            if let sent, sent == payload { return .nothingToDo }
            return queueDifferences(payload, against: row)
        }
        // "Mark taken" with nothing typed: the planned dose is taken, as asked.
        if payload.dose == nil && payload.notes == nil { return .nothingToDo }
        return .refused(Self.plannedTakenElsewhereMessage)
    }

    /// Drops a create whose follow-up is queued (or not needed). When the
    /// follow-up can't be sent, the create stays saved as a failed
    /// reconciliation with the reason, for Retry or Discard.
    @discardableResult
    private func settle(opID: String, _ result: FollowUp) -> Bool {
        switch result {
        case .queued:
            pendingOps.removeAll { $0.id == opID }
            return true
        case .nothingToDo:
            pendingOps.removeAll { $0.id == opID }
            return false
        case .refused(let message):
            if let index = pendingOps.firstIndex(where: { $0.id == opID }) {
                pendingOps[index].reconciling = true
                pendingOps[index].failed = true
                pendingOps[index].lastError = message
            }
            return false
        }
    }

    /// The bridge row for a reconciling create: by client_request_id, or for
    /// a planned dose the bridge called already_completed, by planned_id /
    /// completed_id.
    private func matchedRow(for op: PeptidePendingOp) -> PeptideAdministration? {
        guard let payload = op.create else { return nil }
        if let row = row(forClientRequestID: payload.clientRequestID) { return row }
        guard op.reconcileCause == PeptidePendingOp.causeAlreadyCompleted, let plannedID = payload.plannedID else { return nil }
        if let completedID = rows[plannedID]?.completedId, let row = rows[completedID] { return row }
        return rows.values.first {
            $0.plannedId == plannedID && $0.status.uppercased() == "COMPLETED" && !$0.voided
        }
    }

    private func enqueueCreate(_ payload: PeptideCreatePayload) {
        if let index = pendingOps.firstIndex(where: { $0.id == payload.clientRequestID }) {
            pendingOps[index].create = payload
            pendingOps[index].failed = false
            pendingOps[index].lastError = nil
        } else {
            pendingOps.append(.makeCreate(payload))
        }
    }

    /// An edit made while the create was in flight (or after an idempotency
    /// conflict) becomes a correction so nothing the user typed is lost.
    private func queueDifferences(_ payload: PeptideCreatePayload, against row: PeptideAdministration) -> FollowUp {
        var changes = PeptideCorrectionChanges()
        if let typed = PeptideMath.parseISO8601(payload.datetime),
           let stored = PeptideMath.parseISO8601(row.datetime),
           abs(typed.timeIntervalSince(stored)) >= 1 {
            changes.datetime = payload.datetime
        }
        if let dose = payload.dose, dose != row.dose { changes.dose = dose }
        if (payload.route ?? "") != (row.route ?? "") { changes.route = payload.route ?? "" }
        if (payload.notes ?? "") != (row.notes ?? "") { changes.notes = payload.notes ?? "" }
        let scheduled = row.plannedId != nil || row.scheduleId != nil
        if !scheduled {
            if let compound = payload.compound, compound != row.compound { changes.compound = compound }
            if let units = payload.units, units != (row.units ?? "") { changes.units = units }
        }
        guard !changes.isEmpty, !row.voided else { return .nothingToDo }
        if let refusal = Self.ownershipRefusal(row) {
            return .refused("Edits made before this entry synced couldn't be sent. " + refusal)
        }
        pendingOps.append(.makeCorrect(rowID: row.id, reason: "Edited in the app before it synced.", changes: changes))
        return .queued
    }

    /// After a successful refresh: each reconciling create (idempotency
    /// conflict, already_completed, or a refused cancellation after an
    /// uncertain send) and each uncertain create is matched to its bridge row.
    /// The follow-up void or correction is queued first; only then is the
    /// create dropped. Not found: it stays saved, marked failed with why, and
    /// is checked again on every refresh.
    private func reconcilePending() {
        var changed = false
        var queued = false
        for op in pendingOps where op.kind == .create && op.id != inFlightOpID
            && (op.isReconciling || (op.isUncertain && !op.failed)) {
            guard let payload = op.create else { continue }
            if let row = matchedRow(for: op) {
                // The bridge has it: the create is done; queue what's left.
                let isOwnCopy = row.clientRequestID?.lowercased() == payload.clientRequestID.lowercased()
                let result = followUp(for: op, row: row, sent: nil, isOwnCopy: isOwnCopy)
                if settle(opID: op.id, result) { queued = true }
                if !isOwnCopy && !pendingOps.contains(where: { $0.id == op.id }) { meta[op.id] = nil }
                changed = true
            } else if op.isReconciling {
                if op.reconcileCause == PeptidePendingOp.causeRejectedAfterUncertain && historyComplete {
                    // Full history has no row with this request id: no send
                    // reached the bridge, so the removal is complete.
                    pendingOps.removeAll { $0.id == op.id }
                    meta[op.id] = nil
                } else if let index = pendingOps.firstIndex(where: { $0.id == op.id }) {
                    pendingOps[index].failed = true
                    pendingOps[index].lastError = Self.reconcileMessage(cause: op.reconcileCause)
                }
                changed = true
            }
        }
        if changed { didChange() }
        if queued { scheduleFlush() }
    }

    private static func reconcileMessage(cause: String?) -> String {
        if cause == PeptidePendingOp.causeAlreadyCompleted { return alreadyCompletedMissingMessage }
        if cause == PeptidePendingOp.causeRejectedAfterUncertain { return cancelUnconfirmedMessage }
        return keyConflictMessage
    }

    private func scheduleFlush() {
        guard autoFlush else { return }
        Task { [weak self] in
            await self?.flush()
        }
    }

    private func didChange() {
        rebuildEntries()
        persist()
    }

    private func rebuildEntries() {
        var opsByRow: [String: [PeptidePendingOp]] = [:]
        for op in pendingOps where op.kind != .create {
            if let rowID = op.rowID { opsByRow[rowID, default: []].append(op) }
        }
        // Creates still queued although the bridge row is known (a removal or
        // edit waiting to be queued, or one that couldn't be sent).
        var createOps: [String: PeptidePendingOp] = [:]
        for op in pendingOps where op.kind == .create {
            if let crid = op.create?.clientRequestID { createOps[crid.lowercased()] = op }
        }
        var synced = Set<String>()
        var result: [PeptideLogEntry] = []
        for row in rows.values {
            if let crid = row.clientRequestID { synced.insert(crid.lowercased()) }
            var entry = makeEntry(row)
            for op in opsByRow[row.id] ?? [] {
                apply(op, to: &entry)
            }
            if let crid = row.clientRequestID, let op = createOps[crid.lowercased()],
               op.cancelReason == nil || !entry.voided {
                if op.cancelReason != nil {
                    // Removed by the user before the create's answer arrived.
                    entry.voided = true
                    entry.voidReason = op.cancelReason
                }
                entry.pendingOpID = op.id
                entry.syncState = op.failed ? .failed(op.lastError ?? "The bridge didn't accept this change.") : .pending
            }
            result.append(entry)
        }
        for op in pendingOps where op.kind == .create {
            guard let payload = op.create, !synced.contains(payload.clientRequestID.lowercased()) else { continue }
            result.append(makePendingEntry(op, payload: payload))
        }
        result.sort { lhs, rhs in
            let left = lhs.date ?? .distantPast
            let right = rhs.date ?? .distantPast
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
        entries = result
    }

    private func makeEntry(_ row: PeptideAdministration) -> PeptideLogEntry {
        let status = row.status.uppercased()
        let syncState: PeptideSyncState
        if row.recordedVia == "peptide-agent" || status == "PLANNED" {
            syncState = .readOnlyAgent
        } else if row.recordedVia != "app" {
            // Missing or unknown origin: read-only.
            syncState = .readOnly
        } else {
            syncState = .synced
        }
        let local = meta[row.clientRequestID?.lowercased() ?? row.id] ?? meta[row.id]
        return PeptideLogEntry(
            id: row.id,
            rowID: row.id,
            clientRequestID: row.clientRequestID,
            person: PeptidePerson.normalized(row.person),
            compound: row.compound,
            dose: row.dose,
            units: row.units,
            date: PeptideMath.parseISO8601(row.datetime),
            datetimeRaw: row.datetime,
            route: row.route,
            notes: row.notes,
            sourceVial: row.sourceVial,
            status: status,
            plannedID: row.plannedId,
            scheduleID: row.scheduleId,
            completedID: row.completedId,
            voided: row.voided,
            voidReason: row.voidReason,
            recordedVia: row.recordedVia,
            corrections: row.correctionHistory,
            badges: row.badges,
            vialID: local?.vialID,
            drawnVolume: local?.drawnVolume,
            drawnUnit: local?.drawnUnit,
            syncState: syncState,
            pendingOpID: nil,
            createdAt: row.createdAt
        )
    }

    private func makePendingEntry(_ op: PeptidePendingOp, payload: PeptideCreatePayload) -> PeptideLogEntry {
        let planned = payload.plannedID.flatMap { rows[$0] }
        let local = meta[payload.clientRequestID]
        let state: PeptideSyncState = op.failed ? .failed(op.lastError ?? "The bridge didn't accept this entry.") : .pending
        return PeptideLogEntry(
            id: "pending-" + payload.clientRequestID,
            rowID: nil,
            clientRequestID: payload.clientRequestID,
            person: PeptidePerson.normalized(payload.person ?? planned?.person),
            compound: payload.compound ?? planned?.compound ?? "Planned dose",
            dose: payload.dose ?? planned?.dose,
            units: payload.units ?? planned?.units,
            date: PeptideMath.parseISO8601(payload.datetime),
            datetimeRaw: payload.datetime,
            route: payload.route,
            notes: payload.notes,
            sourceVial: payload.sourceVial,
            status: "COMPLETED",
            plannedID: payload.plannedID,
            scheduleID: planned?.scheduleId,
            completedID: nil,
            voided: op.cancelReason != nil,
            voidReason: op.cancelReason,
            recordedVia: "app",
            corrections: [],
            badges: [],
            vialID: local?.vialID,
            drawnVolume: local?.drawnVolume,
            drawnUnit: local?.drawnUnit,
            syncState: state,
            pendingOpID: op.id,
            createdAt: nil
        )
    }

    private func apply(_ op: PeptidePendingOp, to entry: inout PeptideLogEntry) {
        switch op.kind {
        case .create:
            return
        case .correct:
            guard let changes = op.changes else { return }
            var date = entry.date
            if let datetime = changes.datetime { date = PeptideMath.parseISO8601(datetime) }
            entry = PeptideLogEntry(
                id: entry.id,
                rowID: entry.rowID,
                clientRequestID: entry.clientRequestID,
                person: entry.person,
                compound: changes.compound ?? entry.compound,
                dose: changes.dose ?? entry.dose,
                units: changes.units ?? entry.units,
                date: date,
                datetimeRaw: changes.datetime ?? entry.datetimeRaw,
                route: changes.route ?? entry.route,
                notes: changes.notes ?? entry.notes,
                sourceVial: changes.sourceVial ?? entry.sourceVial,
                status: entry.status,
                plannedID: entry.plannedID,
                scheduleID: entry.scheduleID,
                completedID: entry.completedID,
                voided: entry.voided,
                voidReason: entry.voidReason,
                recordedVia: entry.recordedVia,
                corrections: entry.corrections,
                badges: entry.badges,
                vialID: entry.vialID,
                drawnVolume: entry.drawnVolume,
                drawnUnit: entry.drawnUnit,
                syncState: entry.syncState,
                pendingOpID: entry.pendingOpID,
                createdAt: entry.createdAt
            )
        case .void:
            entry.voided = true
            entry.voidReason = op.reason
        }
        entry.pendingOpID = op.id
        entry.syncState = op.failed ? .failed(op.lastError ?? "The bridge didn't accept this change.") : .pending
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var version: Int
        var rows: [PeptideAdministration]
        var pendingOps: [PeptidePendingOp]
        var meta: [PeptideLocalMeta]
        var vials: [PeptideVial]
        var schedules: [PeptideUserSchedule]
        var lastSync: Date?
        var historyComplete: Bool

        enum CodingKeys: String, CodingKey {
            case version, rows, pendingOps, meta, vials, schedules, lastSync, historyComplete
        }

        init(
            version: Int,
            rows: [PeptideAdministration],
            pendingOps: [PeptidePendingOp],
            meta: [PeptideLocalMeta],
            vials: [PeptideVial],
            schedules: [PeptideUserSchedule],
            lastSync: Date?,
            historyComplete: Bool
        ) {
            self.version = version
            self.rows = rows
            self.pendingOps = pendingOps
            self.meta = meta
            self.vials = vials
            self.schedules = schedules
            self.lastSync = lastSync
            self.historyComplete = historyComplete
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? container.decode(Int.self, forKey: .version)) ?? 1
            let lossyRows = (try? container.decode([PeptideLossy<PeptideAdministration>].self, forKey: .rows)) ?? []
            rows = lossyRows.compactMap(\.value)
            let lossyOps = (try? container.decode([PeptideLossy<PeptidePendingOp>].self, forKey: .pendingOps)) ?? []
            pendingOps = lossyOps.compactMap(\.value)
            let lossyMeta = (try? container.decode([PeptideLossy<PeptideLocalMeta>].self, forKey: .meta)) ?? []
            meta = lossyMeta.compactMap(\.value)
            let lossyVials = (try? container.decode([PeptideLossy<PeptideVial>].self, forKey: .vials)) ?? []
            vials = lossyVials.compactMap(\.value)
            let lossySchedules = (try? container.decode([PeptideLossy<PeptideUserSchedule>].self, forKey: .schedules)) ?? []
            schedules = lossySchedules.compactMap(\.value)
            lastSync = try? container.decodeIfPresent(Date.self, forKey: .lastSync)
            // Older saves have no flag: not complete until the next full refresh.
            let savedComplete = (try? container.decodeIfPresent(Bool.self, forKey: .historyComplete)) ?? false
            // A saved row or local link that no longer decodes may have been a dose from a vial,
            // so the cache can't vouch for completeness until the next full refresh.
            let droppedSomething = rows.count != lossyRows.count || meta.count != lossyMeta.count
            historyComplete = savedComplete && !droppedSomething
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(rows, forKey: .rows)
            try container.encode(pendingOps, forKey: .pendingOps)
            try container.encode(meta, forKey: .meta)
            try container.encode(vials, forKey: .vials)
            try container.encode(schedules, forKey: .schedules)
            try container.encodeIfPresent(lastSync, forKey: .lastSync)
            try container.encode(historyComplete, forKey: .historyComplete)
        }
    }

    private func load() {
        guard let data = file.read() else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            file.keepUnreadable(data)
            return
        }
        rows = Dictionary(snapshot.rows.filter { !$0.id.isEmpty }.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        pendingOps = snapshot.pendingOps
        meta = Dictionary(snapshot.meta.map { ($0.key, $0) }, uniquingKeysWith: { _, latest in latest })
        vials = snapshot.vials
        schedules = snapshot.schedules
        lastSync = snapshot.lastSync
        historyComplete = snapshot.historyComplete
    }

    private func persist() {
        if file.isInMemory { return }
        let snapshot = Snapshot(
            version: 1,
            rows: Array(rows.values),
            pendingOps: pendingOps,
            meta: Array(meta.values),
            vials: vials,
            schedules: schedules,
            lastSync: lastSync,
            historyComplete: historyComplete
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            persistError = "Peptide log couldn't be encoded."
            return
        }
        switch file.write(data) {
        case .success?:
            persistError = nil
        case .failure(let error)?:
            persistError = error.localizedDescription
        case nil:
            break
        }
    }
}

// MARK: - Row cache

extension PeptideAdministration: Encodable {
    init(
        id: String,
        datetime: String,
        compound: String,
        dose: Double? = nil,
        units: String? = nil,
        volume: Double? = nil,
        volumeUnits: String? = nil,
        route: String? = nil,
        notes: String? = nil,
        status: String = "COMPLETED",
        plannedId: String? = nil,
        scheduleId: String? = nil,
        completedId: String? = nil,
        sourceVial: String? = nil,
        voided: Bool = false,
        doseDeviatesFromPlanned: Bool = false,
        volumeBasis: String? = nil,
        calcGate: String? = nil,
        concentrationBasis: String? = nil,
        badges: [String] = [],
        person: String? = nil,
        recordedVia: String? = nil,
        voidReason: String? = nil,
        correctionHistory: [PeptideCorrection] = [],
        createdAt: String? = nil,
        updatedAt: String? = nil,
        clientRequestID: String? = nil
    ) {
        self.id = id
        self.datetime = datetime
        self.compound = compound
        self.dose = dose
        self.units = units
        self.volume = volume
        self.volumeUnits = volumeUnits
        self.route = route
        self.notes = notes
        self.status = status
        self.plannedId = plannedId
        self.scheduleId = scheduleId
        self.completedId = completedId
        self.sourceVial = sourceVial
        self.voided = voided
        self.doseDeviatesFromPlanned = doseDeviatesFromPlanned
        self.volumeBasis = volumeBasis
        self.calcGate = calcGate
        self.concentrationBasis = concentrationBasis
        self.badges = badges
        self.person = person
        self.recordedVia = recordedVia
        self.voidReason = voidReason
        self.correctionHistory = correctionHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.clientRequestID = clientRequestID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(datetime, forKey: .datetime)
        try container.encode(compound, forKey: .compound)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encodeIfPresent(units, forKey: .units)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(volumeUnits, forKey: .volumeUnits)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(plannedId, forKey: .plannedId)
        try container.encodeIfPresent(scheduleId, forKey: .scheduleId)
        try container.encodeIfPresent(completedId, forKey: .completedId)
        try container.encodeIfPresent(sourceVial, forKey: .sourceVial)
        try container.encode(voided, forKey: .voided)
        try container.encode(doseDeviatesFromPlanned, forKey: .doseDeviatesFromPlanned)
        try container.encodeIfPresent(volumeBasis, forKey: .volumeBasis)
        try container.encodeIfPresent(calcGate, forKey: .calcGate)
        try container.encodeIfPresent(concentrationBasis, forKey: .concentrationBasis)
        try container.encode(badges, forKey: .badges)
        try container.encodeIfPresent(person, forKey: .person)
        try container.encodeIfPresent(recordedVia, forKey: .recordedVia)
        try container.encodeIfPresent(voidReason, forKey: .voidReason)
        try container.encode(correctionHistory, forKey: .correctionHistory)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(clientRequestID, forKey: .clientRequestID)
    }
}
