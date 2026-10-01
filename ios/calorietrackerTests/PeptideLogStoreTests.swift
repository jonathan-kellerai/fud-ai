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
        bridge.history = [
            PeptideAdministration(
                id: "srv-done",
                datetime: PeptideMath.iso8601NewYork(Date(timeIntervalSince1970: 1_790_000_000)),
                compound: "BPC-157",
                dose: 500,
                units: "mcg",
                recordedVia: "app",
                clientRequestID: "crid-done"
            ),
        ]
        let store = makeStore(bridge)
        _ = try #require(store.log(draft(), clientRequestID: "crid-done"))
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

    // MARK: Uncertain creates

    @Test func voidDuringPostQueuesVoidForTheReturnedRow() async throws {
        let bridge = FakePeptideBridge()
        bridge.suspendCreates = true
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))
        let flushing = Task { await store.flush() }
        let started = await bridge.waitForSuspendedCreate()
        try #require(started)
        #expect(bridge.hasSuspendedCreate)
        #expect(store.inFlightOpID == crid)

        let entry = try #require(store.entries.first)
        #expect(entry.isPendingCreate)
        #expect(store.isCreateUncertain(entry))
        #expect(store.void(entry, reason: "Wrong vial") == nil)
        // Not deleted: the POST may still commit. The cancellation is kept.
        #expect(store.pendingOps.count == 1)
        #expect(store.pendingOps.first?.cancelReason == "Wrong vial")
        #expect(store.entries.first?.voided == true)

        bridge.suspendCreates = false
        bridge.resumeCreate()
        await flushing.value

        #expect(bridge.voidCalls.count == 1)
        #expect(bridge.voidCalls.first?.rowID == "row-" + crid)
        #expect(bridge.voidCalls.first?.reason == "Wrong vial")
        #expect(store.pendingOps.isEmpty)
        let synced = try #require(store.entries.first)
        #expect(synced.rowID == "row-" + crid)
        #expect(synced.voided)
        #expect(synced.voidReason == "Wrong vial")
        #expect(store.entries.count == 1)
    }

    @Test func voidAfterTimeoutReplaysCreateThenVoids() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = URLError(.timedOut)
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))
        await store.flush()
        let entry = try #require(store.entries.first)
        #expect(store.isCreateUncertain(entry))
        #expect(store.void(entry, reason: "") == nil)
        #expect(store.pendingOps.count == 1)
        #expect(store.pendingOps.first?.cancelReason == PeptideLogStore.cancelledCreateReason)

        bridge.createError = nil
        await store.flush()
        // Same client_request_id, so the bridge replays the row it may have kept.
        #expect(bridge.createCalls.allSatisfy { $0.clientRequestID == crid })
        #expect(bridge.voidCalls.count == 1)
        #expect(bridge.voidCalls.first?.reason == PeptideLogStore.cancelledCreateReason)
        #expect(store.pendingOps.isEmpty)
        #expect(store.entries.first?.voided == true)
    }

    @Test func voidOfNeverSentCreateDeletesIt() throws {
        let bridge = FakePeptideBridge()
        let store = makeStore(bridge)
        _ = try #require(store.log(draft()))
        let entry = try #require(store.entries.first)
        #expect(!store.isCreateUncertain(entry))
        #expect(store.void(entry, reason: "") == nil)
        #expect(store.pendingOps.isEmpty)
        #expect(bridge.createCalls.isEmpty)
    }

    @Test func secondFlushWaitsForTheRunningPass() async throws {
        let bridge = FakePeptideBridge()
        bridge.suspendCreates = true
        let store = makeStore(bridge)
        let first = try #require(store.log(draft()))
        let flushing = Task { await store.flush() }
        let started = await bridge.waitForSuspendedCreate()
        try #require(started)
        let second = try #require(store.log(draft(compound: "TB-500", amount: "2", units: "mg")))
        bridge.suspendCreates = false
        let waiting = Task { await store.flush() }
        bridge.resumeCreate()
        await waiting.value
        await flushing.value
        #expect(bridge.createCalls.map(\.clientRequestID) == [first, second])
        #expect(store.pendingOps.isEmpty)
    }

    // MARK: Idempotency conflict

    @Test func keyConflictKeepsEditsQueuedUntilTheServerRowIsFound() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = PeptideBridgeWriteError(status: 409, code: "idempotency_key_conflict", message: "idempotency_key_conflict")
        bridge.historyError = URLError(.notConnectedToInternet)
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))
        await store.flush()
        // History couldn't be read: the user's entry is still the only copy.
        #expect(store.pendingOps.count == 1)
        #expect(store.pendingOps.first?.isReconciling == true)
        #expect(store.pendingOps.first?.create?.dose == 500)
        #expect(store.entries.first?.dose == 500)

        // Another flush doesn't resend it while it waits to be reconciled.
        await store.flush()
        #expect(bridge.createCalls.count == 1)

        bridge.historyError = nil
        bridge.createError = nil
        bridge.history = [
            PeptideAdministration(
                id: "srv-1",
                datetime: PeptideMath.iso8601NewYork(Date(timeIntervalSince1970: 1_790_000_000)),
                compound: "BPC-157",
                dose: 300,
                units: "mcg",
                recordedVia: "app",
                clientRequestID: crid
            ),
        ]
        await store.refresh()
        #expect(bridge.correctCalls.count == 1)
        #expect(bridge.correctCalls.first?.rowID == "srv-1")
        #expect(bridge.correctCalls.first?.changes.dose == 500)
        #expect(store.pendingOps.isEmpty)
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.dose == 500)
    }

    // MARK: History refresh

    @Test func refreshNeverErasesCachedRows() async throws {
        let bridge = FakePeptideBridge()
        bridge.history = [
            PeptideAdministration(id: "a", datetime: "2026-09-20T13:00:00Z", compound: "MT2", dose: 250, units: "mcg", person: "victoria", recordedVia: "app"),
            PeptideAdministration(id: "b", datetime: "2026-09-21T13:00:00Z", compound: "MT2", dose: 250, units: "mcg", person: "victoria", recordedVia: "app"),
        ]
        let store = makeStore(bridge)
        await store.refresh()
        #expect(store.entries.count == 2)
        bridge.history = [bridge.history[0]]
        await store.refresh()
        #expect(store.entries.map(\.id).sorted() == ["a", "b"])
    }

    @Test func refreshUsesBoundedWindowsWithALimit() async throws {
        let bridge = FakePeptideBridge()
        let store = makeStore(bridge)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        await store.refresh(now: now)
        #expect(bridge.historyWindows.count >= 2)
        for window in bridge.historyWindows {
            let span = try #require(PeptideMath.daysBetween(window.from, window.to))
            #expect(span >= 0 && span < PeptideLogStore.historyWindowDays)
            #expect(window.limit == PeptideLogStore.historyLimit)
        }
        for (earlier, later) in zip(bridge.historyWindows, bridge.historyWindows.dropFirst()) {
            #expect(ReconMath.addDays(earlier.to, 1) == later.from)
        }
        #expect(bridge.historyWindows.last?.to == ReconMath.addDays(PeptideMath.civilDate(now), 7))
        #expect(store.lastSyncError == nil)
    }

    @Test func fullWindowIsReportedAsTruncated() async throws {
        let bridge = FakePeptideBridge()
        bridge.firstWindowExtra = (0..<PeptideLogStore.historyLimit).map {
            PeptideAdministration(id: "bulk-\($0)", datetime: "2026-09-01T13:00:00Z", compound: "BPC-157", dose: 1, units: "mcg", recordedVia: "app")
        }
        let store = makeStore(bridge)
        await store.refresh()
        #expect(store.lastSyncError?.contains("limit") == true)
        #expect(store.rows.count == PeptideLogStore.historyLimit)
        #expect(!store.historyComplete)
    }

    @Test func olderRefreshDoesNotOverwriteANewerRow() async throws {
        let bridge = FakePeptideBridge()
        let original = PeptideAdministration(
            id: "app-1",
            datetime: "2026-09-20T13:00:00Z",
            compound: "BPC-157",
            dose: 500,
            units: "mcg",
            recordedVia: "app",
            updatedAt: "2026-09-20T13:00:00Z",
            clientRequestID: "abc"
        )
        bridge.history = [original]
        let store = makeStore(bridge)
        await store.refresh()
        let entry = try #require(store.entries.first)
        #expect(store.correct(entry, reason: "typo", changes: PeptideCorrectionChanges(dose: 250)) == nil)
        await store.flush()
        #expect(store.entries.first?.dose == 250)
        // A GET that started before the PATCH answers with the old row.
        bridge.history = [original]
        await store.refresh()
        #expect(store.entries.first?.dose == 250)
    }

    @Test func rowsWithoutRecordedViaAreReadOnly() async throws {
        let bridge = FakePeptideBridge()
        bridge.history = [
            PeptideAdministration(id: "legacy-1", datetime: "2026-09-20T13:00:00Z", compound: "BPC-157", dose: 500, units: "mcg"),
            PeptideAdministration(id: "odd-1", datetime: "2026-09-20T14:00:00Z", compound: "BPC-157", dose: 500, units: "mcg", recordedVia: "import"),
        ]
        let store = makeStore(bridge)
        await store.refresh()
        for id in ["legacy-1", "odd-1"] {
            let entry = try #require(store.entries.first { $0.id == id })
            #expect(entry.syncState == .readOnly)
            #expect(!entry.isEditableInApp)
            #expect(store.correct(entry, reason: "typo", changes: PeptideCorrectionChanges(dose: 1)) == PeptideLogStore.unknownOriginMessage)
            #expect(store.void(entry, reason: "dup") == PeptideLogStore.unknownOriginMessage)
        }
        #expect(store.void(rowID: "legacy-1", recordedVia: nil, reason: "dup") == PeptideLogStore.unknownOriginMessage)
        #expect(store.pendingOps.isEmpty)
    }

    @Test func unreadableRowsRaiseAWarningAndBlockRemaining() async throws {
        let bridge = FakePeptideBridge()
        bridge.skippedPerWindow = 1
        let store = makeStore(bridge)
        let vial = PeptideVial(
            id: "v1",
            person: "jonathan",
            compound: "BPC-157",
            components: [PeptideVialComponent(name: "BPC-157", amount: 10, unit: "mg")],
            diluentML: 2,
            concentrationConfirmed: true
        )
        store.saveVial(vial)
        #expect(store.remaining(for: vial).calculable)
        await store.refresh()
        #expect(store.skippedRowCount > 0)
        #expect(!store.historyComplete)
        #expect(store.syncWarning != nil)
        let remaining = store.remaining(for: vial)
        #expect(!remaining.calculable)
        #expect(remaining.reason == PeptideMath.incompleteHistoryReason)
    }

    // MARK: History completeness

    private func bpcVial() -> PeptideVial {
        PeptideVial(
            id: "v-bpc",
            person: "jonathan",
            compound: "BPC-157",
            components: [PeptideVialComponent(name: "BPC-157", amount: 10, unit: "mg")],
            diluentML: 2,
            concentrationConfirmed: true
        )
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("peptide-log-test-\(UUID().uuidString).json")
    }

    @Test func remainingIsUncalculableWhileHistoryIsIncomplete() async throws {
        let bridge = FakePeptideBridge()
        let store = makeStore(bridge)
        let vial = bpcVial()
        store.saveVial(vial)
        var local = draft()
        local.vialID = vial.id
        _ = try #require(store.log(local))
        // Never synced and the only dose is on this phone: computed from it.
        #expect(!store.historyComplete)
        #expect(store.remaining(for: vial).calculable)

        await store.refresh()
        #expect(store.historyComplete)
        let full = store.remaining(for: vial)
        #expect(full.calculable)
        #expect(full.linkedCount == 1)

        // One window fails: incomplete until a full refresh succeeds again.
        bridge.failingWindow = 2
        await store.refresh()
        #expect(!store.historyComplete)
        let blocked = store.remaining(for: vial)
        #expect(!blocked.calculable)
        #expect(blocked.reason == PeptideMath.incompleteHistoryReason)

        bridge.failingWindow = nil
        await store.refresh()
        #expect(store.historyComplete)
        #expect(store.remaining(for: vial).calculable)
    }

    @Test func historyCompleteIsSavedAndOldSavesStartIncomplete() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = FakePeptideBridge()
        let store = PeptideLogStore(persistence: .file(url), client: bridge, autoFlush: false)
        await store.refresh()
        #expect(store.historyComplete)
        #expect(PeptideLogStore(persistence: .file(url), client: bridge, autoFlush: false).historyComplete)

        bridge.failingWindow = 0
        await store.refresh()
        #expect(!store.historyComplete)
        #expect(!PeptideLogStore(persistence: .file(url), client: bridge, autoFlush: false).historyComplete)

        // A save from before the flag existed reads as incomplete.
        let old = #"{"version":1,"rows":[],"pendingOps":[],"meta":[],"vials":[],"schedules":[],"lastSync":800000000}"#
        try Data(old.utf8).write(to: url)
        let upgraded = PeptideLogStore(persistence: .file(url), client: bridge, autoFlush: false)
        #expect(!upgraded.historyComplete)
        #expect(upgraded.lastSync != nil)
        let vial = bpcVial()
        upgraded.saveVial(vial)
        #expect(upgraded.remaining(for: vial).reason == PeptideMath.incompleteHistoryReason)

        bridge.failingWindow = nil
        await upgraded.refresh()
        #expect(upgraded.historyComplete)
        #expect(upgraded.remaining(for: vial).calculable)
    }

    // MARK: already_completed

    @Test func alreadyCompletedKeepsASavedOpUntilTheRowIsFound() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = FakePeptideBridge()
        bridge.createError = PeptideBridgeWriteError(status: 409, code: "already_completed", message: "already_completed")
        bridge.historyError = URLError(.notConnectedToInternet)
        let store = PeptideLogStore(persistence: .file(url), client: bridge, autoFlush: false)
        let crid = try #require(store.log(draft(), clientRequestID: "crid-ac"))
        await store.flush()
        let op = try #require(store.pendingOps.first)
        #expect(op.isReconciling)
        #expect(op.reconcileCause == PeptidePendingOp.causeAlreadyCompleted)
        #expect(!op.failed)
        #expect(store.entries.count == 1)

        // Saved: it survives a relaunch, and it isn't sent again while it waits.
        let relaunched = PeptideLogStore(persistence: .file(url), client: bridge, autoFlush: false)
        #expect(relaunched.pendingOps.first?.reconcileCause == PeptidePendingOp.causeAlreadyCompleted)
        await relaunched.flush()
        #expect(bridge.createCalls.count == 1)

        // History loads without the row: kept, visible as failed with why.
        bridge.historyError = nil
        await relaunched.refresh()
        #expect(relaunched.pendingOps.count == 1)
        #expect(relaunched.pendingOps.first?.failed == true)
        #expect(relaunched.pendingOps.first?.lastError == PeptideLogStore.alreadyCompletedMissingMessage)
        #expect(relaunched.entries.first?.syncState == .failed(PeptideLogStore.alreadyCompletedMissingMessage))

        // Removed meanwhile: once the row shows up, its void is queued and sent.
        let entry = try #require(relaunched.entries.first)
        #expect(relaunched.void(entry, reason: "Duplicate") == nil)
        #expect(relaunched.pendingOps.count == 1)
        bridge.history = [
            PeptideAdministration(
                id: "srv-ac",
                datetime: PeptideMath.iso8601NewYork(Date(timeIntervalSince1970: 1_790_000_000)),
                compound: "BPC-157",
                dose: 500,
                units: "mcg",
                recordedVia: "app",
                clientRequestID: crid
            ),
        ]
        await relaunched.refresh()
        #expect(bridge.voidCalls.count == 1)
        #expect(bridge.voidCalls.first?.rowID == "srv-ac")
        #expect(bridge.voidCalls.first?.reason == "Duplicate")
        #expect(relaunched.pendingOps.isEmpty)
        #expect(bridge.createCalls.count == 1)
    }

    @Test func alreadyCompletedPlannedDoseIsMatchedByPlannedID() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = PeptideBridgeWriteError(status: 409, code: "already_completed", message: "already_completed")
        bridge.history = [
            PeptideAdministration(
                id: "plan-1",
                datetime: "2026-09-20T13:00:00Z",
                compound: "Tesamorelin",
                dose: 1.4,
                units: "mg",
                status: "PLANNED",
                completedId: "done-1",
                recordedVia: "peptide-agent"
            ),
            PeptideAdministration(
                id: "done-1",
                datetime: "2026-09-20T13:05:00Z",
                compound: "Tesamorelin",
                dose: 1.4,
                units: "mg",
                plannedId: "plan-1",
                recordedVia: "peptide-agent"
            ),
        ]
        let store = makeStore(bridge)
        let takenAt = Date(timeIntervalSince1970: 1_790_000_000)
        store.logPlanned(plannedID: "plan-1", takenAt: takenAt, dose: nil, notes: nil, clientRequestID: "crid-plan-a")
        store.logPlanned(plannedID: "plan-1", takenAt: takenAt, dose: nil, notes: "Felt fine", clientRequestID: "crid-plan-b")
        await store.flush()

        // Nothing typed: the planned dose is taken, as asked.
        #expect(!store.isQueued("crid-plan-a"))
        // Notes typed: kept and explained; nothing is written to the assistant's row.
        let kept = try #require(store.pendingOps.first { $0.id == "crid-plan-b" })
        #expect(kept.failed)
        #expect(kept.lastError == PeptideLogStore.plannedTakenElsewhereMessage)
        #expect(bridge.correctCalls.isEmpty)
        #expect(bridge.voidCalls.isEmpty)

        store.discard(opID: "crid-plan-b")
        #expect(store.pendingOps.isEmpty)
        #expect(bridge.voidCalls.isEmpty)
    }

    // MARK: Ownership of follow-up writes

    @Test func reconciledEditsAreNotSentToARowTheAppDidNotRecord() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = PeptideBridgeWriteError(status: 409, code: "idempotency_key_conflict", message: "idempotency_key_conflict")
        bridge.history = [
            PeptideAdministration(
                id: "srv-x",
                datetime: PeptideMath.iso8601NewYork(Date(timeIntervalSince1970: 1_790_000_000)),
                compound: "BPC-157",
                dose: 300,
                units: "mcg",
                clientRequestID: "crid-own"
            ),
        ]
        let store = makeStore(bridge)
        _ = try #require(store.log(draft(), clientRequestID: "crid-own"))
        await store.flush()

        let op = try #require(store.pendingOps.first { $0.id == "crid-own" })
        #expect(op.failed)
        #expect(op.isReconciling)
        #expect(op.lastError?.contains(PeptideLogStore.unknownOriginMessage) == true)
        #expect(bridge.correctCalls.isEmpty)
        let entry = try #require(store.entries.first { $0.rowID == "srv-x" })
        #expect(entry.syncState.failureMessage != nil)
        #expect(entry.pendingOpID == "crid-own")

        // Discard leaves the bridge row as it is.
        store.discard(opID: "crid-own")
        #expect(store.pendingOps.isEmpty)
        #expect(bridge.correctCalls.isEmpty)
        #expect(bridge.voidCalls.isEmpty)
    }

    @Test func voidDuringPostIsNotSentForARowTheAssistantRecorded() async throws {
        let bridge = FakePeptideBridge()
        bridge.suspendCreates = true
        bridge.createRecordedVia = "peptide-agent"
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))
        let flushing = Task { await store.flush() }
        let started = await bridge.waitForSuspendedCreate()
        try #require(started)
        let entry = try #require(store.entries.first)
        #expect(store.void(entry, reason: "Wrong vial") == nil)

        bridge.suspendCreates = false
        bridge.resumeCreate()
        await flushing.value

        #expect(bridge.voidCalls.isEmpty)
        let op = try #require(store.pendingOps.first { $0.id == crid })
        #expect(op.failed)
        #expect(op.lastError?.contains(PeptideLogStore.readOnlyMessage) == true)
        #expect(store.entries.first?.syncState.failureMessage != nil)
    }

    // MARK: Refused cancelled creates

    @Test func refusedCancelledCreateWithNoEarlierSendIsRemoved() async throws {
        let bridge = FakePeptideBridge()
        bridge.suspendCreates = true
        bridge.createError = PeptideBridgeWriteError(status: 400, code: "invalid", message: "bad")
        let store = makeStore(bridge)
        _ = try #require(store.log(draft()))
        let flushing = Task { await store.flush() }
        let started = await bridge.waitForSuspendedCreate()
        try #require(started)
        let entry = try #require(store.entries.first)
        #expect(store.void(entry, reason: "Wrong vial") == nil)
        #expect(store.pendingOps.first?.cancelReason == "Wrong vial")

        bridge.suspendCreates = false
        bridge.resumeCreate()
        await flushing.value

        // The only send was refused: nothing reached the bridge.
        #expect(store.pendingOps.isEmpty)
        #expect(store.entries.isEmpty)
        #expect(bridge.historyCalls == 0)
    }

    @Test func refusedCancelledCreateAfterAnUncertainSendIsReconciled() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = URLError(.timedOut)
        let store = makeStore(bridge)
        let crid = try #require(store.log(draft()))
        await store.flush()
        let entry = try #require(store.entries.first)
        #expect(store.isCreateUncertain(entry))
        #expect(store.void(entry, reason: "Wrong vial") == nil)

        // The retry is refused and history can't be read: the cancellation is kept.
        bridge.createError = PeptideBridgeWriteError(status: 400, code: "invalid", message: "bad")
        bridge.historyError = URLError(.notConnectedToInternet)
        await store.flush()
        let op = try #require(store.pendingOps.first)
        #expect(op.cancelReason == "Wrong vial")
        #expect(op.isReconciling)
        #expect(op.reconcileCause == PeptidePendingOp.causeRejectedAfterUncertain)
        #expect(bridge.createCalls.count == 2)

        // The timed-out send had reached the bridge: that row is voided.
        bridge.historyError = nil
        bridge.history = [
            PeptideAdministration(
                id: "srv-u",
                datetime: PeptideMath.iso8601NewYork(Date(timeIntervalSince1970: 1_790_000_000)),
                compound: "BPC-157",
                dose: 500,
                units: "mcg",
                recordedVia: "app",
                clientRequestID: crid
            ),
        ]
        await store.refresh()
        #expect(bridge.voidCalls.count == 1)
        #expect(bridge.voidCalls.first?.rowID == "srv-u")
        #expect(bridge.voidCalls.first?.reason == "Wrong vial")
        #expect(store.pendingOps.isEmpty)
        #expect(bridge.createCalls.count == 2)
    }

    @Test func refusedCancelledCreateIsDroppedWhenFullHistoryHasNoRow() async throws {
        let bridge = FakePeptideBridge()
        bridge.createError = URLError(.timedOut)
        let store = makeStore(bridge)
        _ = try #require(store.log(draft()))
        await store.flush()
        let entry = try #require(store.entries.first)
        #expect(store.void(entry, reason: "Wrong vial") == nil)

        bridge.createError = PeptideBridgeWriteError(status: 400, code: "invalid", message: "bad")
        await store.flush()
        // A full refresh ran and has no row with this request id.
        #expect(store.historyComplete)
        #expect(store.pendingOps.isEmpty)
        #expect(store.entries.isEmpty)
        #expect(bridge.voidCalls.isEmpty)
    }
}

/// Scripted bridge. Records every write.
@MainActor
final class FakePeptideBridge: PeptideBridgeClient {
    var history: [PeptideAdministration] = []
    var historyError: Error?
    var createError: Error?
    var historyCalls = 0
    var historyWindows: [(from: String, to: String, limit: Int)] = []
    /// Unreadable rows reported per window.
    var skippedPerWindow = 0
    /// Extra rows returned only for the first window (to fill it to the limit).
    var firstWindowExtra: [PeptideAdministration] = []
    var todayCalls = 0
    var createCalls: [PeptideCreatePayload] = []
    var correctCalls: [(rowID: String, reason: String, changes: PeptideCorrectionChanges)] = []
    var voidCalls: [(rowID: String, reason: String)] = []
    /// When true, `create` waits until `resumeCreate()` (a POST in flight).
    var suspendCreates = false
    /// recorded_via on rows `create` returns.
    var createRecordedVia: String? = "app"
    /// Zero-based window (counted per refresh) that fails with `URLError(.timedOut)`.
    var failingWindow: Int?
    private var windowInRefresh = 0
    private var createContinuation: CheckedContinuation<Void, Never>?
    /// Tests waiting for a create to suspend, by token.
    private var suspendWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    nonisolated deinit {}

    var hasSuspendedCreate: Bool { createContinuation != nil }

    func resumeCreate() {
        let continuation = createContinuation
        createContinuation = nil
        continuation?.resume()
    }

    /// Handshake: returns true once `create` is suspended (immediately if it
    /// already is), or false after `seconds` so a test can't hang.
    func waitForSuspendedCreate(seconds: Double = 5) async -> Bool {
        if createContinuation != nil { return true }
        let token = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            suspendWaiters[token] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.finishWaiter(token, started: false)
            }
        }
    }

    private func finishWaiter(_ token: UUID, started: Bool) {
        guard let continuation = suspendWaiters.removeValue(forKey: token) else { return }
        continuation.resume(returning: started)
    }

    private func notifySuspended() {
        for token in Array(suspendWaiters.keys) {
            finishWaiter(token, started: true)
        }
    }

    /// Position of the window just recorded within its refresh: windows of
    /// one refresh are consecutive, a new refresh starts over.
    private func windowIndex(from: String) -> Int {
        let count = historyWindows.count
        let previous: (from: String, to: String, limit: Int)? = count >= 2 ? historyWindows[count - 2] : nil
        if let previous, ReconMath.addDays(previous.to, 1) == from {
            windowInRefresh += 1
        } else {
            windowInRefresh = 0
        }
        return windowInRefresh
    }

    func fetchAdministrations(from: String, to: String, limit: Int) async throws -> PeptideAdministrationList {
        historyCalls += 1
        let isFirst = historyWindows.isEmpty
        historyWindows.append((from: from, to: to, limit: limit))
        let index = windowIndex(from: from)
        if let historyError { throw historyError }
        if let failingWindow, failingWindow == index { throw URLError(.timedOut) }
        // Every window answers with the whole scripted history (tests don't
        // depend on the wall clock); the store merges by id.
        return PeptideAdministrationList(
            from: from,
            to: to,
            administrations: history + (isFirst ? firstWindowExtra : []),
            skippedRows: skippedPerWindow
        )
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
        if suspendCreates {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                createContinuation = continuation
                notifySuspended()
            }
        }
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
            recordedVia: createRecordedVia,
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
        history[index].updatedAt = "2026-09-20T14:00:00Z"
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
