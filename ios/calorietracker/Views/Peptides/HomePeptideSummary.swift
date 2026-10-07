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

    var body: some View {
        let logs = store.takenEntries(on: day)
        let due = PeptideMath.dueItems(date: day, schedules: store.schedules, entries: store.entries).filter { !$0.taken }
        let low = store.lowStockVials()
        return VStack(alignment: .leading, spacing: 8) {
            if logs.isEmpty {
                Text("Nothing logged today.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    PeptideFieldLabel("Logged today")
                    ForEach(logs) { entry in
                        Text(entry.compound + " · " + (entry.drawText ?? "draw not recorded"))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(IronTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !due.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    PeptideFieldLabel("Due today (your schedules)")
                    ForEach(due) { item in
                        Text(item.schedule.compound + " · " + PeptideMath.frequencyText(item.schedule.frequency))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(IronTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !low.isEmpty {
                Text("Low stock: " + low.map(\.displayName).joined(separator: ", "))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
