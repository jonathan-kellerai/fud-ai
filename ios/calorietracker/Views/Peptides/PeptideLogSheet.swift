//
//  PeptideLogSheet.swift
//  calorietracker
//
//  Quick entry → confirm → save, like food logging. The amount field always
//  starts empty and nothing is filled in for the user.
//

import SwiftUI

struct PeptideLogSheet: View {
    private enum Step {
        case entry
        case confirm
    }

    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PeptideLogDraft
    @State private var step: Step
    @State private var typingOther = false
    @State private var issues: [PeptideDraftField: String] = [:]
    @State private var saveError: String?
    @State private var clientRequestID = UUID().uuidString.lowercased()
    private let onSaved: (() -> Void)?

    /// `reviewDraft` is for Visual QA only: it opens on the confirm step with
    /// values the test typed. App call sites never pass it.
    /// `now` is the default time only (Visual QA passes a fixed instant).
    init(
        person: String,
        compound: String? = nil,
        reviewDraft: PeptideLogDraft? = nil,
        now: Date = Date(),
        onSaved: (() -> Void)? = nil
    ) {
        if let reviewDraft {
            _draft = State(initialValue: reviewDraft)
            _step = State(initialValue: .confirm)
        } else {
            _draft = State(initialValue: PeptideLogDraft.new(person: PeptidePerson.normalized(person), compound: compound ?? "", now: now))
            _step = State(initialValue: .entry)
        }
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == .entry {
                        entryForm
                    } else {
                        PeptideLogReviewCard(draft: draft)
                        confirmActions
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle(step == .entry ? "Log dose" : "Confirm dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Entry

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            PeptidePersonToggle(person: personBinding)
            compoundSection
            amountSection
            timeSection
            siteSection
            vialSection
            drawnSection
            notesSection
            Button("Review") { review() }
                .buttonStyle(IronPrimaryButtonStyle())
        }
    }

    private var personBinding: Binding<String> {
        Binding(
            get: { draft.person },
            set: { newValue in
                guard newValue != draft.person else { return }
                draft.person = newValue
                draft.vialID = nil
            }
        )
    }

    private var compoundOptions: [String] {
        PeptideMath.compoundOptions(
            person: draft.person,
            inventoryCompounds: store.inventory.map(\.compound),
            loggedCompounds: store.loggedCompounds(person: draft.person)
        )
    }

    private var selectedOption: String? {
        guard !typingOther else { return nil }
        return compoundOptions.first { $0 == draft.compound } ?? compoundOptions.first { PeptideMath.sameCompound($0, draft.compound) }
    }

    private var compoundSection: some View {
        let options = compoundOptions
        let selected = selectedOption
        let showsOther = typingOther || (selected == nil && !draft.trimmedCompound.isEmpty)
        return VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Compound")
            PeptideFlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    PeptideChoiceChip(
                        title: option,
                        subtitle: PeptideMath.sameCompound(option, PeptideMath.glowName) ? PeptideMath.glowSubtitle : nil,
                        selected: selected == option
                    ) {
                        typingOther = false
                        selectCompound(option)
                    }
                }
                PeptideChoiceChip(title: "Other…", selected: showsOther) {
                    typingOther = true
                    if selected != nil { draft.compound = "" }
                    draft.vialID = nil
                }
            }
            if showsOther {
                PeptideInputField(title: "Compound name", text: $draft.compound, prompt: "Type the compound")
            }
            if let issue = issues[.compound] {
                PeptideIssueText(text: issue)
            }
        }
    }

    private func selectCompound(_ option: String) {
        if !PeptideMath.sameCompound(option, draft.compound) {
            draft.vialID = nil
        }
        draft.compound = option
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideInputField(
                title: "Amount",
                text: $draft.amountText,
                prompt: "Type the amount you took",
                keyboard: .decimalPad,
                monospaced: true,
                issue: issues[.amount]
            )
            PeptideFieldLabel("Units")
            PeptideFlowLayout(spacing: 8) {
                ForEach(PeptideMath.unitOptions, id: \.self) { unit in
                    PeptideChoiceChip(
                        title: unit,
                        subtitle: unit == "units" ? "U-100 syringe" : nil,
                        selected: draft.units == unit
                    ) {
                        draft.units = unit
                    }
                }
            }
            if let issue = issues[.units] {
                PeptideIssueText(text: issue)
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            PeptideFieldLabel("Time")
            DatePicker("Time", selection: $draft.takenAt, in: ...max(Date(), draft.takenAt).addingTimeInterval(60 * 60))
                .labelsHidden()
                .tint(IronTheme.bloodText)
            Text("Saved as " + PeptideMath.shortDateTime(draft.takenAt) + " ET")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var siteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Site (optional)")
            PeptideFlowLayout(spacing: 8) {
                ForEach(PeptideMath.siteOptions, id: \.self) { site in
                    PeptideChoiceChip(title: site, selected: draft.site == site) {
                        draft.site = draft.site == site ? "" : site
                    }
                }
            }
            PeptideInputField(title: "Site or route", text: $draft.site, prompt: "Or type a site", issue: issues[.site])
        }
    }

    @ViewBuilder
    private var vialSection: some View {
        let vials = store.personVials(person: draft.person).filter {
            !draft.trimmedCompound.isEmpty && PeptideMath.sameCompound($0.compound, draft.compound)
        }
        if !vials.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PeptideFieldLabel("Vial (optional)")
                PeptideFlowLayout(spacing: 8) {
                    PeptideChoiceChip(title: "No vial", selected: draft.vialID == nil) {
                        draft.vialID = nil
                    }
                    ForEach(vials) { vial in
                        PeptideChoiceChip(
                            title: vial.displayName,
                            subtitle: vial.mixedOn.map { "Mixed " + ReconMath.formatDateShort($0) },
                            selected: draft.vialID == vial.id
                        ) {
                            draft.vialID = vial.id
                            if draft.units == nil {
                                draft.units = PeptideMath.defaultUnits(for: vial)
                            }
                        }
                    }
                }
            }
        }
    }

    private var drawnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideInputField(
                title: "Drawn volume (optional)",
                text: $draft.drawnText,
                prompt: "What you drew",
                keyboard: .decimalPad,
                monospaced: true,
                issue: issues[.drawn]
            )
            HStack(spacing: 8) {
                PeptideChoiceChip(title: "mL", selected: draft.drawnUnit == "mL") { draft.drawnUnit = "mL" }
                PeptideChoiceChip(title: "units", subtitle: "U-100", selected: draft.drawnUnit == "units") { draft.drawnUnit = "units" }
            }
            Text("Only used to track what's left in a vial you entered. 100 units = 1 mL.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            PeptideFieldLabel("Notes (optional)")
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(IronTheme.textPrimary)
                .padding(10)
                .background(IronTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            if let issue = issues[.notes] {
                PeptideIssueText(text: issue)
            }
        }
    }

    private func review() {
        if typingOther || selectedOption == nil {
            draft.compound = draft.trimmedCompound
        }
        issues = PeptideMath.validate(draft)
        if issues.isEmpty {
            saveError = nil
            step = .confirm
        }
    }

    // MARK: Confirm

    private var confirmActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let saveError {
                PeptideIssueText(text: saveError)
            }
            Button("Save dose") { save() }
                .buttonStyle(IronPrimaryButtonStyle())
            Button("Edit") { step = .entry }
                .font(.system(size: 15, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        }
    }

    private func save() {
        let problems = PeptideMath.validate(draft)
        guard problems.isEmpty else {
            issues = problems
            step = .entry
            return
        }
        guard store.log(draft, clientRequestID: clientRequestID) != nil else {
            saveError = "This dose couldn't be saved. Check the fields and try again."
            return
        }
        onSaved?()
        dismiss()
    }
}

/// Everything the user typed, plus what's left in the vial only when it can be
/// calculated from the user's own vial numbers.
struct PeptideLogReviewCard: View {
    @Environment(PeptideLogStore.self) private var store
    let draft: PeptideLogDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                PeptideFieldLabel(PeptidePerson.name(draft.person))
                Text(draft.trimmedCompound)
                    .font(.system(size: 26, weight: .black))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(amountLine)
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(IronTheme.hairline).frame(height: 1)
            PeptideDetailRow(label: "Time", value: PeptideMath.shortDateTime(draft.takenAt) + " ET")
            PeptideDetailRow(label: "Site", value: draft.trimmedSite.isEmpty ? "—" : draft.trimmedSite)
            PeptideDetailRow(label: "Vial", value: vial?.displayName ?? "None")
            PeptideDetailRow(label: "Drawn volume", value: drawnLine)
            if !draft.trimmedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    PeptideFieldLabel("Notes")
                    Text(draft.trimmedNotes)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            remainingBlock
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: true)
    }

    private var amountLine: String {
        let amount = draft.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [amount, draft.units ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var drawnLine: String {
        guard let drawn = draft.drawnVolume else { return "—" }
        return PeptideMath.number(drawn) + " " + (draft.drawnUnit ?? "")
    }

    private var vial: PeptideVial? { store.vial(id: draft.vialID) }

    @ViewBuilder
    private var remainingBlock: some View {
        if let vial {
            let remaining = store.remaining(for: vial, including: hypotheticalEntry)
            VStack(alignment: .leading, spacing: 6) {
                PeptideFieldLabel("Remaining in vial after this dose")
                if remaining.calculable, let left = remaining.remainingML, let total = remaining.totalML {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(PeptideMath.mlText(left) + " of " + PeptideMath.mlText(total))
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .foregroundStyle(remaining.isLow ? IronTheme.rust : IronTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if remaining.isLow {
                            PeptideTag(text: "Low stock", tone: IronTheme.rust)
                        }
                    }
                    PeptideRemainingBar(fraction: remaining.fraction ?? 0, low: remaining.isLow)
                } else {
                    Text("Remaining can't be calculated")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(IronTheme.rust)
                    Text(remaining.reason ?? "A number this needs is missing.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("No vial picked, so nothing is subtracted from a vial.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hypotheticalEntry: PeptideLogEntry {
        PeptideLogEntry(
            id: "draft-review",
            person: PeptidePerson.normalized(draft.person),
            compound: draft.trimmedCompound,
            dose: draft.amount,
            units: draft.units,
            date: draft.takenAt,
            vialID: draft.vialID,
            drawnVolume: draft.drawnVolume,
            drawnUnit: draft.drawnVolume == nil ? nil : draft.drawnUnit,
            syncState: .pending
        )
    }
}
