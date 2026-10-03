import SwiftUI

/// Presentation only: draft edits, targets and steps are supplied by the owner.
struct LoggerSetRow: View {
    let setIndex: Int
    let set: LoggedSet
    let startLoadLb: Double?
    let isHold: Bool
    let kind: SetEntryLogic.RowKind
    let isPersonalRecord: Bool
    let targetText: String
    let targetChips: Set<Int>
    let loadStep: Double
    let onEdit: () -> Void
    let onChange: ((inout LoggedSet) -> Void) -> Void
    let onStep: (Bool, Int) -> Void
    let onLog: () -> Void
    let onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focus: Field?
    @State private var showsRPE = false
    private enum Field: Hashable { case load, reps, rpe }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch kind {
            case .ghost: ghost
            case .logged: logged
            case .current: editor
            }
        }
        .font(.body.monospacedDigit())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            if kind == .current { Rectangle().fill(IronTheme.blood).frame(width: IronTheme.ruleWidth) }
        }
        .contextMenu {
            if kind != .ghost { Button("Delete set", role: .destructive, action: onRemove) }
            if kind == .current { Button("RPE…") { showsRPE = true; focus = .rpe } }
        }
        .toolbar {
            if focus != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Button(focus == .load ? "−\(LoggerFormatting.load(loadStep))" : "−1") { stepFocused(-1) }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        .disabled(focus == .rpe)
                    Button(focus == .load ? "+\(LoggerFormatting.load(loadStep))" : "+1") { stepFocused(1) }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        .disabled(focus == .rpe)
                    Spacer(minLength: 0)
                    Button("Next ›") { focus = focus == .load ? .reps : focus == .reps && showsRPE ? .rpe : nil }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    Button("Done") { focus = nil }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
            }
        }
    }

    private var ghost: some View {
        HStack(spacing: 4) {
            number
            Button(action: onEdit) {
                Text("\(set.weight == 0 && startLoadLb != 0 ? "Select load" : LoggerFormatting.load(set.weight) + " lb") × \(targetText) · target")
                    .foregroundStyle(IronTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: onLog) {
                Image(systemName: "checkmark")
                    .frame(width: 52, height: 44).contentShape(Rectangle())
                    .overlay { RoundedRectangle(cornerRadius: IronTheme.buttonRadius).stroke(IronTheme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [4])) }
            }.buttonStyle(.plain).foregroundStyle(IronTheme.textTertiary).accessibilityLabel("Log set")
        }
    }

    private var logged: some View {
        HStack(spacing: 4) {
            number
            Button(action: onEdit) {
                Text("\(LoggerFormatting.load(set.weight)) lb × \(set.reps)\(isHold ? " s" : "")\(set.rir.map { " · RIR \($0)" } ?? "")")
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit set \(setIndex + 1)")
            Button(action: onLog) {
                Image(systemName: "checkmark").frame(width: 52, height: 44).contentShape(Rectangle())
                    .background(IronTheme.olive, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
            }.buttonStyle(.plain).foregroundStyle(IronTheme.textPrimary).accessibilityLabel("Log set")
        }
    }

    private var editor: some View {
        VStack(spacing: 4) {
            if typeSize > .xxLarge {
                HStack(spacing: 4) { number; loadControl }
                repsControl
            } else {
                HStack(spacing: 4) { loadControl; repsControl }
            }
            HStack(spacing: 0) {
                RIRChips(value: set.rir, targets: targetChips) { value in onChange { $0.rir = value } }
                Button { focus = nil; onLog() } label: {
                    Image(systemName: "checkmark").frame(width: 52, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(IronTheme.bloodText).accessibilityLabel("Log set")
            }
            if showsRPE {
                TextField("RPE", text: Binding(get: { set.rpeText }, set: { value in onChange { $0.rpeText = value } }))
                    .keyboardType(.decimalPad).focused($focus, equals: .rpe)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .accessibilityLabel("RPE, rate of perceived exertion")
            }
        }
    }

    private var number: some View {
        VStack(spacing: 0) {
            Text("\(setIndex + 1)").font(.caption.bold())
            if isPersonalRecord { Text("PR").font(.caption.bold()).foregroundStyle(IronTheme.brass) }
        }.foregroundStyle(IronTheme.textSecondary).frame(width: 20)
    }

    private var loadControl: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Decrease load") { onStep(true, -1) }
            TextField("Load", value: Binding<Double?>(get: { set.weight == 0 && startLoadLb != 0 ? nil : set.weight }, set: { value in onChange { $0.weight = value ?? 0 } }), format: .number)
                .keyboardType(.decimalPad).focused($focus, equals: .load)
                .multilineTextAlignment(.center).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .accessibilityLabel("Load, pounds")
            stepButton("plus", label: "Increase load") { onStep(true, 1) }
        }
    }

    private var repsControl: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: isHold ? "Decrease hold seconds" : "Decrease reps") { onStep(false, -1) }
            TextField(isHold ? "Sec" : "Reps", value: Binding<Int?>(get: { set.reps == 0 ? nil : set.reps }, set: { value in onChange { $0.reps = value ?? 0 } }), format: .number)
                .keyboardType(.numberPad).focused($focus, equals: .reps)
                .multilineTextAlignment(.center).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .accessibilityLabel(isHold ? "Hold seconds" : "Reps")
            stepButton("plus", label: isHold ? "Increase hold seconds" : "Increase reps") { onStep(false, 1) }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(IronTheme.textPrimary).accessibilityLabel(label)
            .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
    }

    private func stepFocused(_ direction: Int) {
        if focus == .rpe { return }
        onStep(focus == .load, direction)
    }
}

struct RIRChips: View {
    let value: Int?
    let targets: Set<Int>
    let onSelect: (Int?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0...4, id: \.self) { rir in
                let selected = value.map { min($0, 4) == rir } ?? false
                Button { onSelect(selected ? nil : rir) } label: {
                    Text(rir == 4 ? "4+" : "\(rir)")
                        .font(.body.bold().monospacedDigit())
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .background(selected ? IronTheme.blood : IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
                        .overlay { RoundedRectangle(cornerRadius: IronTheme.buttonRadius).stroke(targets.contains(rir) ? IronTheme.brass : IronTheme.hairline, lineWidth: 1) }
                }.buttonStyle(.plain)
                    .foregroundStyle(selected ? IronTheme.textPrimary : targets.contains(rir) ? IronTheme.brass : IronTheme.textSecondary)
                    .accessibilityLabel("RIR \(rir == 4 ? "4 or more" : String(rir))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
