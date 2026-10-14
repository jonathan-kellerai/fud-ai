//
//  PeptideTodayView.swift
//  calorietracker
//
//  Peptides › Today: today's AM and PM plan (the lab reminder above that
//  morning's doses, one tap per planned dose), today's draws as cards, and
//  one full-width "Log a draw" button. Draws show as typed; no mg is worked out.
//

import SwiftUI

struct PeptideTodayView: View {
    @Environment(PeptideLogStore.self) private var store
    /// yyyy-MM-dd, America/New_York.
    let today: String
    /// Fixed "now" (Visual QA): one-tap doses log at it.
    var referenceDate: Date? = nil
    /// Opens the log sheet, optionally on a compound (from the user's schedule).
    let onLog: (String?) -> Void
    @State private var reminderTarget: PeptideReminderEditorTarget?

    var body: some View {
        let entries = store.dayEntries(today, includeVoided: false)
        let plan = store.dayPlan(today)
        VStack(alignment: .leading, spacing: 12) {
            PeptideHeader(text: "Today · " + ReconMath.formatDateShort(today))
            if !plan.isEmpty {
                PeptideDayPlanView(
                    plan: plan,
                    canLog: true,
                    referenceDate: referenceDate,
                    onLog: { onLog($0) },
                    onEditReminder: { reminderTarget = PeptideReminderEditorTarget(reminder: $0) }
                )
            }
            PeptideFieldLabel("Logged today")
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
        }
        .sheet(item: $reminderTarget) { target in
            PeptideReminderEditor(reminder: target.reminder)
        }
    }

    /// "BPC-157 · mixed 26 Sep" for a linked vial.
    private func vialName(_ entry: PeptideLogEntry) -> String? {
        guard let vial = store.vial(id: entry.vialID) else { return nil }
        guard let mixed = vial.mixedOn, let parts = ReconMath.parseISO(mixed) else { return vial.displayName }
        return vial.displayName + " · mixed \(parts.day) \(ReconMath.monthShort[parts.month - 1])"
    }
}
