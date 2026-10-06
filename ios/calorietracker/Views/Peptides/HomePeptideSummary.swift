//
//  HomePeptideSummary.swift
//  calorietracker
//
//  The Home peptide card from the Peptides log on this phone: today's doses,
//  what the user's own schedules list as due, and low stock.
//

import SwiftUI

struct HomePeptideSummary: View {
    @Environment(PeptideLogStore.self) private var store
    let day: String

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
        let logs = store.takenEntries(on: day)
        let due = Self.dueItems(store: store, day: day)
        let low = store.lowStockVials(person: nil)
        return VStack(alignment: .leading, spacing: 8) {
            if logs.isEmpty {
                Text("Nothing logged today.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(PeptidePerson.order, id: \.self) { person in
                let rows = logs.filter { PeptidePerson.normalized($0.person) == person }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        PeptideFieldLabel(PeptidePerson.name(person) + " · logged today")
                        ForEach(rows) { entry in
                            Text(entry.compound + " · " + PeptideMath.amountText(entry.dose, entry.units))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(IronTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
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
