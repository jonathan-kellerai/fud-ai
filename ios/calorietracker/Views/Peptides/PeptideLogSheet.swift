//
//  PeptideLogSheet.swift
//  calorietracker
//
//  Log a draw like a set: compound, the draw you typed (units or mL), the
//  time (now unless you change it). Review, then save. The draw field always
//  starts empty and no unit is picked: nothing is filled in for the user.
//

import SwiftUI

struct PeptideLogSheet: View {
    private enum Step {
        case entry
        case review
    }

    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PeptideLogDraft
    @State private var step: Step
    @State private var typingOther = false
    @State private var showsDetails = false
    @State private var issues: [PeptideDraftField: String] = [:]
    @State private var saveError: String?
    /// One id per sheet, so saving twice replaces instead of adding a second draw.
    @State private var entryID = UUID().uuidString.lowercased()
    private let onSaved: (() -> Void)?

    /// `reviewDraft` is for Visual QA only: it opens on the review step with
    /// values the test typed. App call sites never pass it.
    /// `now` is the default time only (Visual QA passes a fixed instant).
    init(
        compound: String? = nil,
        reviewDraft: PeptideLogDraft? = nil,
        now: Date = Date(),
        onSaved: (() -> Void)? = nil
    ) {
        if let reviewDraft {
            _draft = State(initialValue: reviewDraft)
            _step = State(initialValue: .review)
        } else {
            _draft = State(initialValue: PeptideLogDraft.new(compound: compound ?? "", now: now))
            _step = State(initialValue: .entry)
        }
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if step == .entry {
                        entryForm
                    } else {
                        PeptideLogReviewCard(draft: draft)
                        reviewActions
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle(step == .entry ? "Log a draw" : "Review draw")
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
        VStack(alignment: .leading, spacing: 18) {
            compoundSection
            drawSection
            timeSection
            vialSection
            if draft.drawUnit == .units {
                scaleSection
            }
            detailsSection
            if !issues.isEmpty {
                PeptideIssueText(text: "Check the fields above.")
            }
            Button("Review") { review() }
                .buttonStyle(IronPrimaryButtonStyle())
                .accessibilityIdentifier("peptides.log.review")
        }
    }

    private var compoundOptions: [String] {
        PeptideMath.compoundOptions(
            vialCompounds: store.vialList().map(\.compound),
            loggedCompounds: store.loggedCompounds()
        )
    }

    private var selectedOption: String? {
        guard !typingOther else { return nil }
        return compoundOptions.first { $0 == draft.compound } ?? compoundOptions.first { PeptideMath.sameCompound($0, draft.compound) }
    }

    private var compoundSection: some View {
        let options = compoundOptions
        let selected = selectedOption
        let showsOther = typingOther || options.isEmpty || (selected == nil && !draft.trimmedCompound.isEmpty)
        return VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Compound")
            if !options.isEmpty {
                PeptideFlowLayout(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        PeptideChoiceChip(title: option, selected: selected == option) {
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

    /// The draw: typed, never filled. The unit is a choice the user makes.
    private var drawSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideInputField(
                title: "Draw",
                text: $draft.drawText,
                prompt: "Type what you drew",
                keyboard: .decimalPad,
                monospaced: true,
                issue: issues[.draw]
            )
            .accessibilityIdentifier("peptides.log.draw")
            PeptideFieldLabel("Unit")
            PeptideFlowLayout(spacing: 8) {
                ForEach(PeptideDrawUnit.allCases) { unit in
                    PeptideChoiceChip(title: unit.label, selected: draft.drawUnit == unit) {
                        draft.drawUnit = unit
                    }
                    .accessibilityLabel(unit.spokenLabel)
                }
            }
            if let issue = issues[.unit] {
                PeptideIssueText(text: issue)
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            PeptideFieldLabel("Time")
            DatePicker("Time", selection: $draft.takenAt, in: ...max(Date(), draft.takenAt).addingTimeInterval(60 * 60))
                .labelsHidden()
                .tint(IronTheme.brass)
            Text("Saved as " + PeptideMath.shortDateTime(draft.takenAt) + " ET")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var vialSection: some View {
        let vials = store.vialList().filter {
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
                        }
                    }
                }
            }
        }
    }

    /// This draw's own syringe scale. Defaults to the one in Settings.
    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Syringe scale for this draw")
            PeptideFlowLayout(spacing: 8) {
                PeptideChoiceChip(
                    title: "Settings",
                    subtitle: store.syringeScale?.label ?? "Not set",
                    selected: draft.scaleOverride == nil
                ) {
                    draft.scaleOverride = nil
                }
                ForEach(PeptideSyringeScale.allCases) { scale in
                    PeptideChoiceChip(title: scale.label, selected: draft.scaleOverride == scale) {
                        draft.scaleOverride = scale
                    }
                }
            }
            Text("Saved with this draw. Changing Settings later doesn't change it.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Site and notes are optional, so they fold away like a set's notes.
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showsDetails.toggle()
            } label: {
                Label(showsDetails ? "Hide site and notes" : "Add site or notes (optional)", systemImage: showsDetails ? "chevron.up" : "chevron.down")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.brass)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsDetails || !draft.site.isEmpty || !draft.notes.isEmpty {
                siteSection
                notesSection
            }
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
            step = .review
        }
    }

    // MARK: Review

    private var reviewActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let saveError {
                PeptideIssueText(text: saveError)
            }
            Button("Save draw") { save() }
                .buttonStyle(IronPrimaryButtonStyle())
                .accessibilityIdentifier("peptides.log.save")
            Button("Edit") { step = .entry }
                .buttonStyle(PeptideSecondaryButtonStyle())
        }
    }

    private func save() {
        let problems = PeptideMath.validate(draft)
        guard problems.isEmpty else {
            issues = problems
            step = .entry
            return
        }
        guard store.log(draft, id: entryID) != nil else {
            saveError = "This draw couldn't be saved. Check the fields and try again."
            return
        }
        onSaved?()
        dismiss()
    }
}

/// Everything the user typed, the syringe scale this draw will record, and
/// what's left in the vial only when the user's own numbers allow it.
/// Never shows mg.
struct PeptideLogReviewCard: View {
    @Environment(PeptideLogStore.self) private var store
    let draft: PeptideLogDraft

    var body: some View {
        let entry = store.entry(from: draft, id: "draft-review")
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.trimmedCompound)
                    .font(.system(.title2, design: .default, weight: .black))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.drawText ?? "—")
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Rectangle().fill(IronTheme.hairline).frame(height: 1)
            PeptideDetailRow(label: "Time", value: PeptideMath.shortDateTime(draft.takenAt) + " ET")
            PeptideDetailRow(label: "Vial", value: vial?.displayName ?? "None")
            if entry.drawnUnit == .units {
                PeptideDetailRow(label: "Syringe scale", value: entry.syringeScaleAtSave?.label ?? "Not recorded")
            }
            PeptideDetailRow(label: "Site", value: draft.trimmedSite.isEmpty ? "—" : draft.trimmedSite)
            if !draft.trimmedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    PeptideFieldLabel("Notes")
                    Text(draft.trimmedNotes)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            remainingBlock(entry)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: true)
    }

    private var vial: PeptideVial? { store.vial(id: draft.vialID) }

    @ViewBuilder
    private func remainingBlock(_ entry: PeptideLogEntry) -> some View {
        if let vial {
            let remaining = store.remaining(for: vial, including: entry)
            VStack(alignment: .leading, spacing: 6) {
                PeptideFieldLabel("Left in the vial after this draw")
                if remaining.calculable, let left = remaining.remainingML, let total = remaining.totalML {
                    Text(PeptideMath.mlText(left) + " of " + PeptideMath.mlText(total))
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    PeptideRemainingBar(fraction: remaining.fraction ?? 0, low: remaining.isLow)
                } else {
                    Text("Remaining is not shown.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                    Text(remaining.reason ?? "A number this needs is missing.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("No vial picked, so nothing is taken out of a vial.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
