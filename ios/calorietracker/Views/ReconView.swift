import SwiftUI

/// Reconstitute a vial, in three steps (this replaces Recon Bench):
/// 1. what's in the vial, as typed from the label;
/// 2. the plain arithmetic on those two numbers, said not to be advice;
/// 3. a tick that stamps when the user confirmed the mix.
/// Records only: nothing is suggested, and no dose is worked out.
struct ReconView: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let existing: PeptideVial?
    /// Fixed "now" (Visual QA). Nil uses the clock.
    private let referenceDate: Date?
    @State private var compound: String
    @State private var amountText: String
    @State private var unit: String?
    @State private var diluentText: String
    @State private var mixedOn: Date
    @State private var confirmedAt: Date?
    @State private var errorText: String?

    /// `vial` re-opens a single-compound vial to confirm or correct it, keeping
    /// its id (and so its draws), even one imported with no amount typed yet.
    /// `initialConfirmedAt` is for Visual QA only (step 3 already ticked).
    init(vial: PeptideVial? = nil, referenceDate: Date? = nil, initialConfirmedAt: Date? = nil) {
        let single = vial?.opensInReconstitute == true ? vial : nil
        existing = single
        self.referenceDate = referenceDate
        let component = single?.components.first
        _compound = State(initialValue: single?.compound ?? "")
        _amountText = State(initialValue: component?.amount.map(PeptideMath.number) ?? "")
        _unit = State(initialValue: component.flatMap { PeptideMath.vialUnitOptions.contains($0.unit) ? $0.unit : nil })
        _diluentText = State(initialValue: single?.diluentML.map(PeptideMath.number) ?? "")
        _mixedOn = State(initialValue: single?.mixedOn.map(PeptideViewDates.localDate(fromCivil:)) ?? (referenceDate ?? Date()))
        _confirmedAt = State(initialValue: initialConfirmedAt ?? (single?.concentrationConfirmed == true ? single?.concentrationConfirmedAt : nil))
    }

    private var arithmetic: PeptideMath.DerivationStep? {
        let amount = ReconMath.toNumber(amountText)
        let diluent = ReconMath.toNumber(diluentText)
        return PeptideMath.reconstituteArithmetic(
            amount: amount.isFinite ? amount : nil,
            unit: unit,
            diluentML: diluent.isFinite ? diluent : nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepOne
                    stepTwo
                    stepThree
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                    Button("Save vial") { save() }
                        .buttonStyle(IronPrimaryButtonStyle())
                        .accessibilityIdentifier("peptides.reconstitute.save")
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle("Reconstitute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: amountText) { _, _ in confirmedAt = nil }
            .onChange(of: unit) { _, _ in confirmedAt = nil }
            .onChange(of: diluentText) { _, _ in confirmedAt = nil }
        }
    }

    // MARK: Step 1

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReconStepTitle(text: "Step 1 of 3 · What's in the vial")
            VStack(alignment: .leading, spacing: 14) {
                compoundSection
                PeptideInputField(
                    title: "Vial amount",
                    text: $amountText,
                    prompt: "Type it from the label",
                    keyboard: .decimalPad,
                    monospaced: true
                )
                PeptideFlowLayout(spacing: 8) {
                    ForEach(PeptideMath.vialUnitOptions, id: \.self) { option in
                        PeptideChoiceChip(title: option, selected: unit == option) { unit = option }
                    }
                }
                PeptideInputField(
                    title: "Diluent added (mL)",
                    text: $diluentText,
                    prompt: "The water you added, in mL",
                    keyboard: .decimalPad,
                    monospaced: true
                )
                VStack(alignment: .leading, spacing: 4) {
                    PeptideFieldLabel("Mixed")
                    DatePicker("Mixed", selection: $mixedOn, in: ...max(Date(), mixedOn), displayedComponents: .date)
                        .labelsHidden()
                        .tint(IronTheme.brass)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ironCard(rule: true)
        }
    }

    private var compoundSection: some View {
        let options = PeptideMath.compoundOptions(
            vialCompounds: store.vialList(includeFinished: true).map(\.compound),
            loggedCompounds: store.loggedCompounds()
        )
        return VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Compound")
            if !options.isEmpty {
                PeptideFlowLayout(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        PeptideChoiceChip(title: option, selected: compound == option) { compound = option }
                    }
                }
            }
            PeptideInputField(title: "Compound name", text: $compound, prompt: options.isEmpty ? "Type the compound" : "Or type a compound")
        }
    }

    // MARK: Step 2

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReconStepTitle(text: "Step 2 of 3 · The arithmetic")
            VStack(alignment: .leading, spacing: 8) {
                Text("This is plain arithmetic on the two numbers you typed. It is not advice.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let arithmetic {
                    Text(arithmetic.text)
                        .font(.system(.title2, design: .default, weight: .black).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(arithmetic.spoken)
                } else {
                    Text("Type the vial amount, its unit and the diluent to see it.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ironCard()
        }
    }

    // MARK: Step 3

    private var stepThree: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReconStepTitle(text: "Step 3 of 3 · Confirm")
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    confirmedAt = confirmedAt == nil ? (referenceDate ?? Date()) : nil
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: confirmedAt == nil ? "square" : "checkmark.square.fill")
                            .font(.title3)
                            .foregroundStyle(confirmedAt == nil ? IronTheme.textSecondary : IronTheme.olive)
                        Text("I mixed this vial with exactly this diluent volume.")
                            .font(.system(.body, design: .rounded, weight: .semibold))
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
                .accessibilityValue(confirmedAt == nil ? "Not ticked" : "Ticked")
                .accessibilityHint("Records that you confirmed it, and when.")
                .accessibilityAddTraits(confirmedAt == nil ? [] : .isSelected)
                .accessibilityIdentifier("peptides.reconstitute.confirm")
                if let confirmedAt {
                    PeptideDetailRow(label: "Confirmed by", value: "You")
                    PeptideDetailRow(label: "Confirmed at", value: PeptideMath.shortDateTime(confirmedAt) + " ET")
                } else {
                    Text("Until you tick this, the vial shows: Concentration not confirmed.")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(IronTheme.rust)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ironCard()
        }
    }

    private func save() {
        if let problem = PeptideMath.reconstituteIssue(compound: compound, amountText: amountText, unit: unit, diluentText: diluentText) {
            errorText = problem
            return
        }
        guard let unit else { return }
        let vial = PeptideVial.reconstituted(
            id: existing?.id ?? UUID().uuidString,
            compound: compound,
            amount: ReconMath.toNumber(amountText),
            unit: unit,
            diluentML: ReconMath.toNumber(diluentText),
            mixedOn: PeptideViewDates.civil(fromLocal: mixedOn),
            confirmedAt: confirmedAt,
            existing: existing,
            now: referenceDate ?? Date()
        )
        store.saveVial(vial)
        if let refusal = store.changeRefusal {
            errorText = refusal
            return
        }
        dismiss()
    }
}

/// "STEP 1 OF 3 · ..." in brass, condensed heavy, wrapping at large sizes.
struct ReconStepTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .default, weight: .black))
            .fontWidth(.condensed)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.brass)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
