//
//  CCStepFormSheet.swift
//  calorietracker
//
//  JL Physical — start and end positions for one Convict Conditioning step.
//  Step names and targets come from the bridge; art and cues are bundled.
//

import SwiftUI
import UIKit

/// Opened from a ladder step row, the stats panel and the logger's ladder hint.
/// Previous/next chevrons preview neighbouring rungs without leaving the sheet.
struct CCStepFormSheet: View {
    let series: CCSeriesState
    let rule: CCLadderRule?

    @State private var stepNumber: Int
    @State private var phase: CCStepArt.Phase = .start
    @State private var width: CGFloat = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Below this sheet width two squares are too small to read, so one shows at a time.
    private static let sideBySideMinWidth: CGFloat = 340

    init(series: CCSeriesState, rule: CCLadderRule?, step: Int) {
        self.series = series
        self.rule = rule
        _stepNumber = State(initialValue: step)
    }

    private var step: CCLadderStep? {
        CCLadderLogic.stepInfo(stepNumber, in: series)
    }

    private var cue: CCFormCue? {
        CCFormCues.cue(series: series.series, step: stepNumber)
    }

    private var showsOneImage: Bool {
        dynamicTypeSize.isAccessibilitySize || (width > 0 && width < Self.sideBySideMinWidth)
    }

    private var title: String {
        guard let step else { return "Step \(stepNumber)" }
        return "Step \(stepNumber) · \(step.name)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stepHeader
                    images
                    details
                }
                .padding()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(IronTheme.canvas)
            .navigationTitle(series.label.isEmpty ? series.series : series.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(IronTheme.canvas)
    }

    // MARK: Header

    private var stepHeader: some View {
        HStack(alignment: .center, spacing: 4) {
            stepButton(offset: -1)
            Text(title)
                .font(IronTheme.heavyHeadline)
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            stepButton(offset: 1)
        }
    }

    private func stepButton(offset: Int) -> some View {
        let neighbour = CCLadderLogic.stepInfo(stepNumber + offset, in: series)
        let isPrevious = offset < 0
        return Button {
            if let neighbour { stepNumber = neighbour.step }
        } label: {
            Image(systemName: isPrevious ? "chevron.left" : "chevron.right")
                .font(.headline.weight(.heavy))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(neighbour == nil ? IronTheme.textTertiary.opacity(0.4) : IronTheme.textPrimary)
        .disabled(neighbour == nil)
        .accessibilityLabel(isPrevious ? "Previous step" : "Next step")
        .accessibilityValue(neighbour.map { "Step \($0.step), \($0.name)" } ?? "")
        .accessibilityIdentifier(isPrevious ? "ccForm.previous" : "ccForm.next")
    }

    // MARK: Images

    @ViewBuilder
    private var images: some View {
        if showsOneImage {
            VStack(spacing: 12) {
                Picker("Position", selection: $phase.animation(reduceMotion ? nil : IronTheme.motion)) {
                    ForEach(CCStepArt.Phase.allCases) { option in
                        Text(phaseTitle(option))
                            .accessibilityLabel("\(phaseTitle(option)) position")
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ccForm.phasePicker")
                ZStack {
                    stepImage(phase)
                        .id(phase)
                        .transition(.opacity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(CCStepArt.Phase.allCases) { option in
                    VStack(spacing: 6) {
                        stepImage(option)
                        Text(phaseTitle(option))
                            .font(.system(size: 13, weight: .heavy))
                            .fontWidth(.condensed)
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(IronTheme.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func phaseTitle(_ phase: CCStepArt.Phase) -> String {
        switch phase {
        case .start: "Start"
        case .end: "End"
        }
    }

    /// A square of the step art, or an SF Symbol until that ladder's art ships.
    private func stepImage(_ phase: CCStepArt.Phase) -> some View {
        let name = CCStepArt.name(series: series.series, step: stepNumber, phase: phase)
        let hasArt = UIImage(named: name) != nil
        let shape = RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if hasArt {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.largeTitle)
                        .foregroundStyle(IronTheme.textTertiary)
                }
            }
            .background(IronTheme.canvas)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(IronTheme.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cue?.altText(for: phase) ?? "\(title), \(phaseTitle(phase).lowercased()) position")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("ccForm.\(CCFormCues.key(series: series.series, step: stepNumber)).\(phase.rawValue)")
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let step, let target = CCLadderLogic.stepTargetLabel(step, series: series.series, rule: rule) {
                // Wraps rather than truncating the target at large type on iPhone SE.
                Label {
                    Text("Graduate at \(target)")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: CCLadderLogic.isHoldStep(step, series: series.series, rule: rule) ? "timer" : "flag.checkered")
                        .foregroundStyle(IronTheme.brass)
                }
                .accessibilityElement(children: .combine)
            }
            if let cue {
                ForEach(CCStepArt.Phase.allCases) { option in
                    cueList(option, cue.cues(for: option))
                }
            }
            if let step, let book = CCLadderLogic.bookText(step) {
                Text(book)
                    .font(.caption)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private func cueList(_ phase: CCStepArt.Phase, _ cues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            IronSectionTitle(title: "\(phaseTitle(phase)) position")
            ForEach(Array(cues.enumerated()), id: \.offset) { _, cue in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                        .foregroundStyle(IronTheme.blood)
                        .accessibilityHidden(true)
                    Text(cue)
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The "Form" button that opens CCStepFormSheet, shared by the stats panel and the logger.
struct CCFormButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Form", systemImage: "figure.strengthtraining.traditional")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(IronCompactButtonStyle())
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Form")
        .accessibilityHint("Shows start and end positions")
    }
}
