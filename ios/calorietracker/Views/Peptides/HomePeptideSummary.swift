//
//  HomePeptideSummary.swift
//  calorietracker
//
//  Extra lines for the Home peptide card from the Peptides log: today's
//  unsynced app logs, what the user's own schedules list as due, and low stock.
//  Synced rows already show in the card from /api/peptides/today.
//

import SwiftUI

struct HomePeptideSummary: View {
    @Environment(PeptideLogStore.self) private var store
    let day: String

    static func hasContent(store: PeptideLogStore, day: String) -> Bool {
        !unsynced(store: store, day: day).isEmpty
            || !dueItems(store: store, day: day).isEmpty
            || !store.lowStockVials(person: nil).isEmpty
    }

    private static func unsynced(store: PeptideLogStore, day: String) -> [PeptideLogEntry] {
        store.entries.filter {
            $0.isCompleted && $0.civilDate == day && ($0.syncState.isPending || $0.syncState.failureMessage != nil)
        }
    }

    private static func dueItems(store: PeptideLogStore, day: String) -> [(person: String, item: PeptideMath.DueItem)] {
        var result: [(person: String, item: PeptideMath.DueItem)] = []
        for person in PeptidePerson.order {
            let items = PeptideMath.dueItems(date: day, person: person, schedules: store.schedules, entries: store.entries)
            for item in items where !item.taken {
                result.append((person: person, item: item))
            }
        }
        return result
    }

    var body: some View {
        let unsynced = Self.unsynced(store: store, day: day)
        let due = Self.dueItems(store: store, day: day)
        let low = store.lowStockVials(person: nil)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(PeptidePerson.order, id: \.self) { person in
                let rows = unsynced.filter { PeptidePerson.normalized($0.person) == person }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        PeptideFieldLabel(PeptidePerson.name(person) + " · logged in the app")
                        ForEach(rows) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(entry.compound + " · " + PeptideMath.amountText(entry.dose, entry.units))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(IronTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                PeptideSyncChip(state: entry.syncState)
                            }
                        }
                    }
                }
            }
            if !due.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    PeptideFieldLabel("Due today (your schedules)")
                    ForEach(due, id: \.item.id) { pair in
                        Text(PeptidePerson.name(pair.person) + " · " + pair.item.schedule.compound + " · " + PeptideMath.frequencyText(pair.item.schedule.frequency))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(IronTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !low.isEmpty {
                Text("Low stock: " + low.map { $0.displayName + " (" + PeptidePerson.name($0.person) + ")" }.joined(separator: ", "))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
