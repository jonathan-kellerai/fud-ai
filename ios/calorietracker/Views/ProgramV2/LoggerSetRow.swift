import SwiftUI

/// Set presentation only; the logger supplies values and handles all edits.
struct LoggerSetRow: View {
    let setIndex: Int
    let set: LoggedSet
    let startLoadLb: Double?
    let isHold: Bool
    let isCurrent: Bool
    let isPersonalRecord: Bool
    let onChange: (LoggedSet) -> Void
    let onLog: () -> Void
    let onRemove: () -> Void

    @ScaledMetric(relativeTo: .body) private var inputScale: CGFloat = 1

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                setNumber
                loadField
                rowLabel("lb ×")
                repsField
                rowLabel("RIR")
                rirField
                rpeField
                logSetButton
                removeSetButton
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    setNumber
                    loadField
                    rowLabel("lb ×")
                    repsField
                    rowLabel(isHold ? "sec" : "reps")
                }
                HStack(spacing: 8) {
                    rowLabel("RIR")
                    rirField
                    rpeField
                    logSetButton
                    removeSetButton
                }
                .padding(.leading, 28)
            }
        }
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            if isCurrent {
                Rectangle()
                    .fill(IronTheme.blood)
                    .frame(width: IronTheme.ruleWidth)
            }
        }
    }

    private var setNumber: some View {
        HStack(spacing: 8) {
            Text("\(setIndex + 1)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(IronTheme.textSecondary)
                .frame(width: 20)
            if isPersonalRecord {
                Text("PR")
                    .font(.system(size: 11, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(0.6)
                    .foregroundStyle(IronTheme.brass)
                    .fixedSize()
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private func change(_ edit: (inout LoggedSet) -> Void) {
        var next = set
        edit(&next)
        onChange(next)
    }

    private var loadField: some View {
        let showsBlankLoad = set.weight == 0 && startLoadLb != 0
        return TextField("Load", value: Binding<Double?>(
            get: { showsBlankLoad ? nil : set.weight },
            set: { newValue in change { $0.weight = newValue ?? 0 } }
        ), format: .number)
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: 60)
    }

    private var repsField: some View {
        TextField(isHold ? "Sec" : "Reps", value: Binding<Int?>(
            get: { set.reps == 0 ? nil : set.reps },
            set: { newValue in change { $0.reps = newValue ?? 0 } }
        ), format: .number)
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: scaledInputWidth(64))
        .accessibilityLabel(isHold ? "Hold seconds" : "Reps")
    }

    private var rirField: some View {
        TextField("", value: Binding(
            get: { set.rir },
            set: { newValue in change { $0.rir = newValue } }
        ), format: .number)
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: 40)
        .onSubmit(onLog)
    }

    private var rpeField: some View {
        TextField("RPE", text: Binding(
            get: { set.rpeText },
            set: { newValue in change { $0.rpeText = newValue } }
        ))
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
        .frame(width: scaledInputWidth(60))
        .accessibilityLabel("RPE, rate of perceived exertion")
    }

    private func scaledInputWidth(_ base: CGFloat) -> CGFloat {
        (base * min(max(inputScale, 1), 1.4)).rounded()
    }

    private var logSetButton: some View {
        Button(action: onLog) {
            Image(systemName: set.reps > 0 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(set.reps > 0 ? IronTheme.olive : IronTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log set")
    }

    private var removeSetButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(IronTheme.bloodText)
        }
        .buttonStyle(.plain)
    }
}
