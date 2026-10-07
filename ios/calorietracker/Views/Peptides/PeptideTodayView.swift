//
//  PeptideTodayView.swift
//  calorietracker
//
//  Peptides › Today: today's draws as cards, like finished sets, and one
//  full-width "Log a draw" button in the scroll (no floating +). Draws show
//  in units or mL as typed. Never mg.
//

import SwiftUI

struct PeptideTodayView: View {
    @Environment(PeptideLogStore.self) private var store
    /// yyyy-MM-dd, America/New_York.
    let today: String
    /// Opens the log sheet, optionally on a compound (from the user's schedule).
    let onLog: (String?) -> Void

    var body: some View {
        let entries = store.dayEntries(today, includeVoided: false)
        let due = PeptideMath.dueItems(date: today, schedules: store.schedules, entries: store.entries)
        VStack(alignment: .leading, spacing: 12) {
            PeptideHeader(text: "Today · " + ReconMath.formatDateShort(today))
            if entries.isEmpty {
                Text("Nothing logged today.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .peptideAccentCard(IronTheme.concrete)
            }
            ForEach(entries) { entry in
                NavigationLink {
                    PeptideEntryDetailView(entryID: entry.id)
                } label: {
                    PeptideRecordCard(entry: entry, vialName: vialName(entry))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the draw")
            }
            Button {
                onLog(nil)
            } label: {
                Label("Log a draw", systemImage: "plus")
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .accessibilityIdentifier("peptides.today.log")
            Text("Records what you enter. Suggests no doses.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !due.isEmpty {
                dueSection(due)
            }
        }
    }

    /// "BPC-157 · mixed 26 Sep" for a linked vial.
    private func vialName(_ entry: PeptideLogEntry) -> String? {
        guard let vial = store.vial(id: entry.vialID) else { return nil }
        guard let mixed = vial.mixedOn, let parts = ReconMath.parseISO(mixed) else { return vial.displayName }
        return vial.displayName + " · mixed \(parts.day) \(ReconMath.monthShort[parts.month - 1])"
    }

    /// What the user's own schedules list for today. Plain text, no targets.
    private func dueSection(_ items: [PeptideMath.DueItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Your schedules today")
            ForEach(items) { item in
                AdaptiveLabelValue {
                    Text(item.schedule.compound)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } value: {
                    if item.taken {
                        Text("Logged")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                    } else {
                        Button("Log") { onLog(item.schedule.compound) }
                            .buttonStyle(IronCompactButtonStyle())
                            .accessibilityLabel("Log a draw of " + item.schedule.compound)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .peptideAccentCard(IronTheme.brass)
    }
}
