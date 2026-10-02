//
//  HomePeptideSummary.swift
//  calorietracker
//
//  Extra lines for the Home peptide card from the Peptides log: today's app
//  logs (pending and synced) that /api/peptides/today hasn't returned yet,
//  what the user's own schedules list as due, and low stock.
//

import SwiftUI

struct HomePeptideSummary: View {
    @Environment(PeptideLogStore.self) private var store
    let day: String
    /// Ids and client_request_ids the card already shows from /today.
    var shownKeys: Set<String> = []

    static func shownKeys(_ today: PeptideTodayResponse?) -> Set<String> {
        guard let today else { return [] }
        var keys = Set<String>()
        for row in today.completed {
            if !row.id.isEmpty { keys.insert(row.id) }
            if let crid = row.clientRequestID, !crid.isEmpty { keys.insert(crid.lowercased()) }
        }
        return keys
    }

    static func hasContent(store: PeptideLogStore, day: String, shownKeys: Set<String>) -> Bool {
        !appLogs(store: store, day: day, shownKeys: shownKeys).isEmpty
            || !dueItems(store: store, day: day).isEmpty
            || !store.lowStockVials(person: nil).isEmpty
    }

    /// App-logged doses for `day` from the merged log (pending + synced),
    /// minus the ones the card already shows from /today.
    static func appLogs(store: PeptideLogStore, day: String, shownKeys: Set<String>) -> [PeptideLogEntry] {
        store.entries.filter { entry in
            guard entry.isCompleted, !entry.voided, entry.civilDate == day else { return false }
            guard entry.isPendingCreate || entry.recordedVia == "app" else { return false }
            if let rowID = entry.rowID, shownKeys.contains(rowID) { return false }
            if let crid = entry.clientRequestID, shownKeys.contains(crid.lowercased()) { return false }
            return true
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
        let logs = Self.appLogs(store: store, day: day, shownKeys: shownKeys)
        let due = Self.dueItems(store: store, day: day)
        let low = store.lowStockVials(person: nil)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(PeptidePerson.order, id: \.self) { person in
                let rows = logs.filter { PeptidePerson.normalized($0.person) == person }
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
