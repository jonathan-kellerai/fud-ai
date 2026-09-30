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
/// would leak into every other screen.
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? IronTheme.blood : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
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

// MARK: - Ladders screen

struct CCLaddersView: View {
    @State private var response: CCLaddersResponse? = CCLadderMemoryCache.last
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var pendingChange: CCPendingStepChange?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let saveError {
                    CCLadderErrorBanner(
                        title: "Step change not saved",
                        message: saveError,
                        actionTitle: "Dismiss",
                        action: { self.saveError = nil }
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
                            masterStep: response.rule?.masterStep ?? CCLadderLogic.defaultMasterStep,
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
            let fresh = try await CCLadderClient.fetchLadders()
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
            try await CCLadderClient.postEvent(change.request)
            saveError = nil
            await load()
        } catch {
            // Stays on screen until the user dismisses it.
            saveError = CCLadderClient.userMessage(for: error)
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
        let streak = rule?.requiredStreak ?? 2
        let sets = rule?.workingSets ?? 2
        let rir = rule?.maxRir ?? 2
        let setsText: String = sets == 2 ? "both" : "all \(sets)"
        return "Advance after \(streak) consecutive sessions with \(setsText) working sets at target reps at ≤ \(rir) RIR. The bridge decides readiness; you advance manually."
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
    let masterStep: Int
    let isSaving: Bool
    let onChange: (CCStepChangeDirection) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if CCLadderLogic.isSetUp(series) {
                if CCLadderLogic.isMaster(series, masterStep: masterStep) {
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
                        step: step,
                        masterStep: masterStep,
                        isSaving: isSaving,
                        onChange: onChange
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not set up yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                    Text("Step data not loaded. Add the CC-Tracker files to set up this ladder.")
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
                .font(.system(size: 17, weight: .heavy))
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
            .font(.system(size: 17, weight: .heavy))
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
                CCStepRow(step: step, status: CCLadderLogic.stepStatus(step: step.step, current: series.currentStep))
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
                if let workingReps = step.workingReps, !workingReps.isEmpty {
                    Text("\(workingReps) reps")
                        .font(.caption)
                        .foregroundStyle(status == .current ? IronTheme.textPrimary : IronTheme.textTertiary)
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
        let reps = step.workingReps.map { ", \($0) reps" } ?? ""
        return "Step \(step.step), \(step.name)\(reps), \(state)"
    }
}

// MARK: - Stats panel

private struct CCStepStatsPanel: View {
    let series: CCSeriesState
    let step: CCLadderStep
    let masterStep: Int
    let isSaving: Bool
    let onChange: (CCStepChangeDirection) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IronSectionTitle(title: "Step \(step.step) · \(step.name)")
                .fixedSize(horizontal: false, vertical: true)

            if let workingReps = step.workingReps, !workingReps.isEmpty {
                statRow("Working range", "\(workingReps) reps")
            }
            if let target = CCLadderLogic.targetReps(series) {
                statRow("Target", "\(target) reps")
            }
            statRow("Streak", "\(series.streak) / \(series.requiredStreak)")
            if let since = series.since {
                statRow("Since", CCLadderLogic.displayDate(since))
            }

            readiness

            recentSessions

            if CCLadderLogic.showsAdvance(series, masterStep: masterStep) {
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
                .font(.system(size: 17, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.brass)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Not ready")
                    .font(.system(size: 17, weight: .heavy))
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
                        Text(CCLadderLogic.setsSummary(session.sets))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(session.qualifying ? IronTheme.brass : IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
