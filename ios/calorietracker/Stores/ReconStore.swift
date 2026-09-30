import Foundation

/// Local Recon Bench state. Syringe units are not stored; screens recompute them with ReconMath.
/// Bridge sync is off unless the operator turns the flag on.
@Observable
final class ReconBenchStore {
    private(set) var cards: [String: [String: ReconMath.Card]]
    private(set) var entries: [ReconMath.ScheduleEntry]
    private(set) var taken: [String: Bool]
    var bridgeSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(bridgeSyncEnabled, forKey: Self.bridgeKey) }
    }
    var syncNotice: String?

    init() {
        let loaded = Self.load()
        cards = loaded.cards
        entries = loaded.entries
        taken = loaded.taken
        bridgeSyncEnabled = UserDefaults.standard.bool(forKey: Self.bridgeKey)
    }

    /// Explicit nonisolated deinit: the synthesized main-actor-isolated deinit
    /// double-frees a TaskLocal scope on iOS <= 26.2 (swiftlang/swift#88036)
    /// when the store is released inside a task-local context.
    nonisolated deinit {}

    func card(person: String, key: String) -> ReconMath.Card {
        cards[person]?[key] ?? ReconMath.defaultCard(person: person, key: key)
    }

    func updateCard(person: String, key: String, _ mutate: (inout ReconMath.Card) -> Void) {
        var next = card(person: person, key: key)
        mutate(&next)
        var personCards = cards[person] ?? [:]
        personCards[key] = next
        cards[person] = personCards
        persist()
    }

    func reset(person: String) {
        var personCards = cards[person] ?? [:]
        for key in ReconMath.roster[person] ?? [] {
            personCards[key] = ReconMath.defaultCard(person: person, key: key)
        }
        cards[person] = personCards
        persist()
    }

    func config(person: String, key: String) -> ReconMath.VialConfig {
        ReconMath.config(for: card(person: person, key: key), key: key)
    }

    func onHand(person: String, key: String) -> Double? {
        if cards[person]?[key] != nil { return cards[person]?[key]?.onHand }
        return ReconMath.onHandDefault[person]?[key]
    }

    func calculatorOnHand(key: String) -> (value: Double?, source: String) {
        if cards["jonathan"]?[key] != nil {
            return (cards["jonathan"]?[key]?.onHand, "Jonathan's inventory")
        }
        if cards["victoria"]?[key] != nil {
            return (cards["victoria"]?[key]?.onHand, "Victoria's inventory")
        }
        return (ReconMath.onHandDefault["calc"]?[key], "inventory")
    }

    func add(_ entry: ReconMath.ScheduleEntry) {
        guard ReconMath.roster[entry.person]?.contains(entry.compound) == true else { return }
        entries.append(entry)
        persist()
    }

    func delete(id: String) {
        entries.removeAll { $0.id == id }
        taken = taken.filter { !$0.key.hasPrefix(id + "|") }
        persist()
    }

    func isTaken(_ occurrence: ReconMath.Occurrence) -> Bool {
        taken[takenKey(occurrence)] == true
    }

    func toggleTaken(_ occurrence: ReconMath.Occurrence) {
        let key = takenKey(occurrence)
        let markingTaken = taken[key] != true
        if markingTaken {
            taken[key] = true
        } else {
            taken[key] = nil
        }
        persist()
        guard ReconMath.shouldSyncTakenToBridge(syncEnabled: bridgeSyncEnabled, markingTaken: markingTaken) else { return }
        let posted = occurrence
        Task { await postTaken(posted, clientRequestID: "recon-" + key) }
    }

    func takenKey(_ occurrence: ReconMath.Occurrence) -> String {
        occurrence.entry.id + "|" + occurrence.date
    }

    private func postTaken(_ occurrence: ReconMath.Occurrence, clientRequestID: String) async {
        let compound = ReconMath.compounds[occurrence.entry.compound]
        let dose: Double?
        let units: String?
        if compound?.blend.isEmpty == false {
            dose = occurrence.entry.draw
            units = "units"
        } else {
            dose = occurrence.entry.dose
            units = occurrence.entry.doseUnit
        }
        do {
            _ = try await NeonBridgeService.shared.createCompletedAdministration(
                clientRequestID: clientRequestID,
                plannedID: nil,
                datetime: occurrence.date + "T12:00:00Z",
                dose: dose,
                units: units,
                compound: compound?.name,
                route: nil,
                notes: "Logged from Recon Bench.",
                sourceVial: nil
            )
            syncNotice = nil
        } catch let error as NeonBridgeError where error.isAlreadyCompleted {
            syncNotice = nil
        } catch {
            syncNotice = error.localizedDescription
        }
    }

    private func persist() {
        let snapshot = Snapshot(cards: cards, entries: entries, taken: taken)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = Self.fileURL {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func load() -> Snapshot {
        let data = fileData() ?? UserDefaults.standard.data(forKey: defaultsKey)
        let saved = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        var cards = ReconMath.defaultCards()
        if let saved {
            for person in ReconMath.peopleOrder {
                for key in ReconMath.roster[person] ?? [] {
                    if let card = saved.cards[person]?[key] {
                        cards[person]?[key] = card
                    }
                }
            }
        }
        let entries = (saved?.entries ?? []).filter { entry in
            ReconMath.compounds[entry.compound] != nil && ReconMath.roster[entry.person]?.contains(entry.compound) == true
        }
        return Snapshot(cards: cards, entries: entries, taken: saved?.taken ?? [:])
    }

    private static func fileData() -> Data? {
        guard let url = fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static var fileURL: URL? {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
            .appendingPathComponent("Library/Application Support/ReconBench", isDirectory: true) else { return nil }
        return directory.appendingPathComponent("recon_bench_v1.json")
    }

    static let defaultsKey = "recon.bench.v1"
    static let bridgeKey = "recon.bridgeSyncEnabled"

    private struct Snapshot: Codable {
        var cards: [String: [String: ReconMath.Card]]
        var entries: [ReconMath.ScheduleEntry]
        var taken: [String: Bool]
    }
}
