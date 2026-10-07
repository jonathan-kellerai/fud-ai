//
//  HomePeptideSummary.swift
//  calorietracker
//
//  The Home peptide card's one line, from the Peptides log on this phone:
//  draws today, what the user's own schedules still list, and low vials.
//  Counts only: never an amount, never mg.
//

import SwiftUI

struct HomePeptideSummary: View {
    @Environment(PeptideLogStore.self) private var store
    let day: String

    var body: some View {
        let draws = store.takenEntries(on: day).count
        let dueLeft = PeptideMath.dueItems(date: day, schedules: store.schedules, entries: store.entries).filter { !$0.taken }.count
        let low = store.lowStockVials().count
        Text(PeptideMath.homeSummaryText(drawsToday: draws, dueLeft: dueLeft, lowVials: low))
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(IronTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Peptides: " + PeptideMath.homeSummaryText(drawsToday: draws, dueLeft: dueLeft, lowVials: low))
    }
}
