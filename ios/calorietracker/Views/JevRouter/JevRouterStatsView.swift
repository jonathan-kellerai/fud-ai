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

            ForEach(JevUse.allCases) { use in
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

            Section {
                if telemetry.decisions.isEmpty {
                    Text("No decisions yet this session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(telemetry.decisions.reversed()) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.use.title)
                                .font(.system(.body, design: .rounded, weight: .medium))
                            Text(record.preview.isEmpty ? record.result : record.preview)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } header: {
                IronSectionTitle(title: "Recent decisions")
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
        let p50 = telemetry.percentile(0.5).map { "\($0) ms" } ?? "—"
        let spend = String(format: "~$%.4f", telemetry.estimatedSpend)
        return "Saved ~\(calls) AI calls · p50 \(p50) · \(spend) Jev spend"
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

    var body: some View {
        ForEach(JevUse.allCases.filter(\.isSettingsToggle)) { use in
            Toggle(use.title, isOn: binding(for: use))
                .tint(AppColors.calorie)
                .accessibilityIdentifier("settings.jevRouter.\(use.rawValue)")
        }
        Toggle("Allow on-device Gemma", isOn: $allowOnDevice)
            .tint(AppColors.calorie)
            .disabled(!gemmaSelectable)
            .onChange(of: allowOnDevice) { _, isOn in
                JevRouterSettings.allowOnDevice = isOn
            }
        if !gemmaSelectable {
            Text("Gemma needs an 8 GB iPhone with the model downloaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Picker("Cheaper text model", selection: $cheapModel) {
            Text("None").tag("")
            ForEach(textModels, id: \.self) { model in
                Text(AIProvider.friendlyModelName(model)).tag(model)
            }
        }
        .onChange(of: cheapModel) { _, model in
            JevRouterSettings.cheapTextModel = model
        }
        Toggle("Jev tie-break for close calls", isOn: $tieBreak)
            .tint(AppColors.calorie)
            .accessibilityIdentifier("settings.jevRouter.plausibilityTieBreak")
            .onChange(of: tieBreak) { _, isOn in
                JevRouterSettings.plausibilityTieBreak = isOn
            }
        Text("The tie-break sends relative facts as text, never photos or absolute body weight. It stays off until you turn it on.")
            .font(.footnote)
            .foregroundStyle(.secondary)
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
