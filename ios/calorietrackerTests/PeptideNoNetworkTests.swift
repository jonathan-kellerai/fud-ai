import Foundation
import Testing
@testable import calorietracker

/// Peptides make no network request at all, with no bridge key configured.
///
/// Why a stub transport: the app reaches the network through URLSession.shared,
/// so a URLProtocol registered for the test's duration is the only way to
/// prove "no request" without adding hooks to production code. It records
/// every request (no host exemptions) and fails it. A control request proves
/// it is in the path before the flows run. CI runs suites serially in one
/// process (-parallel-testing-enabled NO) and this suite is `.serialized`, so
/// no other suite's requests can land in the log while it is registered.
@MainActor
@Suite(.serialized)
struct PeptideNoNetworkTests {
    private func draft(compound: String = "BPC-157", amount: String = "500", units: String = "mcg") -> PeptideLogDraft {
        var draft = PeptideLogDraft.new(person: "jonathan", compound: compound, now: Date(timeIntervalSince1970: 1_790_000_000))
        draft.amountText = amount
        draft.units = units
        return draft
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-no-network-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
    }

    /// Registers the tripwire with no bridge key, proves it intercepts, runs
    /// `flows`, lets stray tasks run, then returns every request it saw.
    private func requests(during flows: () async throws -> Void) async throws -> [String] {
        let service = NeonBridgeService.shared
        let savedSettings = service.settings
        service.settings = NeonBridgeSettings(baseURL: NeonBridgeSettings.defaultBaseURL, apiKey: nil)
        URLProtocol.registerClass(PeptideNetworkTripwire.self)
        defer {
            URLProtocol.unregisterClass(PeptideNetworkTripwire.self)
            service.settings = savedSettings
            PeptideNetworkTripwire.log.reset()
        }
        PeptideNetworkTripwire.log.reset()

        let control = try #require(URL(string: "https://peptide-tripwire-control.invalid/ping"))
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(from: control)
        }
        #expect(PeptideNetworkTripwire.log.snapshot() == ["GET peptide-tripwire-control.invalid/ping"])
        PeptideNetworkTripwire.log.reset()

        try await flows()
        // Anything a flow left running in the background gets its chance to call out.
        try await Task.sleep(for: .milliseconds(500))
        await Task.yield()
        return PeptideNetworkTripwire.log.snapshot()
    }

    @Test func loggingEditingAndVoidingStayOnThePhone() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = try await requests {
            let store = PeptideLogStore(persistence: .file(url))
            let vial = PeptideVial(
                id: "v1",
                person: "jonathan",
                compound: "BPC-157",
                components: [PeptideVialComponent(name: "BPC-157", amount: 10, unit: "mg")],
                diluentML: 2,
                concentrationConfirmed: true
            )
            store.saveVial(vial)
            var typed = draft()
            typed.vialID = vial.id
            let id = try #require(store.log(typed))
            let entry = try #require(store.entry(id: id))
            #expect(store.correct(entry, reason: "Typo", changes: PeptideCorrectionChanges(dose: 250)) == nil)
            store.updateLocalDetails(for: try #require(store.entry(id: id)), vialID: vial.id, drawnVolume: 5, drawnUnit: "units")
            #expect(store.void(try #require(store.entry(id: id)), reason: "Duplicate") == nil)
            _ = store.log(draft(compound: "MT2", amount: "250"))
            #expect(store.remaining(for: vial).calculable)
            store.finishVial(id: vial.id)
            store.deleteVial(id: vial.id)
            let schedule = PeptideUserSchedule(id: "s1", person: "jonathan", compound: "BPC-157", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-09-01")
            store.saveSchedule(schedule)
            store.setScheduleActive(id: "s1", active: false)
            store.deleteSchedule(id: "s1")
            #expect(store.persistError == nil)
        }
        #expect(seen.isEmpty, "Peptide requests: \(seen)")
    }

    @Test func homeCardInputsAndPersonToggleStayOnThePhone() async throws {
        let seen = try await requests {
            let store = PeptideLogStore(persistence: .inMemory)
            store.saveSchedule(PeptideUserSchedule(id: "s1", person: "victoria", compound: "MT2", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-09-01"))
            _ = store.log(draft())
            let day = PeptideMath.civilDate(Date(timeIntervalSince1970: 1_790_000_000))
            #expect(store.hasLocalActivity(today: day))
            #expect(store.takenEntries(on: day).count == 1)
            _ = store.lowStockVials(person: nil)
            #expect(!PeptideMath.dueItems(date: day, person: "victoria", schedules: store.schedules, entries: store.entries).isEmpty)

            let savedPerson = UserDefaults.standard.object(forKey: PeptideLogStore.personKey)
            defer { UserDefaults.standard.set(savedPerson, forKey: PeptideLogStore.personKey) }
            PeptidePersonMemory.save("victoria")
            #expect(PeptidePersonMemory.load() == "victoria")
        }
        #expect(seen.isEmpty, "Peptide requests: \(seen)")
    }

    @Test func migratingAVersion1LogStaysOnThePhone() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let version1 = """
        {"version":1,"rows":[{"id":"r1","datetime":"2026-09-20T07:30:00-04:00","compound":"BPC-157","dose":500,"units":"mcg",
          "status":"COMPLETED","recorded_via":"app","client_request_id":"c1","voided":false}],
         "pendingOps":[{"id":"c2","kind":"create","create":{"clientRequestID":"c2","datetime":"2026-09-21T07:30:00-04:00",
          "dose":250,"units":"mcg","compound":"MT2"},"attempts":4,"failed":false,"createdAt":800000000}],
         "meta":[],"vials":[],"schedules":[]}
        """
        try Data(version1.utf8).write(to: url)
        let seen = try await requests {
            let store = PeptideLogStore(persistence: .file(url))
            #expect(store.entries.map(\.id) == ["r1", "c2"])
            let relaunched = PeptideLogStore(persistence: .file(url))
            #expect(relaunched.entries == store.entries)
        }
        #expect(seen.isEmpty, "Peptide requests: \(seen)")
    }

    @Test func reconBenchTakenMarkStaysOnThePhone() async throws {
        let seen = try await requests {
            let store = ReconBenchStore()
            let entry = ReconMath.ScheduleEntry(
                id: "tripwire-\(UUID().uuidString)", person: "jonathan", compound: "tesamorelin",
                dose: 1.4, doseUnit: "mg", draw: nil,
                freq: ReconMath.Frequency(type: "daily"), start: "2026-09-01", weeks: 1
            )
            let occurrence = ReconMath.Occurrence(
                date: "2026-09-01", dayNumber: 1, index: 0, entry: entry, entryIndex: 0,
                info: ReconMath.DoseInfo(), poolKey: "", status: "", flags: [], duplicate: false, cumulativeN: 0
            )
            store.toggleTaken(occurrence)
            #expect(store.isTaken(occurrence))
            // Unmark so the bench is left as it was.
            store.toggleTaken(occurrence)
            #expect(!store.isTaken(occurrence))
        }
        #expect(seen.isEmpty, "Peptide requests: \(seen)")
    }
}

/// Lock-protected record of what the tripwire saw (URLSession calls
/// `startLoading` off the main actor).
nonisolated final class PeptideNetworkRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String] = []

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append("\(request.httpMethod ?? "GET") \(request.url?.host ?? "")\(request.url?.path ?? "")")
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        requests = []
    }
}

/// Intercepts every request while registered, records it and fails it.
/// URLProtocol requires restating inherited unchecked Sendable: this subclass
/// adds no mutable instance state, and its shared log is lock-protected above.
nonisolated final class PeptideNetworkTripwire: URLProtocol, @unchecked Sendable {
    static let log = PeptideNetworkRequestLog()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log.record(request)
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
