//
//  CCLaddersView.swift
//  calorietracker
//
//  JL Physical — Train tab "Ladders" mode. One rail per Convict Conditioning
//  series. Step names, ranges, targets and readiness all come from the bridge.
//

import SwiftUI

// MARK: - Train mode switch

enum TrainMode: String, CaseIterable, Identifiable {
    case today = "Today"
    case ladders = "Ladders"

    var id: String { rawValue }
}

/// Two-segment switch in Iron & Blood colors. A system segmented Picker only
/// takes theme colors through global UISegmentedControl appearance, which
/// would leak into every other screen. The selected segment is raised, bone
/// text over a blood underline; each segment is at least 44 pt tall.
struct TrainModeSwitch: View {
    @Binding var mode: TrainMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrainMode.allCases) { option in
                let selected = option == mode
                Button {
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 15, weight: .heavy))
                        .fontWidth(.condensed)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? IronTheme.textPrimary : IronTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? IronTheme.surfaceRaised : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle()
                                    .fill(IronTheme.blood)
                                    .frame(height: IronTheme.underlineWidth)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .padding(2)
        .background(IronTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                .strokeBorder(IronTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Train mode")
    }
}

// MARK: - Memory cache

/// Last good ladders response. Memory only; never written to disk.
enum CCLadderMemoryCache {
    static var last: CCLaddersResponse?
}

// MARK: - Save error

/// The last failed step change. Shared so it survives switching Today | Ladders;
/// cleared only by the Dismiss button.
@Observable
final class CCLadderSaveErrorStore {
    static let shared = CCLadderSaveErrorStore()
    var message: String?
}

// MARK: - Ladders screen

struct CCLaddersView: View {
    @State private var response: CCLaddersResponse? = CCLadderMemoryCache.last
    @State private var loadError: String?
    private let saveErrors = CCLadderSaveErrorStore.shared
    @State private var isSaving = false
    @State private var pendingChange: CCPendingStepChange?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let saveError = saveErrors.message {
                    CCLadderErrorBanner(
                        title: "Step change not saved",
                        message: saveError,
                        actionTitle: "Dismiss",
                        action: { saveErrors.message = nil }
                    )
                }

                if let response {
                    if let loadError {
                        CCLadderErrorBanner(
                            title: "Couldn’t refresh ladders",
                            message: loadError,
                            actionTitle: "Retry",
                            action: { Task { await load() } }
                        )
                    }
                    CCLadderRuleCard(rule: response.rule)
                    ForEach(response.series) { series in
                        CCSeriesCard(
                            series: series,
                            rule: response.rule,
                            isSaving: isSaving,
                            onChange: { direction in requestChange(series, direction: direction) }
                        )
                    }
                } else if let loadError {
                    CCLadderErrorBanner(
                        title: "Couldn’t load ladders",
                        message: loadError,
                        actionTitle: "Retry",
                        action: { Task { await load() } }
                    )
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(IronTheme.textSecondary)
                        Text("Loading ladders…")
                            .font(.subheadline)
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .ironCard()
                }
            }
            .padding()
        }
        .background(IronTheme.canvas)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            pendingChange?.title ?? "",
            isPresented: Binding(
                get: { pendingChange != nil },
                set: { presented in if !presented { pendingChange = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingChange
        ) { change in
            Button(change.confirmLabel, role: change.role) {
                Task { await save(change) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            Text(change.message)
        }
    }

    private func requestChange(_ series: CCSeriesState, direction: CCStepChangeDirection) {
        guard !isSaving, let request = CCLadderLogic.changeRequest(for: series, direction: direction) else { return }
        pendingChange = CCPendingStepChange(series: series, request: request)
    }

    private func load() async {
        do {
            let fresh = try await CCLadderClient.fetchLadders(settings: NeonBridgeService.shared.settings)
            response = fresh
            CCLadderMemoryCache.last = fresh
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = CCLadderClient.userMessage(for: error)
        }
    }

    private func save(_ change: CCPendingStepChange) async {
        pendingChange = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await CCLadderClient.postEvent(change.request, settings: NeonBridgeService.shared.settings)
            await load()
        } catch {
            // Stays on screen until the user dismisses it.
            saveErrors.message = CCLadderClient.userMessage(for: error)
        }
    }
}

// MARK: - Pending change

struct CCPendingStepChange: Identifiable {
    let seriesLabel: String
    let targetName: String?
    let request: CCLadderEventRequest

    var id: String { "\(request.series)-\(request.eventType)-\(request.toStep)" }

    init(series: CCSeriesState, request: CCLadderEventRequest) {
        self.seriesLabel = series.label.isEmpty ? series.series : series.label
        self.targetName = series.steps.first { $0.step == request.toStep }?.name
        self.request = request
    }

    private var isAdvance: Bool { request.eventType == CCStepChangeDirection.advance.rawValue }

    var role: ButtonRole? {
        if isAdvance { return nil }
        return .destructive
    }

    var title: String {
        isAdvance ? "Advance \(seriesLabel)?" : "Go back a step on \(seriesLabel)?"
    }

    var confirmLabel: String {
        isAdvance ? "Advance to step \(request.toStep)" : "Go back to step \(request.toStep)"
    }

    var message: String {
        let destination = targetName.map { "step \(request.toStep), \($0)" } ?? "step \(request.toStep)"
        return "Moves \(seriesLabel) from step \(request.fromStep) to \(destination). The change is saved to the bridge."
    }
}

// MARK: - Rule card

private struct CCLadderRuleCard: View {
    let rule: CCLadderRule?

    private var text: String {
        CCLadderLogic.ruleText(rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IronSectionTitle(title: "Advance rule")
            Text(text)
                .font(.subheadline)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }
}

// MARK: - Error banner

private struct CCLadderErrorBanner: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.bloodText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(IronCompactButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: true)
    }
}

// MARK: - Series card

private struct CCSeriesCard: View {
    let series: CCSeriesState
    let rule: CCLadderRule?
    let isSaving: Bool
    let onChange: (CCStepChangeDirection) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if CCLadderLogic.isSetUp(series) {
                if CCLadderLogic.isMaster(series) {
                    masterBanner
                }
                if series.currentStep == nil {
                    Text("Not started")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(IronTheme.textSecondary)
                }
                rail
                if let step = CCLadderLogic.currentStepInfo(series) {
                    CCStepStatsPanel(
                        series: series,
                        rule: rule,
                        step: step,
                        isSaving: isSaving,
                        onChange: onChange
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not set up yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                    Text("The bridge sent no steps for this ladder. Update the bridge, then pull to refresh.")
                        .font(.footnote)
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(series.series)
                .font(.system(size: 20, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.bloodText)
            Text(series.label)
                .font(IronTheme.heavyHeadline)
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            if CCLadderLogic.isSetUp(series) && !series.inProgram {
                Text("Not in current program")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IronTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                            .strokeBorder(IronTheme.hairline, lineWidth: 1)
                    }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var masterBanner: some View {
        Text("Master level")
            .font(IronTheme.heavyHeadline)
            .fontWidth(.condensed)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.canvas)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(IronTheme.brass, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(series.steps.sorted { $0.step < $1.step }) { step in
                CCStepRow(
                    step: step,
                    status: CCLadderLogic.stepStatus(step: step.step, current: series.currentStep),
                    targetLabel: CCLadderLogic.stepTargetLabel(step, series: series.series, rule: rule)
                )
            }
        }
        .background(alignment: .leading) {
            Rectangle()
                .fill(IronTheme.hairline)
                .frame(width: 2)
                .padding(.leading, 15)
                .padding(.vertical, 8)
                .accessibilityHidden(true)
        }
    }
}

private struct CCStepRow: View {
    let step: CCLadderStep
    let status: CCStepStatus
    /// Graduate-at target ("3×50", "2:00 hold"); nil on older bridges.
    let targetLabel: String?

    /// Older bridges only send the working range.
    private var detailText: String? {
        if let targetLabel { return "Graduate at \(targetLabel)" }
        if let workingReps = step.workingReps, !workingReps.isEmpty { return "\(workingReps) reps" }
        return nil
    }

    private var textColor: Color {
        switch status {
        case .current: IronTheme.textPrimary
        case .done: IronTheme.textSecondary
        case .upcoming: IronTheme.textTertiary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            marker
            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.subheadline.weight(status == .current ? .heavy : .regular))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let detailText {
                    Text(detailText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(status == .current ? IronTheme.textPrimary : IronTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .background(
            status == .current ? IronTheme.blood : Color.clear,
            in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var marker: some View {
        ZStack {
            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                .fill(status == .current ? IronTheme.canvas : IronTheme.surfaceRaised)
            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                .strokeBorder(status == .done ? IronTheme.brass : IronTheme.hairline, lineWidth: 1)
            if status == .done {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(IronTheme.brass)
            } else {
                Text("\(step.step)")
                    .font(.system(size: 14, weight: .heavy))
                    .fontWidth(.condensed)
                    .foregroundStyle(status == .current ? IronTheme.textPrimary : IronTheme.textTertiary)
            }
        }
        .frame(width: 32, height: 32)
    }

    private var accessibilityText: String {
        let state: String
        switch status {
        case .current: state = "current step"
        case .done: state = "done"
        case .upcoming: state = "upcoming"
        }
        let detail = detailText.map { ", \($0)" } ?? ""
        return "Step \(step.step), \(step.name)\(detail), \(state)"
    }
}

// MARK: - Stats panel

private struct CCStepStatsPanel: View {
    let series: CCSeriesState
    let rule: CCLadderRule?
    let step: CCLadderStep
    let isSaving: Bool
    let onChange: (CCStepChangeDirection) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isHold: Bool {
        CCLadderLogic.isHoldSeries(series, rule: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Step \(step.step) · \(step.name)")
                .fixedSize(horizontal: false, vertical: true)

            if let graduateAt = CCLadderLogic.graduateAtText(series, rule: rule) {
                // Wraps rather than truncating the target at large type on iPhone SE.
                Label {
                    Text(graduateAt)
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: isHold ? "timer" : "flag.checkered")
                        .foregroundStyle(IronTheme.brass)
                }
                .accessibilityElement(children: .combine)
            }
            if let book = CCLadderLogic.bookText(step) {
                Text(book)
                    .font(.caption)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let workingReps = step.workingReps, !workingReps.isEmpty {
                statRow("Working range", "\(workingReps) reps")
            }
            statRow("Streak", "\(series.streak) / \(series.requiredStreak)")
            if let since = series.since {
                statRow("Since", CCLadderLogic.displayDate(since))
            }

            readiness

            repProgress

            recentSessions

            if CCLadderLogic.showsAdvance(series) {
                Button {
                    onChange(.advance)
                } label: {
                    Text("Advance to step \(step.step + 1)")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(IronPrimaryButtonStyle(enabled: !isSaving))
                .disabled(isSaving)
            }
            if CCLadderLogic.showsGoBack(series) {
                Button {
                    onChange(.regress)
                } label: {
                    Text("Go back a step")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(IronCompactButtonStyle())
                .disabled(isSaving)
            }
            if isSaving {
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(IronTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(fill: IronTheme.surfaceRaised)
    }

    /// Within-step progress. improved == true is a positive sign even before Ready.
    @ViewBuilder
    private var repProgress: some View {
        if let text = CCLadderLogic.progressText(series.progress, isHold: isHold) {
            let improving = CCLadderLogic.isImproving(series)
            Label {
                Text(text)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(improving ? IronTheme.olive : IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: improving ? "arrow.up.right" : "chart.line.uptrend.xyaxis")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(improving ? IronTheme.olive : IronTheme.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(improving ? "Improving. \(text)" : text)
        }
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var readiness: some View {
        if series.ready {
            Text("Ready")
                .font(IronTheme.heavyHeadline)
                .fontWidth(.condensed)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.brass)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Not ready")
                    .font(IronTheme.heavyHeadline)
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textSecondary)
                ForEach(CCLadderLogic.readinessReasons(for: series), id: \.self) { reason in
                    Text("• \(reason)")
                        .font(.footnote)
                        .foregroundStyle(IronTheme.rust)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSessions: some View {
        let sessions = CCLadderLogic.recentSessions(series)
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent sessions")
                .font(.system(size: 13, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textSecondary)
            if sessions.isEmpty {
                Text("No sessions logged yet.")
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textTertiary)
            } else {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        let heading = [CCLadderLogic.displayDate(session.sessionDate), session.exercise ?? ""]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        Text(heading)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(session.countsTowardCurrentStep ? IronTheme.textPrimary : IronTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(CCLadderLogic.setsSummary(session.sets, isHold: isHold && session.countsTowardCurrentStep))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(session.qualifying ? IronTheme.brass : IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let totals = CCLadderLogic.sessionTotalsText(session, isHold: isHold && session.countsTowardCurrentStep) {
                            Text(totals)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(IronTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if CCLadderLogic.showsRepProgress(session) {
                            Label("Rep progress", systemImage: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(IronTheme.olive)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
