import Foundation
import Testing
@testable import calorietracker

/// The Peptides offline queue: nothing the user typed is lost, retries reuse
/// the same client_request_id, and the peptide assistant's rows stay read-only.
/// No network: every bridge call goes to `FakePeptideBridge`.
@MainActor
struct PeptideLogStoreTests {
    private func makeStore(_ bridge: FakePeptideBridge) -> PeptideLogStore {
        PeptideLogStore(persistence: .inMemory, client: bridge, autoFlush: false)
    }

    private func draft(compound: String = "BPC-157", amount: String = "500", units: String = "mcg") -> PeptideLogDraft {
        var draft = PeptideLogDraft.new(person: "jonathan", compound: compound, now: Date(timeIntervalSince1970: 1_790_000_000))
        draft.amountText = amount
        draft.units = units
        return draft
    }

    @Test func offlineCreateStaysPendingWithSameRequestID() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = URLError(.notConnectedToInternet)
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))

        await store.flush()
        await store.flush()

        #expect(bridge.createCalls.count == 2)
        #expect(bridge.createCalls.allSatisfy { $0.clientRequestID == crid })
        #expect(store.pendingCount == 1)
        let entry = try #require(store.entries.first)
        #expect(entry.syncState == .pending)
        #expect(entry.dose == 500)
        #expect(entry.units == "mcg")
        #expect(entry.person == "jonathan")
        #expect(store.pendingOps.first?.attempts == 2)

        bridge.createError = nil
        await store.flush()
        #expect(bridge.createCalls.last?.clientRequestID == crid)
        #expect(store.pendingCount == 0)
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.syncState == .synced)
        #expect(store.entries.first?.clientRequestID == crid)
    }

    @Test func invalidDraftIsNotQueued() {
        let store = makeStore(FakePeptideBridge())
        var empty = PeptideLogDraft.new(person: "jonathan", compound: "BPC-157")
        empty.units = "mcg"
        #expect(store.log(empty) == nil)
        #expect(store.pendingOps.isEmpty)
    }

    @Test func editingPendingCreateChangesTheQueuedPayload() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = URLError(.timedOut)
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))
        let entry = try #require(store.entries.first)
        #expect(entry.isPendingCreate)

        let message = store.correct(entry, reason: "", changes: PeptideCorrectionChanges(dose: 250, notes: "typo"))
        #expect(message == nil)
        #expect(store.pendingOps.count == 1)
        #expect(store.pendingOps.first?.create?.dose == 250)
        #expect(store.pendingOps.first?.create?.notes == "typo")
        #expect(store.pendingOps.first?.create?.clientRequestID == crid)
        #expect(store.entries.first?.dose == 250)

        await store.flush()
        #expect(bridge.createCalls.last?.dose == 250)
    }

    @Test func voidingPendingCreateRemovesIt() throws {
        let store = makeStore(FakePeptideBridge())
        _ = try #require(store.log(draft()))
        let entry = try #require(store.entries.first)
        #expect(store.void(entry, reason: "") == nil)
        #expect(store.pendingOps.isEmpty)
        #expect(store.entries.isEmpty)
    }

    @Test func rejectedCreateIsVisibleRetryableAndDiscardable() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = PeptideBridgeWriteError(status: 400, code: "invalid", message: "units must be 20 characters or fewer")
        let store = makeStore(bridge)
        _ = try #require(store.log(draft()))

        await store.flush()
        let failed = try #require(store.entries.first)
        #expect(failed.syncState == .failed("units must be 20 characters or fewer"))
        #expect(store.failedCount == 1)
        #expect(store.pendingCount == 0)

        // Failed ops wait for the user: another flush doesn't resend.
        await store.flush()
        #expect(bridge.createCalls.count == 1)

        bridge.createError = nil
        let opID = try #require(failed.pendingOpID)
        store.retry(opID: opID)
        await store.flush()
        #expect(bridge.createCalls.count == 2)
        #expect(store.failedCount == 0)
        #expect(store.entries.first?.syncState == .synced)

        let second = try #require(store.log(draft(compound: "TB-500", amount: "2", units: "mg")))
        bridge.createError = PeptideBridgeWriteError(status: 400, code: "invalid", message: "bad")
        await store.flush()
        #expect(store.failedCount == 1)
        store.discard(opID: second)
        #expect(store.pendingOps.isEmpty)
        #expect(store.entries.count == 1)
    }

    @Test func alreadyCompletedIsTreatedAsDone() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = PeptideBridgeWriteError(status: 409, code: "already_completed", message: "already_completed")
        let store = makeStore(bridge)
        _ = try #require(store.log(draft()))
        await store.flush()
        #expect(store.pendingOps.isEmpty)
        #expect(store.failedCount == 0)
        #expect(bridge.historyCalls >= 1)
    }

    @Test func agentRowsCannotBeCorrectedOrVoided() async throws {
        let bridge = FakePeptideBridge()
        bridge.history = [
            PeptideAdministration(
                id: "agent-1",
                datetime: "2026-09-20T13:00:00Z",
                compound: "Tesamorelin",
                dose: 1.4,
                units: "mg",
                recordedVia: "peptide-agent"
            ),
        ]
        let store = makeStore(bridge)
        await store.refresh()
        let entry = try #require(store.entries.first { $0.id == "agent-1" })
        #expect(entry.syncState == .readOnlyAgent)
        let correction = store.correct(entry, reason: "wrong time", changes: PeptideCorrectionChanges(dose: 1))
        #expect(correction == PeptideLogStore.readOnlyMessage)
        #expect(store.void(entry, reason: "duplicate") == PeptideLogStore.readOnlyMessage)
        #expect(store.pendingOps.isEmpty)
        #expect(bridge.correctCalls.isEmpty)
        #expect(bridge.voidCalls.isEmpty)
    }

    @Test func syncedAppRowCorrectionNeedsReasonAndQueues() async throws {
        let bridge = FakePeptideBridge()
        bridge.history = [
            PeptideAdministration(
                id: "app-1",
                datetime: "2026-09-20T13:00:00Z",
                compound: "BPC-157",
                dose: 500,
                units: "mcg",
                recordedVia: "app",
                clientRequestID: "abc"
            ),
        ]
        let store = makeStore(bridge)
        await store.refresh()
        let entry = try #require(store.entries.first)
        #expect(store.correct(entry, reason: "  ", changes: PeptideCorrectionChanges(dose: 250)) != nil)
        #expect(store.correct(entry, reason: "typo", changes: PeptideCorrectionChanges(dose: 250)) == nil)
        #expect(store.entries.first?.syncState == .pending)
        #expect(store.entries.first?.dose == 250)
        await store.flush()
        #expect(bridge.correctCalls.count == 1)
        #expect(bridge.correctCalls.first?.reason == "typo")
        #expect(store.pendingOps.isEmpty)
    }

    @Test func refreshFailureKeepsCachedRows() async throws {
        let bridge = FakePeptideBridge()
        bridge.history = [
            PeptideAdministration(id: "keep-1", datetime: "2026-09-20T13:00:00Z", compound: "MT2", dose: 250, units: "mcg", person: "victoria"),
        ]
        let store = makeStore(bridge)
        await store.refresh()
        #expect(store.entries.count == 1)
        bridge.historyError = URLError(.notConnectedToInternet)
        await store.refresh()
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.person == "victoria")
        #expect(store.lastSyncError != nil)
    }

    @Test func missingHistoryRouteFallsBackToToday() async throws {
        let bridge = FakePeptideBridge()
        bridge.historyError = NeonBridgeError.httpError(statusCode: 404, message: "not_found")
        let store = makeStore(bridge)
        await store.refresh()
        #expect(store.historyUnavailable)
        #expect(bridge.todayCalls == 1)
    }
}

/// Scripted bridge. Records every write.
@MainActor
final class FakePeptideBridge: PeptideBridgeClient {
    var history: [PeptideAdministration] = []
    var historyError: Error?
    var createError: Error?
    var historyCalls = 0
    var todayCalls = 0
    var createCalls: [PeptideCreatePayload] = []
    var correctCalls: [(rowID: String, reason: String, changes: PeptideCorrectionChanges)] = []
    var voidCalls: [(rowID: String, reason: String)] = []

    nonisolated deinit {}

    func fetchAdministrations(from: String, to: String) async throws -> [PeptideAdministration] {
        historyCalls += 1
        if let historyError { throw historyError }
        return history
    }

    func fetchToday(date: String) async throws -> PeptideTodayResponse {
        todayCalls += 1
        let json = #"{"date":"\#(date)","timezone":"America/New_York","has_active_schedules":false,"planned":[],"completed":[]}"#
        return try JSONDecoder().decode(PeptideTodayResponse.self, from: Data(json.utf8))
    }

    func fetchInventory() async throws -> [PeptideInventoryItem] {
        []
    }

    func create(_ payload: PeptideCreatePayload) async throws -> PeptideAdministration {
        createCalls.append(payload)
        if let createError { throw createError }
        let row = PeptideAdministration(
            id: "row-" + payload.clientRequestID,
            datetime: payload.datetime,
            compound: payload.compound ?? "",
            dose: payload.dose,
            units: payload.units,
            route: payload.route,
            notes: payload.notes,
            person: payload.person,
            recordedVia: "app",
            clientRequestID: payload.clientRequestID
        )
        history.removeAll { $0.id == row.id }
        history.append(row)
        return row
    }

    func correct(rowID: String, reason: String, changes: PeptideCorrectionChanges) async throws -> PeptideAdministration {
        correctCalls.append((rowID: rowID, reason: reason, changes: changes))
        guard let index = history.firstIndex(where: { $0.id == rowID }) else {
            throw PeptideBridgeWriteError(status: 404, code: "not_found", message: "not_found")
        }
        if let dose = changes.dose { history[index].dose = dose }
        if let notes = changes.notes { history[index].notes = notes }
        return history[index]
    }

    func voidRow(rowID: String, reason: String) async throws -> PeptideAdministration {
        voidCalls.append((rowID: rowID, reason: reason))
        guard let index = history.firstIndex(where: { $0.id == rowID }) else {
            throw PeptideBridgeWriteError(status: 404, code: "not_found", message: "not_found")
        }
        history[index].voided = true
        history[index].voidReason = reason
        return history[index]
    }
}
