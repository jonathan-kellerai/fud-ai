import Foundation

/// Recon Bench's old save. Build 68 folded Recon Bench into Reconstitute
/// (ReconView). At launch the mixes the user typed there move into Peptides
/// once (`ReconBenchMigration`); Delete Everything removes what's left.
enum ReconBenchStore {
    static let defaultsKey = "recon.bench.v1"

    static var fileURL: URL? {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
            .appendingPathComponent("Library/Application Support/ReconBench", isDirectory: true) else { return nil }
        return directory.appendingPathComponent("recon_bench_v1.json")
    }

    /// The saved bench: the file, else its UserDefaults copy.
    static func savedData(file: URL? = ReconBenchStore.fileURL, defaults: UserDefaults = .standard) -> Data? {
        if let file, let data = try? Data(contentsOf: file) { return data }
        return defaults.data(forKey: defaultsKey)
    }

    /// Launch: the bench's mixes join `peptides` as unconfirmed vials. The old
    /// save is removed only once its untouched bytes are kept next to the
    /// peptide log and the vials are saved. A save with no mixes the user
    /// typed (only plans and calculator figures) is left as it is.
    static func moveMixes(
        into peptides: PeptideLogStore,
        file: URL? = ReconBenchStore.fileURL,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard let data = savedData(file: file, defaults: defaults) else { return }
        guard peptides.adoptReconBench(data, now: now) else { return }
        deleteSavedData(file: file, defaults: defaults)
    }

    /// Delete Everything: the saved bench file and its UserDefaults copy.
    static func deleteSavedData(file: URL? = ReconBenchStore.fileURL, defaults: UserDefaults = .standard) {
        if let file {
            try? FileManager.default.removeItem(at: file)
        }
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Recon Bench's save, read only to move the mixes the user typed into Vials.
///
/// A save holds, per profile, a card per compound (`cards`), dose plans
/// (`entries`) and ticks for planned doses (`taken`). A card is calculator
/// state: a vial amount and diluent (the mix), plus a dose, draw, doses per
/// week and an on-hand amount. Only the mix moves, as an unconfirmed vial with
/// no dose or plan field, and only where the user changed the catalog's
/// numbers: the bench saved every card, and an untouched one is the catalog's
/// example, not the user's vial. Recon Bench had no mixed date. Plans and
/// ticks are plans, not records of draws, so they aren't moved; they stay in
/// the copy of the save kept next to the peptide log.
enum ReconBenchMigration {
    static let note = "Moved from Recon Bench. Check the amount and diluent, then confirm the mix in Reconstitute."

    /// The vials to move: the user's own, and the second profile's to hold
    /// aside. Nil when the bytes aren't a Recon Bench save.
    static func vials(from data: Data, now: Date) -> PeptideRecordsByProfile? {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        var records = PeptideRecordsByProfile()
        for profileKey in saved.cards.keys.sorted() {
            let profile = PeptideLegacyProfile(raw: profileKey)
            let cards = saved.cards[profileKey] ?? [:]
            for key in cards.keys.sorted() {
                guard let card = cards[key]?.value, let vial = vial(from: card, key: key, profile: profile, now: now) else { continue }
                if profile == .second {
                    records.heldAside.vials.append(vial)
                } else {
                    records.own.vials.append(vial)
                }
            }
        }
        return records
    }

    /// The card's mix as an unconfirmed vial, or nil when it has none or
    /// it's the catalog's. Same id every time, so moving twice adds one vial.
    private static func vial(from card: ReconMath.Card, key: String, profile: PeptideLegacyProfile, now: Date) -> PeptideVial? {
        let amount: Double? = card.vial.isFinite && card.vial > 0 ? card.vial : nil
        let diluent: Double? = card.water.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard amount != nil || diluent != nil else { return nil }
        let catalog = ReconMath.defaultCard(key: key)
        guard !same(card.vial, catalog.vial) || !same(card.water, catalog.water) else { return nil }
        let compound = ReconMath.compound(key)
        let name = compound?.name ?? key
        let id = (profile == .second ? "recon-bench-second-" : "recon-bench-") + key
        var components: [PeptideVialComponent] = []
        if let amount {
            components.append(PeptideVialComponent(id: id + "-amount", name: name, amount: amount, unit: compound?.vialUnit ?? "mg"))
        }
        return PeptideVial(
            id: id,
            compound: name,
            components: components,
            diluentML: diluent,
            concentrationConfirmed: false,
            notes: note,
            createdAt: now
        )
    }

    private static func same(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return abs(left - right) <= ReconMath.epsilon
        default: return false
        }
    }

    private struct Saved: Decodable {
        var cards: [String: [String: PeptideLossy<ReconMath.Card>]]
    }
}
