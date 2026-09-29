import SwiftUI

struct JevRouterStatsView: View {
    var telemetry: JevRouterTelemetry

    init(telemetry: JevRouterTelemetry = .shared) {
        self.telemetry = telemetry
    }

    var body: some View {
        List {
            Section {
                Text(summary)
                    .font(.system(.body, design: .rounded))
            } header: {
                IronSectionTitle(title: "Summary")
            }
            .listRowBackground(AppColors.appCard)

            let activeUses = JevUse.allCases.filter { use in
                Self.hasActivity(telemetry.snapshot.uses[use.rawValue] ?? JevUseStats())
            }
            if activeUses.isEmpty {
                Section {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            } else {
                ForEach(activeUses) { use in
                    let stats = telemetry.snapshot.uses[use.rawValue] ?? JevUseStats()
                    Section {
                        LabeledContent("Requests", value: "\(stats.requests)")
                        LabeledContent("Cache hits", value: "\(stats.cacheHits)")
                        LabeledContent("Accepted", value: "\(stats.accepted)")
                        LabeledContent("Local shortcuts", value: "\(stats.localShortcuts)")
                        LabeledContent("AI calls avoided", value: "\(stats.llmCallsAvoided)")
                    } header: {
                        IronSectionTitle(title: use.title)
                    }
                    .listRowBackground(AppColors.appCard)
                }
            }

            Section {
                if telemetry.decisions.isEmpty {
                    Text("No decisions yet this session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(telemetry.decisions.reversed()) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.use.title)
                                .font(.system(.body, design: .rounded, weight: .medium))
                            Text(decisionDetail(record))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } header: {
                IronSectionTitle(title: "Recent decisions (this session)")
            }
            .listRowBackground(AppColors.appCard)
            .accessibilityIdentifier("jevRouter.stats.decisions")

            Section {
                Button("Reset stats", role: .destructive) { telemetry.reset() }
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("Router stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: String {
        let calls = telemetry.netCallsAvoided
        let callLabel = calls == 1 ? "AI call" : "AI calls"
        let p50 = telemetry.percentile(0.5).map { "\($0) ms" } ?? "—"
        return "Saved ~\(calls) \(callLabel) · p50 \(p50) · \(spendLabel) Jev spend"
    }

    private var spendLabel: String {
        let spend = telemetry.estimatedSpend
        let formatted = String(format: "%.4f", spend)
        if formatted == "0.0000" { return "< $0.01" }
        return "~$\(formatted)"
    }

    private func decisionDetail(_ record: JevDecisionRecord) -> String {
        var parts: [String] = []
        if !record.preview.isEmpty { parts.append(record.preview) }
        parts.append(outcomeText(record))
        if let latencyMs = record.latencyMs { parts.append("\(latencyMs) ms") }
        parts.append(record.source.rawValue)
        return parts.joined(separator: " · ")
    }

    private func outcomeText(_ record: JevDecisionRecord) -> String {
        if record.result == "fallback" {
            let reason = record.reason?.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .lowercased() ?? "fallback"
            return "fell back (\(reason))"
        }
        if record.result == "override" { return "user override" }
        return record.result
    }

    private static func hasActivity(_ stats: JevUseStats) -> Bool {
        stats.requests > 0
            || stats.cacheHits > 0
            || stats.localShortcuts > 0
            || stats.accepted > 0
            || stats.userOverrides > 0
            || stats.llmCallsAvoided > 0
            || stats.inputTokens > 0
            || !stats.fallbacks.isEmpty
            || !stats.skipped.isEmpty
    }
}

struct JevRouterAdvancedSection: View {
    @State private var uses: [JevUse: Bool] = [:]
    @State private var allowOnDevice = JevRouterSettings.allowOnDevice
    @State private var cheapModel = JevRouterSettings.cheapTextModel
    @State private var killSwitch = JevRouterSettings.killSwitch
    @State private var tieBreak = JevRouterSettings.plausibilityTieBreak

    private var gemmaSelectable: Bool { Gemma4LocalModelManager.isCurrentDeviceSelectable }
    private var textModels: [String] {
        let provider = AIProviderSettings.selectedTextProvider
        return provider.textModels
    }

    private var tiersOn: Bool { uses[.tierRouting] ?? JevRouterSettings.isUseEnabled(.tierRouting) }
    private var plausibilityOn: Bool {
        JevUse.plausibility.isShipped && (uses[.plausibility] ?? JevRouterSettings.isUseEnabled(.plausibility))
    }

    var body: some View {
        ForEach(JevUse.settingsOrder) { use in
            if use.isShipped {
                Toggle(use.title, isOn: binding(for: use))
                    .tint(AppColors.calorie)
                    .accessibilityIdentifier("settings.jevRouter.\(use.rawValue)")
            } else {
                Toggle(use.title, isOn: .constant(false))
                    .tint(AppColors.calorie)
                    .disabled(true)
                    .accessibilityIdentifier("settings.jevRouter.\(use.rawValue)")
                Text("Coming soon")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if use == .tierRouting {
                tierOptions
            }
            if use == .plausibility {
                tieBreakOptions
            }
        }
        Toggle("Pause all Jev calls", isOn: $killSwitch)
            .tint(AppColors.calorie)
            .accessibilityIdentifier("settings.jevRouter.killSwitch")
            .onChange(of: killSwitch) { _, isOn in
                JevRouterSettings.killSwitch = isOn
            }
        NavigationLink {
            JevRouterStatsView()
        } label: {
            Text("Router stats")
        }
        .accessibilityIdentifier("settings.jevRouter.stats")
        .onAppear {
            var seeded: [JevUse: Bool] = [:]
            for use in JevUse.allCases where use.isSettingsToggle {
                seeded[use] = JevRouterSettings.isUseEnabled(use)
            }
            uses = seeded
        }
    }

    @ViewBuilder
    private var tierOptions: some View {
        Toggle("Allow on-device Gemma", isOn: $allowOnDevice)
            .tint(AppColors.calorie)
            .disabled(!tiersOn || !gemmaSelectable)
            .padding(.leading, 16)
            .onChange(of: allowOnDevice) { _, isOn in
                JevRouterSettings.allowOnDevice = isOn
            }
        if !gemmaSelectable {
            Text("Gemma needs an 8 GB iPhone with the model downloaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        }
        Picker("Cheaper text model", selection: $cheapModel) {
            Text("None").tag("")
            ForEach(textModels, id: \.self) { model in
                Text(AIProvider.friendlyModelName(model)).tag(model)
            }
        }
        .disabled(!tiersOn)
        .padding(.leading, 16)
        .onChange(of: cheapModel) { _, model in
            JevRouterSettings.cheapTextModel = model
        }
    }

    @ViewBuilder
    private var tieBreakOptions: some View {
        Toggle("Jev tie-break for close calls", isOn: $tieBreak)
            .tint(AppColors.calorie)
            .disabled(!plausibilityOn)
            .padding(.leading, 16)
            .accessibilityIdentifier("settings.jevRouter.plausibilityTieBreak")
            .onChange(of: tieBreak) { _, isOn in
                JevRouterSettings.plausibilityTieBreak = isOn
            }
        Text("The tie-break sends relative facts as text, never photos or absolute body weight. It stays off until you turn it on.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
    }

    private func binding(for use: JevUse) -> Binding<Bool> {
        Binding(
            get: { uses[use] ?? JevRouterSettings.isUseEnabled(use) },
            set: { isOn in
                uses[use] = isOn
                JevRouterSettings.setUseEnabled(use, isOn)
            }
        )
    }
}
