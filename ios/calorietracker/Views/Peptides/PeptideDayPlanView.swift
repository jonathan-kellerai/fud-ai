//
//  PeptideDayPlanView.swift
//  calorietracker
//
//  One day's plan in the two fixed slots, AM then PM. A reminder sits first
//  in its slot; each planned dose is its own row, logged with one tap at the
//  dose the user planned, and edited afterwards with a reason. The app
//  suggests no dose: every amount here is one the user saved.
//

import SwiftUI

struct PeptideDayPlanView: View {
    @Environment(PeptideLogStore.self) private var store
    let plan: PeptideDayPlan
    /// Doses can be logged with one tap (today only; another day uses the log sheet).
    var canLog: Bool
    /// Fixed "now" (Visual QA). Nil logs at the live time.
    var referenceDate: Date?
    /// Opens the log sheet on a compound, for a schedule with no planned dose.
    var onLog: ((String) -> Void)?
    var onEditReminder: ((PeptideReminder) -> Void)?
    @State private var refusal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(plan.slots) { slot in
                slotCard(slot)
            }
            if let refusal {
                PeptideIssueText(text: refusal)
            }
        }
    }

    private func slotCard(_ slot: PeptideDayPlan.Slot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PeptideFieldLabel(slot.slot.label)
                .accessibilityLabel(slot.slot.spokenLabel)
                .accessibilityAddTraits(.isHeader)
            if slot.items.isEmpty {
                Text("Nothing planned.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            ForEach(slot.items) { item in
                switch item {
                case .reminder(let reminder):
                    reminderRow(reminder)
                case .dose(let due):
                    doseRow(due)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .peptideAccentCard(slot.slot == .am ? IronTheme.brass : IronTheme.olive)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peptides.plan." + slot.slot.rawValue)
    }

    private func reminderRow(_ reminder: PeptideReminder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(reminder.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bell")
                    .foregroundStyle(IronTheme.brass)
            }
            Text(reminder.timeText)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
            PeptideFlowLayout(spacing: 8) {
                if let onEditReminder {
                    Button("Edit") { onEditReminder(reminder) }
                        .buttonStyle(IronCompactButtonStyle())
                        .accessibilityLabel("Edit reminder")
                }
                Button("Dismiss") {
                    refusal = store.setReminderDismissed(id: reminder.id, dismissed: true)
                }
                .buttonStyle(IronCompactButtonStyle())
                .accessibilityLabel("Dismiss reminder")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func doseRow(_ due: PeptideMath.DueItem) -> some View {
        let schedule = due.schedule
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(schedule.compound)
                    .font(.system(.headline, design: .default, weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if PeptideCompoundCatalog.isPrescription(schedule.compound) {
                    PeptideTag(text: "Prescription", tone: IronTheme.brass)
                }
            }
            Text(PeptideMath.plannedDoseText(schedule, vial: store.plannedVial(for: schedule.compound)))
                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            doseAction(due)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func doseAction(_ due: PeptideMath.DueItem) -> some View {
        if let entry = due.entry {
            HStack(spacing: 10) {
                Label("Logged " + (entry.date.map(PeptideMath.timeText) ?? ""), systemImage: "checkmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.olive)
                NavigationLink("Edit") {
                    PeptideEntryDetailView(entryID: entry.id)
                }
                .buttonStyle(IronCompactButtonStyle())
                .accessibilityLabel("Edit the logged " + due.schedule.compound)
            }
        } else if canLog {
            if due.schedule.dose != nil {
                Button("Taken") {
                    if store.logPlanned(scheduleID: due.schedule.id, now: referenceDate ?? Date()) == nil {
                        refusal = store.changeRefusal ?? store.persistError ?? "This dose couldn't be saved."
                    } else {
                        refusal = nil
                    }
                }
                .buttonStyle(IronCompactButtonStyle())
                .accessibilityLabel("Mark " + due.schedule.compound + " taken")
                .accessibilityIdentifier("peptides.plan.taken." + due.schedule.id)
            } else if let onLog {
                Button("Log") { onLog(due.schedule.compound) }
                    .buttonStyle(IronCompactButtonStyle())
                    .accessibilityLabel("Log a draw of " + due.schedule.compound)
            }
        } else {
            Text("Not logged")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
        }
    }
}
