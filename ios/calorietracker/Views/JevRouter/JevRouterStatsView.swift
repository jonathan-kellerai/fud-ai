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
    @State private var allowAppleIntelligence = JevRouterSettings.allowAppleIntelligence
    @State private var cheapModel = JevRouterSettings.cheapTextModel
    @State private var killSwitch = JevRouterSettings.killSwitch
    @State private var tieBreak = JevRouterSettings.plausibilityTieBreak

    private var gemmaSelectable: Bool { Gemma4LocalModelManager.isCurrentDeviceSelectable }
    private var appleIntelligenceAvailable: Bool { JevTierRouter.appleIntelligenceDeviceAvailable }
    private var textModels: [String] {
        let provider = AIProviderSettings.selectedTextProvider
        return provider.textModels
    }

    private var tiersOn: Bool { uses[.tierRouting] ?? JevRouterSettings.isUseEnabled(.tierRouting) }
    private var plausibilityOn: Bool { uses[.plausibility] ?? JevRouterSettings.isUseEnabled(.plausibility) }

    var body: some View {
        ForEach(JevUse.settingsOrder) { use in
            routerToggle(use.title, isOn: binding(for: use))
                .accessibilityIdentifier("settings.jevRouter.\(use.rawValue)")
            if use == .tierRouting {
                tierOptions
            }
            if use == .plausibility {
                tieBreakOptions
            }
        }
        routerToggle("Pause all Jev calls", isOn: $killSwitch)
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
        routerToggle("Allow on-device Gemma", isOn: $allowOnDevice)
            .disabled(!tiersOn || !gemmaSelectable)
            .padding(.leading, 16)
            .accessibilityIdentifier("settings.jevRouter.allowOnDevice")
            .onChange(of: allowOnDevice) { _, isOn in
                JevRouterSettings.allowOnDevice = isOn
            }
        if !gemmaSelectable {
            tierFootnote("Gemma needs an 8 GB iPhone with the model downloaded.")
        }
        routerToggle("Allow Apple Intelligence", isOn: $allowAppleIntelligence)
            .disabled(!tiersOn || !appleIntelligenceAvailable)
            .padding(.leading, 16)
            .accessibilityIdentifier("settings.jevRouter.allowAppleIntelligence")
            .onChange(of: allowAppleIntelligence) { _, isOn in
                JevRouterSettings.allowAppleIntelligence = isOn
            }
        if !appleIntelligenceAvailable {
            tierFootnote("Apple Intelligence needs iOS 26 and the on-device model.")
        } else if !tiersOn {
            tierFootnote("Turn on Model tiers to use Apple Intelligence.")
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
        routerToggle("Jev tie-break for close calls", isOn: $tieBreak)
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

    private func tierFootnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
    }

    @ViewBuilder
    private func routerToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        if title.contains(" ") {
            AccessibleSettingToggle(title: title, isOn: isOn)
                .tint(AppColors.calorie)
        } else {
            Toggle(title, isOn: isOn)
                .tint(AppColors.calorie)
        }
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
