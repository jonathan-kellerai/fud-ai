//
//  PeptideEntryDetailView.swift
//  calorietracker
//
//  One draw: what was typed, the syringe scale and vial recorded when it was
//  saved, and its trail in words. The only screen that shows mg, worked out
//  one step per line from the entry's save-time snapshot. It can be corrected
//  (with a reason) or voided (kept, with a reason).
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
                    PeptideMilligramCard(entry: entry)
                    PeptideCorrectionTrail(corrections: entry.corrections)
                    actions(entry)
                } else {
                    PeptideBanner(
                        title: "This entry is no longer here",
                        message: "It may have been deleted with the rest of the app's data.",
                        tone: IronTheme.rust
                    )
                }
                Text("Voided entries stay in the trail.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PeptideFooter()
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Draw")
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
            PeptideDetailRow(label: "Vial", value: vialText(entry))
            if entry.drawnUnit == .units {
                PeptideDetailRow(label: "Syringe scale", value: entry.syringeScaleAtSave?.label ?? "Not recorded")
            }
            PeptideDetailRow(label: "Site", value: nonEmpty(entry.route))
            if entry.dose != nil || entry.units != nil {
                PeptideDetailRow(label: "Amount typed in an earlier version", value: PeptideMath.amountText(entry.dose, entry.units))
            }
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

    /// The vial and whether it was confirmed when this draw was saved.
    private func vialText(_ entry: PeptideLogEntry) -> String {
        guard let id = entry.vialID else { return "None" }
        let name = store.vial(id: id)?.displayName ?? "A vial no longer listed"
        guard entry.vialIDAtSave == id else { return name }
        return name + (entry.concentrationConfirmedAtSave ? " · confirmed" : " · not confirmed")
    }

    private func nonEmpty(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
    }

    @ViewBuilder
    private func actions(_ entry: PeptideLogEntry) -> some View {
        if !entry.voided {
            VStack(alignment: .leading, spacing: 10) {
                Button("Edit entry") { editTarget = entry }
                    .buttonStyle(IronPrimaryButtonStyle())
                Button("Void entry") { voidTarget = entry }
                    .buttonStyle(PeptideSecondaryButtonStyle())
            }
        }
    }
}

/// Compound and draw, and one status: "Voided" with the reason, or nothing.
struct PeptideEntryHeaderCard: View {
    let entry: PeptideLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.compound.isEmpty ? "Draw" : entry.compound)
                .font(.system(.title2, design: .default, weight: .black))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.drawText ?? "Draw not recorded")
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if entry.voided {
                Text("Voided")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(IronTheme.rust)
                Text(entry.voidReason.map { "Reason: " + $0 } ?? "No reason recorded.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: !entry.voided)
        .accessibilityElement(children: .combine)
    }
}

/// The mg working, from the entry's snapshot only, one step per line. When it
/// can't be worked out, says why instead.
struct PeptideMilligramCard: View {
    let entry: PeptideLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PeptideFieldLabel("Arithmetic")
            switch PeptideMath.milligramDerivation(for: entry) {
            case .steps(let steps):
                ForEach(steps) { step in
                    Text(step.text)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(step.spoken)
                }
            case .unavailable(let reasons):
                ForEach(reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(IronTheme.rust)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("This draw shows only what you typed.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .noDraw:
                Text("No draw was recorded for this entry, so there's nothing to work out.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
        .accessibilityElement(children: .contain)
    }
}

/// Changes in words: "Draw: 20 units → 25 units", then when and why.
struct PeptideCorrectionTrail: View {
    let corrections: [PeptideCorrection]

    var body: some View {
        if !corrections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                IronSectionTitle(title: "Changes")
                ForEach(Array(corrections.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PeptideMath.trailSentence(item))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(IronTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(trailDetail(item))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .ironCard()
        }
    }

    private func trailDetail(_ item: PeptideCorrection) -> String {
        let when = PeptideMath.parseISO8601(item.at).map { PeptideMath.shortDateTime($0) + " ET" } ?? (item.at.isEmpty ? "—" : item.at)
        return [when, item.reason].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Edit

/// Compound, draw, time, site and notes. A reason is required and each
/// change goes into the trail. The vial and the save-time snapshot don't change.
struct PeptideEditEntrySheet: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: PeptideLogEntry
    @State private var takenAt: Date
    @State private var drawText: String
    @State private var drawUnit: PeptideDrawUnit?
    @State private var compound: String
    @State private var site: String
    @State private var notes: String
    @State private var reason = ""
    @State private var errorText: String?

    init(entry: PeptideLogEntry) {
        self.entry = entry
        _takenAt = State(initialValue: entry.date ?? Date())
        _drawText = State(initialValue: entry.drawnVolume.map(PeptideMath.number) ?? "")
        _drawUnit = State(initialValue: entry.drawnUnit)
        _compound = State(initialValue: entry.compound)
        _site = State(initialValue: entry.route ?? "")
        _notes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeptideInputField(title: "Compound", text: $compound)
                    PeptideInputField(title: "Draw", text: $drawText, prompt: "Type what you drew", keyboard: .decimalPad, monospaced: true)
                    PeptideFlowLayout(spacing: 8) {
                        ForEach(PeptideDrawUnit.allCases) { unit in
                            PeptideChoiceChip(title: unit.label, selected: drawUnit == unit) { drawUnit = unit }
                                .accessibilityLabel(unit.spokenLabel)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        PeptideFieldLabel("Time")
                        DatePicker("Time", selection: $takenAt)
                            .labelsHidden()
                            .tint(IronTheme.brass)
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
                    Text("The vial, syringe scale and concentration stay as they were when you saved this draw.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PeptideInputField(title: "Reason for the change (required)", text: $reason, prompt: "Why are you changing it?")
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
            .navigationTitle("Edit draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        errorText = nil
        var changes = PeptideCorrectionChanges()
        let drawRaw = drawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !drawRaw.isEmpty || entry.drawnVolume != nil {
            if let problem = PeptideMath.drawIssue(drawRaw) {
                errorText = problem
                return
            }
            guard let unit = drawUnit else {
                errorText = "Pick units or mL."
                return
            }
            let value = ReconMath.toNumber(drawRaw)
            if value != entry.drawnVolume { changes.draw = value }
            if unit != entry.drawnUnit { changes.drawUnit = unit }
            if changes.drawUnit != nil && changes.draw == nil { changes.draw = value }
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
        if let message = store.correct(entry, reason: reason, changes: changes) {
            errorText = message
            return
        }
        dismiss()
    }
}

// MARK: - Void

/// "Delete" is a void with a reason. Voided entries stay in the trail.
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
            .navigationTitle("Void draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Void this draw?",
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
