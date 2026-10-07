//
//  PeptideEntryDetailView.swift
//  calorietracker
//
//  One administration: every field and its correction trail. It can be
//  corrected (with a reason) or voided (kept, with a reason).
//

import SwiftUI

struct PeptideEntryDetailView: View {
    @Environment(PeptideLogStore.self) private var store
    let entryID: String
    @State private var editTarget: PeptideLogEntry?
    @State private var voidTarget: PeptideLogEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entry = store.entry(id: entryID) {
                    PeptideEntryHeaderCard(entry: entry)
                    fieldsCard(entry)
                    if entry.voided {
                        PeptideBanner(
                            title: "Voided",
                            message: entry.voidReason.map { "Reason: " + $0 } ?? "No reason recorded.",
                            tone: IronTheme.rust
                        )
                    }
                    PeptideCorrectionTrail(corrections: entry.corrections)
                    actions(entry)
                } else {
                    PeptideBanner(
                        title: "This entry is no longer here",
                        message: "It may have been deleted with the rest of the app's data.",
                        tone: IronTheme.rust
                    )
                }
                PeptideFooter()
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Dose")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editTarget) { entry in
            PeptideEditEntrySheet(entry: entry)
        }
        .sheet(item: $voidTarget) { entry in
            PeptideVoidSheet(entry: entry)
        }
    }

    private func fieldsCard(_ entry: PeptideLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideDetailRow(label: "Time", value: entry.date.map { PeptideMath.shortDateTime($0) + " ET" } ?? entry.datetimeRaw)
            PeptideDetailRow(label: "Site", value: nonEmpty(entry.route))
            PeptideDetailRow(label: "Vial", value: store.vial(id: entry.vialID)?.displayName ?? "None")
            PeptideDetailRow(label: "Drawn volume", value: entry.drawnVolume.map { PeptideMath.number($0) + " " + (entry.drawnUnit ?? "mL") } ?? "—")
            if let source = entry.sourceVial, !source.isEmpty {
                PeptideDetailRow(label: "Source vial", value: source)
            }
            if let note = entry.notes, !note.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    PeptideFieldLabel("Notes")
                    Text(note)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private func nonEmpty(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
    }

    @ViewBuilder
    private func actions(_ entry: PeptideLogEntry) -> some View {
        if !entry.voided {
            VStack(alignment: .leading, spacing: 10) {
                Button("Edit") { editTarget = entry }
                    .buttonStyle(IronPrimaryButtonStyle())
                Button("Void entry") { voidTarget = entry }
                    .font(.system(size: 15, weight: .heavy))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.bloodText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous).stroke(IronTheme.bloodText, lineWidth: 1))
            }
        }
    }
}

struct PeptideEntryHeaderCard: View {
    let entry: PeptideLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PeptideFieldLabel("Logged")
            Text(entry.compound.isEmpty ? "Dose" : entry.compound)
                .font(.system(size: 26, weight: .black))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(entry.voided ? IronTheme.textTertiary : IronTheme.textPrimary)
                .strikethrough(entry.voided)
                .fixedSize(horizontal: false, vertical: true)
            Text(PeptideMath.amountText(entry.dose, entry.units))
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: !entry.voided)
    }
}

/// at (ET), field, old → new, reason, by.
struct PeptideCorrectionTrail: View {
    let corrections: [PeptideCorrection]

    var body: some View {
        if !corrections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                IronSectionTitle(title: "Correction history")
                ForEach(Array(corrections.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(whenText(item.at) + " · " + item.field + (item.derived ? " (derived)" : ""))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.old + " → " + item.new)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(IronTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.reason.isEmpty || !item.by.isEmpty {
                            Text([item.reason, item.by.isEmpty ? "" : "by " + item.by].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(IronTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .ironCard()
        }
    }

    private func whenText(_ raw: String) -> String {
        guard let date = PeptideMath.parseISO8601(raw) else { return raw.isEmpty ? "—" : raw }
        return PeptideMath.shortDateTime(date) + " ET"
    }
}

// MARK: - Edit

/// Compound, amount, units, time, site and notes need a reason and go into the
/// correction trail. The vial link and drawn volume don't.
struct PeptideEditEntrySheet: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: PeptideLogEntry
    @State private var takenAt: Date
    @State private var amountText: String
    @State private var units: String?
    @State private var compound: String
    @State private var site: String
    @State private var notes: String
    @State private var vialID: String?
    @State private var drawnText: String
    @State private var drawnUnit: String
    @State private var reason = ""
    @State private var errorText: String?

    init(entry: PeptideLogEntry) {
        self.entry = entry
        _takenAt = State(initialValue: entry.date ?? Date())
        _amountText = State(initialValue: entry.dose.map(PeptideMath.number) ?? "")
        _units = State(initialValue: entry.units)
        _compound = State(initialValue: entry.compound)
        _site = State(initialValue: entry.route ?? "")
        _notes = State(initialValue: entry.notes ?? "")
        _vialID = State(initialValue: entry.vialID)
        _drawnText = State(initialValue: entry.drawnVolume.map(PeptideMath.number) ?? "")
        _drawnUnit = State(initialValue: entry.drawnUnit ?? "mL")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editFields
                    localFields
                    PeptideInputField(title: "Reason for the correction (required)", text: $reason, prompt: "Why are you changing it?")
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                    Button("Save changes") { save() }
                        .buttonStyle(IronPrimaryButtonStyle())
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle("Correct dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var editFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            PeptideInputField(title: "Compound", text: $compound)
            PeptideInputField(title: "Amount", text: $amountText, keyboard: .decimalPad, monospaced: true)
            PeptideFieldLabel("Units")
            PeptideFlowLayout(spacing: 8) {
                ForEach(PeptideMath.unitOptions, id: \.self) { unit in
                    PeptideChoiceChip(title: unit, selected: units == unit) { units = unit }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                PeptideFieldLabel("Time")
                DatePicker("Time", selection: $takenAt)
                    .labelsHidden()
            }
            PeptideInputField(title: "Site or route", text: $site)
            VStack(alignment: .leading, spacing: 4) {
                PeptideFieldLabel("Notes")
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(10)
                    .background(IronTheme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            }
        }
    }

    private var localFields: some View {
        let vials = store.vialList(includeFinished: true).filter {
            PeptideMath.sameCompound($0.compound, compound) || $0.id == vialID
        }
        return VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Vial")
            if !vials.isEmpty {
                PeptideFieldLabel("Vial")
                PeptideFlowLayout(spacing: 8) {
                    PeptideChoiceChip(title: "No vial", selected: vialID == nil) { vialID = nil }
                    ForEach(vials) { vial in
                        PeptideChoiceChip(title: vial.displayName, selected: vialID == vial.id) { vialID = vial.id }
                    }
                }
            }
            PeptideInputField(title: "Drawn volume", text: $drawnText, keyboard: .decimalPad, monospaced: true)
            HStack(spacing: 8) {
                PeptideChoiceChip(title: "mL", selected: drawnUnit == "mL") { drawnUnit = "mL" }
                PeptideChoiceChip(title: "units", subtitle: "U-100", selected: drawnUnit == "units") { drawnUnit = "units" }
            }
            Text("Vial and drawn volume don't need a reason.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        errorText = nil
        var changes = PeptideCorrectionChanges()
        let amount = ReconMath.toNumber(amountText)
        if !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard amount.isFinite, amount > 0 else {
                errorText = "Amount must be a number more than 0."
                return
            }
            if amount != entry.dose { changes.dose = amount }
        }
        if let original = entry.date {
            if abs(takenAt.timeIntervalSince(original)) >= 60 { changes.datetime = PeptideMath.iso8601NewYork(takenAt) }
        } else {
            changes.datetime = PeptideMath.iso8601NewYork(takenAt)
        }
        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSite != (entry.route ?? "") {
            guard trimmedSite.count <= PeptideMath.maxRouteLength else {
                errorText = "Site is too long."
                return
            }
            changes.route = trimmedSite
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNotes != (entry.notes ?? "") {
            guard trimmedNotes.count <= PeptideMath.maxNotesLength else {
                errorText = "Notes are too long."
                return
            }
            changes.notes = trimmedNotes
        }
        let trimmedCompound = compound.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCompound.isEmpty, trimmedCompound.count <= PeptideMath.maxCompoundLength else {
            errorText = "Type the compound."
            return
        }
        if trimmedCompound != entry.compound { changes.compound = trimmedCompound }
        if let units, units != entry.units { changes.units = units }
        let drawnRaw = drawnText.trimmingCharacters(in: .whitespacesAndNewlines)
        var drawn: Double?
        if !drawnRaw.isEmpty {
            let value = ReconMath.toNumber(drawnRaw)
            guard value.isFinite, value > 0 else {
                errorText = "Drawn volume must be a number more than 0."
                return
            }
            drawn = value
        }
        let localChanged = vialID != entry.vialID || drawn != entry.drawnVolume
            || (drawn != nil && drawnUnit != (entry.drawnUnit ?? "mL"))
        if !changes.isEmpty {
            if let message = store.correct(entry, reason: reason, changes: changes) {
                errorText = message
                return
            }
        }
        if localChanged {
            store.updateLocalDetails(for: entry, vialID: vialID, drawnVolume: drawn, drawnUnit: drawnUnit)
        }
        if changes.isEmpty && !localChanged {
            errorText = "Nothing changed."
            return
        }
        dismiss()
    }
}

// MARK: - Void

/// "Delete" is a void with a reason. Voided entries stay visible with it.
struct PeptideVoidSheet: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: PeptideLogEntry
    @State private var reason = ""
    @State private var confirming = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeptideEntryHeaderCard(entry: entry)
                    Text("Voided entries stay in history with your reason. Nothing is deleted.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PeptideInputField(title: "Reason (required)", text: $reason, prompt: "Why void this entry?")
                    Button("Void entry") {
                        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            errorText = "A reason is required."
                        } else {
                            confirming = true
                        }
                    }
                    .buttonStyle(IronPrimaryButtonStyle())
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                }
                .padding(16)
            }
            .background(IronTheme.canvas)
            .navigationTitle("Void dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Void this dose?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Void", role: .destructive) { commit() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func commit() {
        if let message = store.void(entry, reason: reason) {
            errorText = message
            return
        }
        dismiss()
    }
}
