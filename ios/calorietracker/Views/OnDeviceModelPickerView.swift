import SwiftUI

/// Settings hub row that opens the picker. The subtitle follows the saved choice.
struct OnDeviceModelHubRow: View {
    @AppStorage(OnDeviceModelSettings.choiceKey) private var choiceRaw = OnDeviceModelChoice.off.rawValue

    var body: some View {
        NavigationLink {
            OnDeviceModelPickerView()
        } label: {
            SettingsHubRowLabel(
                title: "On-device model",
                systemImage: "cpu",
                subtitle: (OnDeviceModelChoice(rawValue: choiceRaw) ?? .off).shortTitle
            )
        }
        .accessibilityIdentifier("settings.onDeviceModel.picker")
    }
}

/// Settings → AI → On-device model. One choice for text food logging, workout parsing and
/// Coach text chat. Photos and Coach images stay on the cloud provider.
struct OnDeviceModelPickerView: View {
    /// Visual QA only: fixed choice and availability instead of live device checks and UserDefaults.
    private let preview: OnDeviceModelState?

    @State private var choice: OnDeviceModelChoice
    @State private var notice: OnDeviceFallbackNotice?
    @State private var gemmaManager = Gemma4LocalModelManager.shared
    @State private var availabilityRevision = 0

    init(preview: OnDeviceModelState? = nil, previewNotice: OnDeviceFallbackNotice? = nil) {
        self.preview = preview
        _choice = State(initialValue: preview?.choice ?? OnDeviceModelSettings.choice)
        _notice = State(initialValue: preview == nil ? OnDeviceModelSettings.lastFallback : previewNotice)
    }

    private var modelState: OnDeviceModelState {
        _ = availabilityRevision
        var current = preview ?? OnDeviceModelState.current
        current.choice = choice
        return current
    }

    var body: some View {
        let snapshot = modelState
        List {
            Section {
                ForEach(OnDeviceModelChoice.allCases) { option in
                    optionRow(option, state: snapshot)
                }
            } header: {
                IronSectionTitle(title: "On-device model")
            } footer: {
                Text("Text food logging, workout parsing and Coach text chat use the picked model. If it can't run, JL Physical uses your cloud text provider instead.")
            }
            .listRowBackground(AppColors.appCard)

            if let notice {
                Section {
                    Label {
                        Text(notice.line)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(IronTheme.brass)
                    }
                    .accessibilityIdentifier("settings.onDeviceModel.fallbackNotice")
                }
                .listRowBackground(AppColors.appCard)
            }

            Section {
                NavigationLink {
                    gemmaDownloadScreen
                } label: {
                    SettingsHubRowLabel(title: "Gemma 4 E2B download", systemImage: "cpu", subtitle: gemmaStatus(snapshot))
                }
                .accessibilityIdentifier("settings.onDeviceModel.gemmaDownload")
            } footer: {
                Text("Photo logging stays on your cloud provider until on-device image input is available (expected iOS 27).")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("On-device model")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard preview == nil else { return }
            gemmaManager.refresh()
            notice = OnDeviceModelSettings.lastFallback
            availabilityRevision += 1
        }
    }

    private func optionRow(_ option: OnDeviceModelChoice, state: OnDeviceModelState) -> some View {
        let availability = state.availability(of: option)
        let isSelected = choice == option
        // A selected model that stopped being available stays visible so the user can see why.
        let isEnabled = availability.isAvailable || isSelected
        return Button {
            select(option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detail(for: option, availability: availability, isSelected: isSelected))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.calorie)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("settings.onDeviceModel.\(option.rawValue)")
    }

    private func detail(
        for option: OnDeviceModelChoice,
        availability: OnDeviceModelAvailability,
        isSelected: Bool
    ) -> String {
        let base: String
        switch option {
        case .off:
            return "Every request uses your AI provider. Model tiers in Advanced AI still apply."
        case .appleFoundationModels:
            base = "System model, text only on iOS 26"
        case .gemma4:
            base = "Downloaded on demand, ~2.59 GB, Apache-2.0"
        }
        switch availability {
        case .available:
            return option == .appleFoundationModels ? "\(base) · \(appleStatus)" : "\(base) · Ready"
        case .unavailable(let reason):
            return isSelected
                ? "\(base) · \(reason). Using your cloud provider for now."
                : "\(base) · \(reason)"
        }
    }

    private var appleStatus: String {
        guard preview == nil else { return "Available on this iPhone" }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceAIService.availabilityDescription
        }
        #endif
        return "Available"
    }

    private func gemmaStatus(_ state: OnDeviceModelState) -> String {
        guard preview == nil else {
            return state.gemma.isAvailable ? "Gemma ready" : "Not downloaded"
        }
        return gemmaManager.settingsSubtitle
    }

    private var gemmaDownloadScreen: some View {
        List {
            Section {
                Gemma4ModelSettingsView {
                    availabilityRevision += 1
                }
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("Gemma 4 E2B")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ option: OnDeviceModelChoice) {
        guard option != choice else { return }
        choice = option
        // The notice described the previous model.
        notice = nil
        guard preview == nil else { return }
        OnDeviceModelSettings.choice = option
        OnDeviceModelSettings.lastFallback = nil
    }
}
