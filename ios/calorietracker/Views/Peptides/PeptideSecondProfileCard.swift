//
//  PeptideSecondProfileCard.swift
//  calorietracker
//
//  The one-time choice for records an earlier version kept under a second
//  profile. Until the user picks, they stay saved on this phone (and in the
//  backup) and out of the log. Names no one.
//

import SwiftUI

struct PeptideSecondProfileCard: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var confirmingDelete = false

    var body: some View {
        let records = store.heldAside
        VStack(alignment: .leading, spacing: 12) {
            Text("Records from a second profile were found")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("An earlier version kept \(Self.countText(records)) under a second profile. Peptides now track only the person who uses this phone. Nothing has been changed: they're saved here, but not in your log, until you choose.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Keep them in my log") { store.keepHeldAside() }
                .buttonStyle(IronPrimaryButtonStyle())
                .accessibilityHint("Adds these records to your peptide log.")
            Button("Delete them") { confirmingDelete = true }
                .buttonStyle(PeptideSecondaryButtonStyle())
                .accessibilityHint("Asks before removing these records from this phone.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: true)
        .accessibilityIdentifier("peptides.secondProfile")
        .confirmationDialog(
            "Delete these records?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete them", role: .destructive) { store.deleteHeldAside() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(Self.countText(records)) from this phone. It can't be undone.")
        }
    }

    /// "3 doses, 1 vial and 1 schedule".
    static func countText(_ records: PeptideRecordSet) -> String {
        var parts: [String] = []
        if !records.entries.isEmpty {
            parts.append(records.entries.count == 1 ? "1 dose" : "\(records.entries.count) doses")
        }
        if !records.vials.isEmpty {
            parts.append(records.vials.count == 1 ? "1 vial" : "\(records.vials.count) vials")
        }
        if !records.schedules.isEmpty {
            parts.append(records.schedules.count == 1 ? "1 schedule" : "\(records.schedules.count) schedules")
        }
        guard let last = parts.popLast() else { return "no records" }
        return parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
    }
}
