//
//  PeptideEntryDetailView.swift
//  calorietracker
//
//  One administration: every field, sync state, correction trail. App rows can
//  be corrected (with a reason) or voided; the peptide assistant's rows are
//  read-only.
//

import SwiftUI

struct PeptideEntryDetailView: View {
    @Environment(PeptideLogStore.self) private var store
    let entryID: String
    let clientRequestID: String?
    @State private var editTarget: PeptideLogEntry?
    @State private var voidTarget: PeptideLogEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entry = store.entry(id: entryID, clientRequestID: clientRequestID) {
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
                        message: "It may have been discarded or replaced after syncing.",
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
        .task { await store.refreshIfStale() }
        .sheet(item: $editTarget) { entry in
            PeptideEditEntrySheet(entry: entry)
        }
        .sheet(item: $voidTarget) { entry in
            PeptideVoidSheet(entry: entry)
        }
    }

    private func fieldsCard(_ entry: PeptideLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideDetailRow(label: "Person", value: PeptidePerson.name(entry.person))
            PeptideDetailRow(label: "Time", value: entry.date.map { PeptideMath.shortDateTime($0) + " ET" } ?? entry.datetimeRaw)
            PeptideDetailRow(label: "Site", value: nonEmpty(entry.route))
            PeptideDetailRow(label: "Vial", value: store.vial(id: entry.vialID)?.displayName ?? "None")
            PeptideDetailRow(label: "Drawn volume", value: entry.drawnVolume.map { PeptideMath.number($0) + " " + (entry.drawnUnit ?? "mL") } ?? "—")
            PeptideDetailRow(label: "Scheduled", value: entry.isScheduled ? "Yes (peptide assistant)" : "No")
            PeptideDetailRow(label: "Recorded via", value: recordedViaText(entry))
            if let note = entry.notes, !note.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    PeptideFieldLabel("Notes")
                    Text(note)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !entry.badges.isEmpty {
                PeptideFlowLayout(spacing: 6) {
                    ForEach(entry.badges, id: \.self) { badge in
                        PeptideTag(text: badge, tone: IronTheme.brass)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private func recordedViaText(_ entry: PeptideLogEntry) -> String {
        let via = entry.recordedVia ?? ""
        switch via {
        case "peptide-agent": return "Peptide assistant"
        case "app": return "This app"
        case "": return entry.isPendingCreate ? "This app" : "—"
        default: return via
        }
    }

    private func nonEmpty(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
    }

    @ViewBuilder
    private func actions(_ entry: PeptideLogEntry) -> some View {
        if entry.isAgentRow {
            PeptideBanner(
                title: "Recorded by the peptide assistant",
                message: "This entry is read-only in the app. Ask the peptide assistant to change it.",
                tone: IronTheme.textSecondary
            )
        } else if !entry.isEditableInApp {
            PeptideBanner(
                title: "Read-only",
                message: "This entry wasn't recorded by this app, so it can't be changed here.",
                tone: IronTheme.textSecondary
            )
        } else if entry.voided {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if case .failed(let message) = entry.syncState, let opID = entry.pendingOpID {
                    PeptideBanner(title: "Not accepted by the bridge", message: message, tone: IronTheme.rust)
                    HStack(spacing: 10) {
                        Button("Retry") { store.retry(opID: opID) }
                            .buttonStyle(IronCompactButtonStyle())
                        Button("Discard", role: .destructive) { store.discard(opID: opID) }
                            .font(.system(size: 15, weight: .heavy))
                            .fontWidth(.condensed)
                            .textCase(.uppercase)
                            .foregroundStyle(IronTheme.bloodText)
                    }
                }
                Button("Edit") { editTarget = entry }
                    .buttonStyle(IronPrimaryButtonStyle())
                Button(entry.isPendingCreate ? "Remove unsynced entry" : "Void entry") { voidTarget = entry }
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
            HStack(alignment: .firstTextBaseline) {
                PeptideFieldLabel(entry.isPlanned ? "Planned" : "Completed")
                Spacer(minLength: 4)
                PeptideSyncChip(state: entry.syncState)
            }
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

/// Time, amount, site, notes (compound/units only when unscheduled), plus the
/// device-only vial link and drawn volume. A reason is required once synced.
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

    private var canChangeCompound: Bool { !entry.isScheduled }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !entry.isEditableInApp {
                        PeptideBanner(title: PeptideLogStore.message(readOnly: entry), tone: IronTheme.rust)
                    } else {
                        editFields
                        localFields
                        reasonField
                        if let errorText {
                            PeptideIssueText(text: errorText)
                        }
                        Button("Save changes") { save() }
                            .buttonStyle(IronPrimaryButtonStyle())
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle(entry.isPendingCreate ? "Edit unsynced dose" : "Correct dose")
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
            if canChangeCompound {
                PeptideInputField(title: "Compound", text: $compound)
            } else {
                PeptideDetailRow(label: "Compound", value: entry.compound)
                Text("Scheduled dose: compound and units stay as the peptide assistant recorded them.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PeptideInputField(title: "Amount", text: $amountText, keyboard: .decimalPad, monospaced: true)
            if canChangeCompound {
                PeptideFieldLabel("Units")
                PeptideFlowLayout(spacing: 8) {
                    ForEach(PeptideMath.unitOptions, id: \.self) { unit in
                        PeptideChoiceChip(title: unit, selected: units == unit) { units = unit }
                    }
                }
            } else {
                PeptideDetailRow(label: "Units", value: entry.units ?? "—")
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
        let vials = store.personVials(person: entry.person, includeFinished: true).filter {
            PeptideMath.sameCompound($0.compound, compound) || $0.id == vialID
        }
        return VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "On this phone")
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
            Text("Vial and drawn volume stay on this phone and don't need a reason.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var reasonField: some View {
        if !entry.isPendingCreate {
            PeptideInputField(title: "Reason for the correction (required)", text: $reason, prompt: "Why are you changing it?")
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
        if canChangeCompound {
            let trimmedCompound = compound.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCompound.isEmpty, trimmedCompound.count <= PeptideMath.maxCompoundLength else {
                errorText = "Type the compound."
                return
            }
            if trimmedCompound != entry.compound { changes.compound = trimmedCompound }
            if let units, units != entry.units { changes.units = units }
        }
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
                    if !entry.isEditableInApp {
                        PeptideBanner(title: PeptideLogStore.message(readOnly: entry), tone: IronTheme.rust)
                    } else if entry.isPendingCreate && store.isCreateUncertain(entry) {
                        Text("This dose may already have reached the bridge. It will be voided there with your reason as soon as the bridge answers.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PeptideInputField(title: "Reason (optional)", text: $reason, prompt: "Why remove this dose?")
                        Button("Remove") { confirming = true }
                            .buttonStyle(IronPrimaryButtonStyle())
                    } else if entry.isPendingCreate {
                        Text("This dose hasn't reached the bridge yet. Removing it deletes it from this phone.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Remove") { confirming = true }
                            .buttonStyle(IronPrimaryButtonStyle())
                    } else {
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
                    }
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                }
                .padding(16)
            }
            .background(IronTheme.canvas)
            .navigationTitle(entry.isPendingCreate ? "Remove dose" : "Void dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                entry.isPendingCreate ? "Remove this unsynced dose?" : "Void this dose?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button(entry.isPendingCreate ? "Remove" : "Void", role: .destructive) { commit() }
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
