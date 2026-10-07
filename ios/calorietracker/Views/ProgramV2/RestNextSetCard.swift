import SwiftUI

struct RestNextSetCard: View {
    let next: RestNextSet
    let onChange: ((inout LoggedSet) -> Void) -> Void
    let onStep: (Bool, Int) -> Void
    @FocusState private var focus: Field?
    @State private var showsRPE = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum Field: Hashable { case load, reps, rpe }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT · SET \(next.step.setIndex + 1) OF \(next.exercise.sets)")
                .font(.caption.bold()).fontWidth(.condensed).foregroundStyle(IronTheme.bloodText)
            Text(next.exercise.name).font(.title2.bold()).fontWidth(.condensed).textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
            if !next.reference.isEmpty {
                Text(next.reference).font(.subheadline.monospacedDigit()).foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(next.reason).font(.subheadline).foregroundStyle(IronTheme.brass)
                .fixedSize(horizontal: false, vertical: true)
            Text("LOAD · LB").font(.caption.bold()).fontWidth(.condensed)
            HStack {
                stepButton("minus", label: "Decrease load") { onStep(true, -1) }
                TextField("Load", value: Binding<Double?>(get: { next.value.weight == 0 && next.exercise.startLoadLb != 0 ? nil : next.value.weight }, set: { value in onChange { $0.weight = value ?? 0 } }), format: .number)
                    .keyboardType(.decimalPad).focused($focus, equals: .load)
                    .font(.largeTitle.bold().monospacedDigit()).multilineTextAlignment(.center)
                    .frame(minWidth: 56, minHeight: 56).contentShape(Rectangle()).accessibilityLabel("Load, pounds")
                stepButton("plus", label: "Increase load") { onStep(true, 1) }
            }
            if !typeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach([-10, -5, 0, 5, 10], id: \.self) { delta in
                            Button(delta == 0 ? "Same" : delta > 0 ? "+\(delta)" : "\(delta)") {
                                onChange { $0 = next.quickLoad(delta) }
                            }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                .buttonStyle(.plain).foregroundStyle(IronTheme.brass)
                        }
                    }
                }
            }
            Text("\(next.isHold ? "HOLD SECONDS" : "REPS") · \(next.exercise.reps)").font(.caption.bold()).fontWidth(.condensed)
            HStack {
                stepButton("minus", label: next.isHold ? "Decrease hold seconds" : "Decrease reps") { onStep(false, -1) }
                TextField(next.isHold ? "Sec" : "Reps", value: Binding(get: { next.value.reps }, set: { value in onChange { $0.reps = value } }), format: .number)
                    .keyboardType(.numberPad).focused($focus, equals: .reps)
                    .font(.largeTitle.bold().monospacedDigit()).multilineTextAlignment(.center)
                    .frame(minWidth: 56, minHeight: 56).contentShape(Rectangle()).accessibilityLabel(next.isHold ? "Hold seconds" : "Reps")
                stepButton("plus", label: next.isHold ? "Increase hold seconds" : "Increase reps") { onStep(false, 1) }
            }
            if !typeSize.isAccessibilitySize && !next.repChoices.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(next.repChoices, id: \.self) { reps in
                            Button("\(reps)") { onChange { $0.reps = reps } }
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                .buttonStyle(.plain).foregroundStyle(IronTheme.brass)
                        }
                    }
                }
            }
            Text("RIR · TARGET \(RIRTargetParser.target(for: next.exercise))").font(.caption.bold()).fontWidth(.condensed)
                .fixedSize(horizontal: false, vertical: true)
            RIRChips(value: next.value.rir, targets: next.targetChips) { value in onChange { $0.rir = value } }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if showsRPE {
                TextField("RPE", text: Binding(get: { next.value.rpeText }, set: { value in onChange { $0.rpeText = value } }))
                    .keyboardType(.decimalPad).focused($focus, equals: .rpe)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityLabel("RPE, rate of perceived exertion")
            } else {
                Button("RPE…") { showsRPE = true; focus = .rpe }
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).buttonStyle(.plain)
            }
        }
        .padding().ironCard(rule: true)
        .toolbar {
            if focus != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("−step") { onStep(focus == .load, -1) }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    Button("+step") { onStep(focus == .load, 1) }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    Spacer(minLength: 0)
                    Button("Next ›") { focus = focus == .load ? .reps : focus == .reps && showsRPE ? .rpe : nil }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    Button("Done") { focus = nil }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.bold()).frame(width: 56, height: 56).contentShape(Rectangle())
                .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
