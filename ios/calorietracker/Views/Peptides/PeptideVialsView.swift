//
//  PeptideVialsView.swift
//  calorietracker
//
//  Peptides › Vials: the user's own vials, each with its amount and diluent
//  as typed and who confirmed the mix and when. Remaining (and its bar) only
//  when confirmed; otherwise "Remaining is not shown." Reconstitute is the
//  main action.
//

import SwiftUI
import UniformTypeIdentifiers

struct PeptideVialEditorTarget: Identifiable {
    let id = UUID().uuidString
    var vial: PeptideVial?
}

struct PeptideVialsView: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var editorTarget: PeptideVialEditorTarget?
    @State private var reconstituteTarget: PeptideVialEditorTarget?
    @State private var showFinished = false
    @State private var finishTarget: PeptideVial?
    @State private var isPickingFile = false
    @State private var importRequest: PeptideImportRequest?
    @State private var importError: String?

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PeptideHeader(text: "Vials")
            Button {
                reconstituteTarget = PeptideVialEditorTarget(vial: nil)
            } label: {
                Label("Reconstitute a vial", systemImage: "plus")
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .accessibilityIdentifier("peptides.vials.reconstitute")
            activeSection
            finishedSection
            Text("Syringe scale: " + (store.syringeScale?.label ?? "not set") + ", recorded in Settings.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                editorTarget = PeptideVialEditorTarget(vial: nil)
            } label: {
                Label("Add a blend or other vial", systemImage: "square.and.pencil")
            }
            .buttonStyle(PeptideSecondaryButtonStyle())
            Button {
                isPickingFile = true
            } label: {
                Label("Import from a file", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PeptideSecondaryButtonStyle())
            .accessibilityHint("Adds vials, schedules and draws from a peptides file. You see what it adds first.")
        }
        .sheet(item: $editorTarget) { target in
            PeptideVialEditor(vial: target.vial)
        }
        .sheet(item: $reconstituteTarget) { target in
            ReconView(vial: target.vial)
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: loadFile
        )
        .sheet(item: $importRequest) { request in
            PeptideImportPreviewSheet(archive: request.archive)
        }
        .alert("Unable to Import", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The selected file could not be imported.")
        }
        .confirmationDialog(
            "Finish this vial?",
            isPresented: finishDialogBinding,
            titleVisibility: .visible,
            presenting: finishTarget
        ) { vial in
            Button("Finish vial") { store.finishVial(id: vial.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Finished vials stay in the list and keep their logged draws.")
        }
    }

    private var finishDialogBinding: Binding<Bool> {
        Binding(
            get: { finishTarget != nil },
            set: { shown in if !shown { finishTarget = nil } }
        )
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { shown in if !shown { importError = nil } }
        )
    }

    /// Validates the picked file; nothing changes until the preview is confirmed.
    private func loadFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            importRequest = PeptideImportRequest(archive: try PeptideArchive.load(from: url))
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        let vials = store.vialList()
        if vials.isEmpty {
            Text("No vials yet. Reconstitute one to start.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .peptideAccentCard(IronTheme.concrete)
        }
        ForEach(vials) { vial in
            card(vial, onFinish: { finishTarget = vial })
        }
    }

    @ViewBuilder
    private var finishedSection: some View {
        let finished = store.vialList(includeFinished: true).filter { $0.status == .finished }
        if !finished.isEmpty {
            Toggle(showFinished ? "Finished vials (\(finished.count))" : "Show finished vials (\(finished.count))", isOn: $showFinished)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textSecondary)
                .tint(IronTheme.olive)
            if showFinished {
                ForEach(finished) { vial in
                    card(vial, onFinish: nil)
                }
            }
        }
    }

    private func card(_ vial: PeptideVial, onFinish: (() -> Void)?) -> some View {
        var reconstitute: (() -> Void)?
        if isSingle(vial) {
            reconstitute = { reconstituteTarget = PeptideVialEditorTarget(vial: vial) }
        }
        return PeptideVialCard(
            vial: vial,
            onEdit: { editorTarget = PeptideVialEditorTarget(vial: vial) },
            onReconstitute: reconstitute,
            onFinish: onFinish
        )
    }

    private func isSingle(_ vial: PeptideVial) -> Bool {
        !vial.isBlend && vial.components.count <= 1
    }
}

struct PeptideVialCard: View {
    @Environment(PeptideLogStore.self) private var store
    let vial: PeptideVial
    var onEdit: (() -> Void)?
    /// Opens Reconstitute on this vial (single-compound vials).
    var onReconstitute: (() -> Void)?
    var onFinish: (() -> Void)?

    var body: some View {
        let remaining = store.remaining(for: vial)
        VStack(alignment: .leading, spacing: 8) {
            header(remaining)
            amountsBlock
            confirmationBlock(remaining)
            Text(remaining.linkedCount == 1 ? "1 draw logged from this vial" : "\(remaining.linkedCount) draws logged from this vial")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
            if !vial.notes.isEmpty {
                Text(vial.notes)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .peptideAccentCard(vial.concentrationConfirmed ? IronTheme.olive : IronTheme.rust)
    }

    private func header(_ remaining: PeptideMath.Remaining) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vial.displayName)
                .font(.system(.title3, design: .default, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            PeptideFlowLayout(spacing: 6) {
                if vial.isBlend { PeptideTag(text: "Blend", tone: IronTheme.textSecondary) }
                if vial.status == .finished { PeptideTag(text: "Finished", tone: IronTheme.textSecondary) }
                if remaining.isLow && vial.status == .active { PeptideTag(text: "Low", tone: IronTheme.brass) }
            }
        }
    }

    /// Exactly what was typed.
    private var amountsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vial.components) { component in
                PeptideDetailRow(
                    label: vial.isBlend && !component.name.isEmpty ? component.name : "Vial amount",
                    value: component.amount.map { PeptideMath.number($0) + " " + component.unit + " (you entered)" } ?? "Not entered"
                )
            }
            if vial.components.isEmpty {
                PeptideDetailRow(label: "Vial amount", value: "Not entered")
            }
            PeptideDetailRow(label: "Diluent", value: vial.diluentML.map { PeptideMath.number($0) + " mL (you entered)" } ?? "Not entered")
            if let mixed = vial.mixedOn {
                PeptideDetailRow(label: "Mixed", value: ReconMath.formatDate(mixed))
            }
        }
    }

    @ViewBuilder
    private func confirmationBlock(_ remaining: PeptideMath.Remaining) -> some View {
        if let confirmed = PeptideMath.confirmedText(vial) {
            PeptideDetailRow(label: "Confirmed", value: confirmed)
            if let line = arithmeticLine {
                Text(line.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(line.spoken)
            }
            if remaining.calculable, let left = remaining.remainingML, let total = remaining.totalML {
                PeptideDetailRow(label: "Left", value: PeptideMath.mlText(left) + " of " + PeptideMath.mlText(total))
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
        } else {
            Text("Concentration not confirmed. Remaining is not shown.")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(IronTheme.rust)
                .fixedSize(horizontal: false, vertical: true)
            PeptideDetailRow(label: "Left", value: "not tracked")
        }
    }

    /// "10 mg ÷ 2 mL = 5 mg/mL", for a confirmed single-compound vial.
    private var arithmeticLine: PeptideMath.DerivationStep? {
        guard !vial.isBlend, vial.components.count == 1 else { return nil }
        return PeptideMath.reconstituteArithmetic(
            amount: vial.components[0].amount,
            unit: vial.components[0].unit,
            diluentML: vial.diluentML
        )
    }

    private var buttons: some View {
        PeptideFlowLayout(spacing: 10) {
            if !vial.concentrationConfirmed, let onReconstitute {
                Button("Confirm in Reconstitute", action: onReconstitute)
                    .buttonStyle(IronCompactButtonStyle())
            }
            if let onEdit {
                Button("Edit", action: onEdit)
                    .buttonStyle(IronCompactButtonStyle())
            }
            if let onFinish {
                Button("Finish vial", action: onFinish)
                    .font(.system(.subheadline, design: .default, weight: .heavy))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            }
        }
    }
}

// MARK: - Editor

struct PeptideVialEditor: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let existing: PeptideVial?
    @State private var compound: String
    @State private var isBlend: Bool
    @State private var components: [ComponentDraft]
    @State private var diluentText: String
    @State private var mixedKnown: Bool
    @State private var mixedOn: Date
    @State private var confirmed: Bool
    @State private var confirmedAt: Date?
    @State private var thresholdText: String
    @State private var notes: String
    @State private var errorText: String?
    @State private var confirmDelete = false

    struct ComponentDraft: Identifiable, Equatable {
        var id: String
        var name: String
        var amountText: String
        /// Nil until the user picks mg, mcg or IU.
        var unit: String?
    }

    init(vial: PeptideVial?) {
        existing = vial
        _compound = State(initialValue: vial?.compound ?? "")
        _isBlend = State(initialValue: vial?.isBlend ?? false)
        let drafts = (vial?.components ?? []).map {
            ComponentDraft(
                id: $0.id,
                name: $0.name,
                amountText: $0.amount.map(PeptideMath.number) ?? "",
                unit: $0.unit.isEmpty ? nil : $0.unit
            )
        }
        _components = State(initialValue: drafts.isEmpty ? [ComponentDraft(id: UUID().uuidString, name: "", amountText: "", unit: nil)] : drafts)
        _diluentText = State(initialValue: vial?.diluentML.map(PeptideMath.number) ?? "")
        _mixedKnown = State(initialValue: vial?.mixedOn != nil)
        _mixedOn = State(initialValue: vial?.mixedOn.map(PeptideViewDates.localDate(fromCivil:)) ?? Date())
        _confirmed = State(initialValue: vial?.concentrationConfirmed ?? false)
        _confirmedAt = State(initialValue: vial?.concentrationConfirmedAt)
        _thresholdText = State(initialValue: vial?.lowStockThresholdML.map(PeptideMath.number) ?? "")
        _notes = State(initialValue: vial?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    compoundSection
                    componentsSection
                    PeptideInputField(title: "Diluent (mL)", text: $diluentText, prompt: "mL of water you added", keyboard: .decimalPad, monospaced: true)
                    mixedSection
                    confirmSection
                    thresholdSection
                    notesSection
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                    Button("Save vial") { save() }
                        .buttonStyle(IronPrimaryButtonStyle())
                    if existing != nil {
                        Button("Delete vial", role: .destructive) { confirmDelete = true }
                            .font(.system(size: 15, weight: .heavy))
                            .fontWidth(.condensed)
                            .textCase(.uppercase)
                            .foregroundStyle(IronTheme.brass)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle(existing == nil ? "Add vial" : "Edit vial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Delete this vial?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete vial", role: .destructive) {
                    if let existing { store.deleteVial(id: existing.id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Logged draws stay. They just lose the link to this vial.")
            }
        }
    }

    private var compoundSection: some View {
        let options = PeptideMath.compoundOptions(vialCompounds: store.vialList().map(\.compound), loggedCompounds: store.loggedCompounds())
        return VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Compound")
            PeptideFlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    PeptideChoiceChip(
                        title: option,
                        subtitle: PeptideMath.sameCompound(option, PeptideMath.glowName) ? PeptideMath.glowSubtitle : nil,
                        selected: compound == option
                    ) {
                        pick(option)
                    }
                }
            }
            PeptideInputField(title: "Compound name", text: $compound, prompt: "Or type a compound")
        }
    }

    /// Glow fills in the three component NAMES only. Amounts stay empty.
    private func pick(_ option: String) {
        compound = option
        if PeptideMath.sameCompound(option, PeptideMath.glowName) {
            isBlend = true
            components = PeptideMath.glowComponentNames.map {
                ComponentDraft(id: UUID().uuidString, name: $0, amountText: "", unit: nil)
            }
        } else if isBlend || components.count != 1 {
            isBlend = false
            components = [ComponentDraft(id: UUID().uuidString, name: "", amountText: "", unit: components.first?.unit)]
        }
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Blend (several compounds in one vial)", isOn: $isBlend)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .tint(IronTheme.blood)
            ForEach($components) { $component in
                componentEditor($component)
            }
            if isBlend {
                Button {
                    components.append(ComponentDraft(id: UUID().uuidString, name: "", amountText: "", unit: nil))
                } label: {
                    Label("Add component", systemImage: "plus")
                }
                .buttonStyle(IronCompactButtonStyle())
            }
        }
    }

    private func componentEditor(_ component: Binding<ComponentDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isBlend {
                HStack(alignment: .bottom, spacing: 8) {
                    PeptideInputField(title: "Component", text: component.name, prompt: "Name")
                    if components.count > 1 {
                        Button {
                            components.removeAll { $0.id == component.wrappedValue.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(IronTheme.brass)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove component")
                    }
                }
            }
            PeptideInputField(
                title: isBlend ? "Amount of \(component.wrappedValue.name.isEmpty ? "component" : component.wrappedValue.name) in vial" : "Amount in vial",
                text: component.amountText,
                prompt: "From the vial label",
                keyboard: .decimalPad,
                monospaced: true
            )
            HStack(spacing: 8) {
                ForEach(PeptideMath.vialUnitOptions, id: \.self) { unit in
                    PeptideChoiceChip(title: unit, selected: component.wrappedValue.unit == unit) {
                        component.wrappedValue.unit = unit
                    }
                }
            }
        }
        .padding(isBlend ? 10 : 0)
        .background(isBlend ? IronTheme.surface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous))
    }

    private var mixedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Mixed date known", isOn: $mixedKnown)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .tint(IronTheme.blood)
            if mixedKnown {
                DatePicker("Mixed on", selection: $mixedOn, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    /// The same tick as Reconstitute's step 3: it stamps when. Changing an
    /// amount or the diluent unticks it.
    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                confirmed.toggle()
                confirmedAt = confirmed ? Date() : nil
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(confirmed ? IronTheme.olive : IronTheme.textSecondary)
                    Text("I mixed this vial with exactly this diluent volume.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("I mixed this vial with exactly this diluent volume")
            .accessibilityValue(confirmed ? "Ticked" : "Not ticked")
            .accessibilityAddTraits(confirmed ? .isSelected : [])
            Text(confirmed
                ? "Confirmed by you" + (confirmedAt.map { " · " + PeptideMath.shortDateTime($0) } ?? "") + "."
                : "Without this, concentration and remaining volume are not shown.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: components) { _, _ in unconfirm() }
        .onChange(of: diluentText) { _, _ in unconfirm() }
    }

    private func unconfirm() {
        confirmed = false
        confirmedAt = nil
    }

    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            PeptideInputField(title: "Low-stock alert (mL, optional)", text: $thresholdText, prompt: "mL", keyboard: .decimalPad, monospaced: true)
            Text("Blank means low at 20% of the diluent volume.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            PeptideFieldLabel("Notes (optional)")
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .padding(10)
                .background(IronTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        }
    }

    private func optionalNumber(_ text: String, field: String) -> (value: Double?, error: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        let value = ReconMath.toNumber(trimmed)
        guard value.isFinite, value > 0 else { return (nil, "\(field) must be a number more than 0.") }
        return (value, nil)
    }

    private func save() {
        let name = compound.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorText = "Pick or type the compound."
            return
        }
        var built: [PeptideVialComponent] = []
        for draft in components {
            let parsed = optionalNumber(draft.amountText, field: "Amount")
            if let error = parsed.error {
                errorText = error
                return
            }
            if parsed.value != nil && draft.unit == nil {
                errorText = "Pick mg, mcg or IU for each amount."
                return
            }
            let componentName = isBlend ? draft.name.trimmingCharacters(in: .whitespacesAndNewlines) : name
            built.append(PeptideVialComponent(id: draft.id, name: componentName, amount: parsed.value, unit: draft.unit ?? ""))
        }
        if !isBlend { built = Array(built.prefix(1)) }
        let diluent = optionalNumber(diluentText, field: "Diluent")
        if let error = diluent.error {
            errorText = error
            return
        }
        let threshold = optionalNumber(thresholdText, field: "Low-stock alert")
        if let error = threshold.error {
            errorText = error
            return
        }
        let edited = PeptideVial(
            id: existing?.id ?? UUID().uuidString,
            compound: name,
            isBlend: isBlend,
            components: built,
            diluentML: diluent.value,
            mixedOn: mixedKnown ? PeptideViewDates.civil(fromLocal: mixedOn) : nil,
            concentrationConfirmed: confirmed,
            concentrationConfirmedAt: confirmedAt,
            lowStockThresholdML: threshold.value,
            status: existing?.status ?? .active,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existing?.createdAt ?? Date()
        )
        store.saveVial(existing.map { $0.applyingEdit(edited) } ?? edited)
        dismiss()
    }
}
