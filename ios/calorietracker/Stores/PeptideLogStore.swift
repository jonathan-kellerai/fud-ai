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
    func fetchAdministrations(from: String, to: String) async throws -> [PeptideAdministration]
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

    func fetchAdministrations(from: String, to: String) async throws -> [PeptideAdministration] {
        try await service.peptideAdministrations(from: from, to: to, includeVoided: true).administrations
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

enum PeptideLogPersistence {
    /// App group `Library/Application Support/PeptideLog/peptide_log_v1.json`, UserDefaults fallback.
    case appGroup
    /// Nothing is written (tests, Visual QA).
    case inMemory
    case file(URL)
}

// MARK: - Store

@Observable
@MainActor
final class PeptideLogStore {
    static let defaultsKey = "peptide.log.v1"
    static let personKey = "peptides.selectedPerson"
    static let historyDays = 400
    static let readOnlyMessage = "Recorded by the peptide assistant. It can't be changed in the app."
    static let historyUnavailableMessage = "Bridge needs the history update. Showing today and what's saved on this phone."

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

    private let persistence: PeptideLogPersistence
    private let client: any PeptideBridgeClient
    private let autoFlush: Bool

    init(
        persistence: PeptideLogPersistence = .appGroup,
        client: (any PeptideBridgeClient)? = nil,
        autoFlush: Bool = true
    ) {
        self.persistence = persistence
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
        PeptideMath.remaining(vial: vial, entries: entries)
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
        if entry.isAgentRow || entry.isPlanned { return Self.readOnlyMessage }
        if entry.isPendingCreate {
            guard let opID = entry.pendingOpID,
                  let index = pendingOps.firstIndex(where: { $0.id == opID }),
                  var payload = pendingOps[index].create else {
                return "This entry is no longer in the queue."
            }
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
        if (recordedVia ?? row?.recordedVia) == "peptide-agent" || row?.status.uppercased() == "PLANNED" {
            return Self.readOnlyMessage
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

    /// "Delete" means void with a reason. A queued create is simply removed.
    @discardableResult
    func void(_ entry: PeptideLogEntry, reason: String) -> String? {
        if entry.isAgentRow || entry.isPlanned { return Self.readOnlyMessage }
        if entry.isPendingCreate {
            guard let opID = entry.pendingOpID else { return "This entry is no longer in the queue." }
            pendingOps.removeAll { $0.id == opID }
            meta[entry.metaKey] = nil
            didChange()
            return nil
        }
        guard let rowID = entry.rowID else { return "This entry isn't saved yet." }
        return void(rowID: rowID, recordedVia: entry.recordedVia, reason: reason)
    }

    @discardableResult
    func void(rowID: String, recordedVia: String?, reason: String) -> String? {
        let row = rows[rowID]
        if (recordedVia ?? row?.recordedVia) == "peptide-agent" || row?.status.uppercased() == "PLANNED" {
            return Self.readOnlyMessage
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
        didChange()
        scheduleFlush()
    }

    func discard(opID: String) {
        guard let op = pendingOps.first(where: { $0.id == opID }) else { return }
        pendingOps.removeAll { $0.id == opID }
        if op.kind == .create { meta[op.id] = nil }
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
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        var needsRefresh = false
        var conflicts: [PeptideCreatePayload] = []
        let ids = pendingOps.filter { !$0.failed }.map(\.id)
        for id in ids {
            guard let op = pendingOps.first(where: { $0.id == id }), !op.failed else { continue }
            let outcome = await send(op)
            guard let index = pendingOps.firstIndex(where: { $0.id == id }) else { continue }
            var stop = false
            switch outcome {
            case .success(let row):
                let current = pendingOps[index]
                pendingOps.remove(at: index)
                upsert(row)
                if current.kind == .create, let edited = current.create, edited != op.create {
                    queueDifferences(edited, against: row)
                }
            case .alreadyDone:
                pendingOps.remove(at: index)
                needsRefresh = true
            case .keyConflict:
                if let payload = pendingOps[index].create { conflicts.append(payload) }
                pendingOps.remove(at: index)
                needsRefresh = true
            case .rejected(let message):
                pendingOps[index].failed = true
                pendingOps[index].attempts += 1
                pendingOps[index].lastError = message
            case .offline(let message):
                pendingOps[index].attempts += 1
                pendingOps[index].lastError = message
                stop = true
            }
            didChange()
            if stop { break }
        }
        isFlushing = false
        if needsRefresh {
            await refreshRows(now: Date())
            resolveConflicts(conflicts)
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
        do {
            let fetched = try await client.fetchAdministrations(from: from, to: to)
            mergeWindow(fetched, from: from, to: to)
            historyUnavailable = false
            lastSyncError = nil
            lastSync = now
        } catch {
            if Self.isMissingRoute(error) {
                historyUnavailable = true
                do {
                    let response = try await client.fetchToday(date: today)
                    for row in response.planned + response.completed where !row.id.isEmpty {
                        rows[row.id] = row
                    }
                    lastSyncError = nil
                    lastSync = now
                } catch {
                    lastSyncError = Self.message(for: error)
                }
            } else {
                lastSyncError = Self.message(for: error)
            }
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

    /// The bridge is the truth for rows inside the fetched window.
    private func mergeWindow(_ fetched: [PeptideAdministration], from: String, to: String) {
        var next: [String: PeptideAdministration] = [:]
        for row in rows.values {
            let civil = PeptideMath.parseISO8601(row.datetime).map(PeptideMath.civilDate) ?? ""
            if civil.isEmpty || civil < from || civil > to {
                next[row.id] = row
            }
        }
        for row in fetched where !row.id.isEmpty {
            next[row.id] = row
        }
        rows = next
    }

    private func upsert(_ row: PeptideAdministration) {
        guard !row.id.isEmpty else { return }
        rows[row.id] = row
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
    private func queueDifferences(_ payload: PeptideCreatePayload, against row: PeptideAdministration) {
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
        guard !changes.isEmpty, !row.voided, row.recordedVia != "peptide-agent" else { return }
        pendingOps.append(.makeCorrect(rowID: row.id, reason: "Edited in the app before it synced.", changes: changes))
    }

    private func resolveConflicts(_ payloads: [PeptideCreatePayload]) {
        guard !payloads.isEmpty else { return }
        for payload in payloads {
            let key = payload.clientRequestID.lowercased()
            if let row = rows.values.first(where: { $0.clientRequestID?.lowercased() == key }) {
                queueDifferences(payload, against: row)
            } else {
                var op = PeptidePendingOp.makeCreate(payload)
                op.failed = true
                op.lastError = "The bridge already has a different entry with this request ID."
                pendingOps.append(op)
            }
        }
        didChange()
        scheduleFlush()
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
        var synced = Set<String>()
        var result: [PeptideLogEntry] = []
        for row in rows.values {
            if let crid = row.clientRequestID { synced.insert(crid.lowercased()) }
            var entry = makeEntry(row)
            for op in opsByRow[row.id] ?? [] {
                apply(op, to: &entry)
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
        let readOnly = row.recordedVia == "peptide-agent" || status == "PLANNED"
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
            syncState: readOnly ? .readOnlyAgent : .synced,
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
            voided: false,
            voidReason: nil,
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

        enum CodingKeys: String, CodingKey {
            case version, rows, pendingOps, meta, vials, schedules, lastSync
        }

        init(
            version: Int,
            rows: [PeptideAdministration],
            pendingOps: [PeptidePendingOp],
            meta: [PeptideLocalMeta],
            vials: [PeptideVial],
            schedules: [PeptideUserSchedule],
            lastSync: Date?
        ) {
            self.version = version
            self.rows = rows
            self.pendingOps = pendingOps
            self.meta = meta
            self.vials = vials
            self.schedules = schedules
            self.lastSync = lastSync
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
        }
    }

    private var fileURL: URL? {
        switch persistence {
        case .inMemory:
            return nil
        case .file(let url):
            return url
        case .appGroup:
            guard let directory = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
                .appendingPathComponent("Library/Application Support/PeptideLog", isDirectory: true) else { return nil }
            return directory.appendingPathComponent("peptide_log_v1.json")
        }
    }

    private var usesDefaults: Bool {
        if case .appGroup = persistence { return true }
        return false
    }

    private func load() {
        if case .inMemory = persistence { return }
        var data: Data?
        if let url = fileURL {
            data = try? Data(contentsOf: url)
        }
        if data == nil, usesDefaults {
            data = UserDefaults.standard.data(forKey: Self.defaultsKey)
        }
        guard let data else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            keepUnreadable(data)
            return
        }
        rows = Dictionary(snapshot.rows.filter { !$0.id.isEmpty }.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        pendingOps = snapshot.pendingOps
        meta = Dictionary(snapshot.meta.map { ($0.key, $0) }, uniquingKeysWith: { _, latest in latest })
        vials = snapshot.vials
        schedules = snapshot.schedules
        lastSync = snapshot.lastSync
    }

    /// Never overwrite data that could not be read: set it aside first.
    private func keepUnreadable(_ data: Data) {
        guard let url = fileURL else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("peptide_log_v1.unreadable-\(stamp).json")
        try? data.write(to: backup, options: .atomic)
    }

    private func persist() {
        if case .inMemory = persistence { return }
        let snapshot = Snapshot(
            version: 1,
            rows: Array(rows.values),
            pendingOps: pendingOps,
            meta: Array(meta.values),
            vials: vials,
            schedules: schedules,
            lastSync: lastSync
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            persistError = "Peptide log couldn't be encoded."
            return
        }
        var wroteFile = false
        if let url = fileURL {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                wroteFile = true
                persistError = nil
            } catch {
                persistError = error.localizedDescription
            }
        }
        if usesDefaults {
            if wroteFile {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
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
