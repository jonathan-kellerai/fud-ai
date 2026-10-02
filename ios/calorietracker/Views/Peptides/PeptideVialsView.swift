//
//  PeptideVialsView.swift
//  calorietracker
//
//  The user's own vials (device only) and the peptide assistant's inventory
//  (read-only, verbatim). Remaining volume is only shown when it can be worked
//  out from the user's own vial numbers.
//

import SwiftUI

struct PeptideVialEditorTarget: Identifiable {
    let id = UUID().uuidString
    var vial: PeptideVial?
    var person: String
}

struct PeptideVialsView: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var person: String
    @State private var editorTarget: PeptideVialEditorTarget?
    @State private var showFinished = false
    @State private var finishTarget: PeptideVial?

    init(person: String = PeptidePerson.jonathan) {
        _person = State(initialValue: PeptidePerson.normalized(person))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PeptideScreenTitle(title: "Vials", subtitle: "Vials you mixed. Remaining is worked out only from your own numbers.")
                PeptidePersonToggle(person: $person)
                Button {
                    editorTarget = PeptideVialEditorTarget(vial: nil, person: person)
                } label: {
                    Label("Add vial", systemImage: "plus")
                }
                .buttonStyle(IronPrimaryButtonStyle())
                activeSection
                finishedSection
                PeptideAgentInventorySection()
                PeptideFooter()
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Vials")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refreshIfStale() }
        .sheet(item: $editorTarget) { target in
            PeptideVialEditor(vial: target.vial, person: target.person)
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
            Text("Finished vials stay in the list and keep their logged doses.")
        }
    }

    private var finishDialogBinding: Binding<Bool> {
        Binding(
            get: { finishTarget != nil },
            set: { shown in if !shown { finishTarget = nil } }
        )
    }

    @ViewBuilder
    private var activeSection: some View {
        let vials = store.personVials(person: person)
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Active")
            if vials.isEmpty {
                Text("No active vials for \(PeptidePerson.name(person)).")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            ForEach(vials) { vial in
                PeptideVialCard(
                    vial: vial,
                    onEdit: { editorTarget = PeptideVialEditorTarget(vial: vial, person: person) },
                    onFinish: { finishTarget = vial }
                )
            }
        }
    }

    @ViewBuilder
    private var finishedSection: some View {
        let finished = store.personVials(person: person, includeFinished: true).filter { $0.status == .finished }
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(showFinished ? "Finished vials (\(finished.count))" : "Show finished vials (\(finished.count))", isOn: $showFinished)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
                    .tint(IronTheme.blood)
                if showFinished {
                    ForEach(finished) { vial in
                        PeptideVialCard(
                            vial: vial,
                            onEdit: { editorTarget = PeptideVialEditorTarget(vial: vial, person: person) },
                            onFinish: nil
                        )
                    }
                }
            }
        }
    }
}

struct PeptideVialCard: View {
    @Environment(PeptideLogStore.self) private var store
    let vial: PeptideVial
    var onEdit: (() -> Void)?
    var onFinish: (() -> Void)?

    var body: some View {
        let remaining = store.remaining(for: vial)
        return VStack(alignment: .leading, spacing: 10) {
            header(remaining)
            componentsBlock
            concentrationBlock
            remainingBlock(remaining)
            Text(remaining.linkedCount == 1 ? "1 dose logged from this vial" : "\(remaining.linkedCount) doses logged from this vial")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
            linkedInventory
            buttons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: remaining.isLow)
    }

    private func header(_ remaining: PeptideMath.Remaining) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vial.displayName)
                .font(.system(size: 22, weight: .black))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PeptideFlowLayout(spacing: 6) {
                if vial.isBlend { PeptideTag(text: "Blend", tone: IronTheme.textSecondary) }
                if vial.status == .finished { PeptideTag(text: "Finished", tone: IronTheme.concrete, filled: true) }
                if remaining.isLow && vial.status == .active { PeptideTag(text: "Low stock", tone: IronTheme.rust) }
            }
        }
    }

    private var componentsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vial.components) { component in
                PeptideDetailRow(
                    label: component.name.isEmpty ? "Amount in vial" : component.name,
                    value: component.amount.map { PeptideMath.number($0) + " " + component.unit } ?? "Not entered"
                )
            }
            PeptideDetailRow(label: "Diluent", value: vial.diluentML.map { PeptideMath.number($0) + " mL" } ?? "Not entered")
            PeptideDetailRow(label: "Mixed", value: vial.mixedOn.map(ReconMath.formatDate) ?? "—")
        }
    }

    @ViewBuilder
    private var concentrationBlock: some View {
        switch PeptideMath.concentration(vial) {
        case .calculable(let list):
            VStack(alignment: .leading, spacing: 2) {
                PeptideFieldLabel("Concentration")
                ForEach(list) { item in
                    Text((vial.isBlend ? item.name + " " : "") + item.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .uncalculable(let reason):
            VStack(alignment: .leading, spacing: 2) {
                Text(vial.concentrationConfirmed ? "Concentration can't be calculated" : "Concentration not confirmed — remaining can't be calculated")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func remainingBlock(_ remaining: PeptideMath.Remaining) -> some View {
        if remaining.calculable, let left = remaining.remainingML, let total = remaining.totalML {
            VStack(alignment: .leading, spacing: 4) {
                PeptideFieldLabel("Remaining")
                Text(PeptideMath.mlText(left) + " of " + PeptideMath.mlText(total))
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .foregroundStyle(remaining.isLow ? IronTheme.rust : IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                PeptideRemainingBar(fraction: remaining.fraction ?? 0, low: remaining.isLow)
                Text(vial.lowStockThresholdML.map { "Low at " + PeptideMath.mlText($0) + " (your threshold)" } ?? "Low at 20% of the diluent (no threshold set)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(IronTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else if vial.concentrationConfirmed {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remaining can't be calculated")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(IronTheme.rust)
                Text(remaining.reason ?? "A number this needs is missing.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var linkedInventory: some View {
        if let item = store.inventoryItem(id: vial.bridgeInventoryID) {
            VStack(alignment: .leading, spacing: 4) {
                PeptideFieldLabel("Peptide assistant's vial: " + item.compound)
                PeptideAgentBadges(item: item)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if let onEdit {
                Button("Edit", action: onEdit)
                    .buttonStyle(IronCompactButtonStyle())
            }
            if let onFinish {
                Button("Finish vial", action: onFinish)
                    .font(.system(size: 15, weight: .heavy))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            }
        }
    }
}

/// Badges and warnings exactly as the peptide assistant sent them.
struct PeptideAgentBadges: View {
    let item: PeptideInventoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.badges.isEmpty {
                PeptideFlowLayout(spacing: 6) {
                    ForEach(uniqueBadges, id: \.self) { badge in
                        PeptideTag(text: badge, tone: IronTheme.brass)
                    }
                }
            }
            ForEach(Array(item.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning.text)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var uniqueBadges: [String] {
        var seen = Set<String>()
        return item.badges.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// The assistant's vial mirror. Read-only; nothing is computed from it.
struct PeptideAgentInventorySection: View {
    @Environment(PeptideLogStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "From the peptide assistant (read-only)")
            if store.inventory.isEmpty {
                Text("No inventory from the peptide assistant.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(store.inventory) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.compound.isEmpty ? "Vial" : item.compound)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let basis = item.concentrationBasis, !basis.isEmpty {
                        PeptideDetailRow(label: "Concentration basis", value: basis)
                    }
                    if let gate = item.calcGate, !gate.isEmpty {
                        PeptideDetailRow(label: "Calculation", value: gate)
                    }
                    if volumeUnavailable(item) {
                        Text(HomeV2Logic.volumeUnavailableText)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(IronTheme.rust)
                    }
                    PeptideAgentBadges(item: item)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ironCard(fill: IronTheme.surface)
            }
        }
    }

    /// Same gate rules as HomeV2Logic.volumeState: a BLOCKED gate or a NONE basis.
    private func volumeUnavailable(_ item: PeptideInventoryItem) -> Bool {
        let gate = (item.calcGate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let basis = (item.concentrationBasis ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return gate.hasPrefix("BLOCKED") || basis == "NONE"
    }
}

// MARK: - Editor

struct PeptideVialEditor: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let existing: PeptideVial?
    @State private var person: String
    @State private var compound: String
    @State private var isBlend: Bool
    @State private var components: [ComponentDraft]
    @State private var diluentText: String
    @State private var mixedKnown: Bool
    @State private var mixedOn: Date
    @State private var confirmed: Bool
    @State private var thresholdText: String
    @State private var notes: String
    @State private var inventoryID: String?
    @State private var errorText: String?
    @State private var confirmDelete = false

    struct ComponentDraft: Identifiable, Equatable {
        var id: String
        var name: String
        var amountText: String
        /// Nil until the user picks mg, mcg or IU.
        var unit: String?
    }

    init(vial: PeptideVial?, person: String) {
        existing = vial
        _person = State(initialValue: PeptidePerson.normalized(vial?.person ?? person))
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
        _thresholdText = State(initialValue: vial?.lowStockThresholdML.map(PeptideMath.number) ?? "")
        _notes = State(initialValue: vial?.notes ?? "")
        _inventoryID = State(initialValue: vial?.bridgeInventoryID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeptidePersonToggle(person: $person)
                    compoundSection
                    componentsSection
                    PeptideInputField(title: "Diluent (mL)", text: $diluentText, prompt: "mL of water you added", keyboard: .decimalPad, monospaced: true)
                    mixedSection
                    confirmSection
                    thresholdSection
                    inventoryLinkSection
                    notesSection
                    NavigationLink {
                        ReconView()
                    } label: {
                        Label("Open Recon Bench", systemImage: "cross.vial.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(IronTheme.bloodText)
                    }
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
                            .foregroundStyle(IronTheme.bloodText)
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
                Text("Logged doses stay. They just lose the link to this vial.")
            }
        }
    }

    private var compoundSection: some View {
        let options = PeptideMath.compoundOptions(
            person: person,
            inventoryCompounds: store.inventory.map(\.compound),
            loggedCompounds: store.loggedCompounds(person: person)
        )
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
                                .foregroundStyle(IronTheme.bloodText)
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

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("I mixed this vial with exactly this diluent volume", isOn: $confirmed)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .tint(IronTheme.olive)
            Text("Without this, concentration and remaining volume are not calculated.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    @ViewBuilder
    private var inventoryLinkSection: some View {
        if !store.inventory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PeptideFieldLabel("Link to the peptide assistant's vial (optional, badges only)")
                PeptideFlowLayout(spacing: 8) {
                    PeptideChoiceChip(title: "None", selected: inventoryID == nil) { inventoryID = nil }
                    ForEach(store.inventory) { item in
                        PeptideChoiceChip(title: item.compound.isEmpty ? item.id : item.compound, selected: inventoryID == item.id) {
                            inventoryID = item.id
                        }
                    }
                }
            }
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
        let vial = PeptideVial(
            id: existing?.id ?? UUID().uuidString,
            person: person,
            compound: name,
            isBlend: isBlend,
            components: built,
            diluentML: diluent.value,
            mixedOn: mixedKnown ? PeptideViewDates.civil(fromLocal: mixedOn) : nil,
            concentrationConfirmed: confirmed,
            lowStockThresholdML: threshold.value,
            bridgeInventoryID: inventoryID,
            status: existing?.status ?? .active,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existing?.createdAt ?? Date()
        )
        store.saveVial(vial)
        dismiss()
    }
}
