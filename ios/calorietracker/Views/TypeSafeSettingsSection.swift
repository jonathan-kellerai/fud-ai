import SwiftUI

struct TypeSafeEstimateCheckSection: View {
    @State private var enabled = TypeSafeSettings.enabled
    @State private var routerEnabled = JevRouterSettings.enabled
    @State private var endpoint = TypeSafeSettings.endpoint
    @State private var model = TypeSafeSettings.model
    @State private var checkTypedMeals = TypeSafeSettings.checkTypedMeals
    @State private var apiKeyText = ""
    @State private var showAPIKey = false
    @State private var showModelPicker = false
    @State private var discovered: [CatalogModel] = []
    @State private var catalogFailed = false
    @State private var testMessage: String?
    @State private var isTesting = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        AISettingsSubsectionHeader(
            title: "TypeSafe Jev",
            systemImage: "checkmark.seal",
            infoTopic: .estimateCheck
        )

        AccessibleSettingToggle(
            title: "Check estimates with TypeSafe",
            systemImage: "checkmark.seal",
            isOn: $enabled
        )
            .tint(AppColors.calorie)
            .accessibilityIdentifier("settings.typesafe.enabled")

        AccessibleSettingToggle(
            title: "Jev router (faster, cheaper AI)",
            systemImage: "arrow.triangle.branch",
            isOn: $routerEnabled
        )
            .tint(AppColors.calorie)
            .accessibilityIdentifier("settings.jevRouter.enabled")
            .onChange(of: routerEnabled) { _, isOn in
                JevRouterSettings.enabled = isOn
            }
            .onChange(of: enabled) { _, isOn in
                TypeSafeSettings.enabled = isOn
                if isOn {
                    apiKeyText = TypeSafeSettings.apiKey(for: endpoint) ?? ""
                    loadCachedModels()
                    scheduleRefresh()
                }
            }
            .onAppear {
                apiKeyText = TypeSafeSettings.apiKey(for: endpoint) ?? ""
                loadCachedModels()
                scheduleRefresh()
            }
            .onDisappear {
                refreshTask?.cancel()
            }
            .sheet(isPresented: $showModelPicker) {
                TypeSafeModelPickerSheet(
                    model: $model,
                    presets: endpoint.presets,
                    discovered: discovered,
                    catalogFailed: catalogFailed
                )
            }

        if enabled || routerEnabled {
            Picker(selection: $endpoint) {
                ForEach(TypeSafeEndpoint.allCases) { item in
                    Text(item.title).tag(item)
                }
            } label: {
                Label("Service", systemImage: "server.rack")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .pickerStyle(.menu)
            .tint(.secondary)
            .accessibilityIdentifier("settings.typesafe.endpoint")
            .onChange(of: endpoint) { _, newEndpoint in
                TypeSafeSettings.endpoint = newEndpoint
                model = newEndpoint.defaultModel
                TypeSafeSettings.model = model
                apiKeyText = TypeSafeSettings.apiKey(for: newEndpoint) ?? ""
                testMessage = nil
                loadCachedModels()
                scheduleRefresh()
            }

            AdaptiveLabelValue {
                Label("API Key", systemImage: "key.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } value: {
                HStack {
                    Group {
                        if showAPIKey {
                            TextField(endpoint.keyPlaceholder, text: $apiKeyText)
                        } else {
                            SecureField(endpoint.keyPlaceholder, text: $apiKeyText)
                        }
                    }
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("settings.typesafe.apiKey")
                    .onChange(of: apiKeyText) { _, newValue in
                        TypeSafeSettings.setAPIKey(newValue, for: endpoint)
                        scheduleRefresh()
                    }
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showAPIKey ? "Hide API key" : "Show API key")
                }
            }

            Button {
                showModelPicker = true
            } label: {
                AdaptiveLabelValue {
                    Label {
                        Text("Model")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } icon: {
                        Image(systemName: "cpu")
                    }
                } value: {
                    HStack(spacing: 6) {
                        Text(AIProvider.friendlyModelName(model))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.typesafe.model")

            Button {
                Task { await testKey() }
            } label: {
                HStack {
                    Label("Test key", systemImage: "key.viewfinder")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if isTesting {
                        ProgressView()
                    } else if let testMessage {
                        Text(testMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isTesting || apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("settings.typesafe.test")

            AccessibleSettingToggle(
                title: "Also check typed meals",
                systemImage: "text.alignleft",
                isOn: $checkTypedMeals
            )
                .tint(AppColors.calorie)
                .accessibilityIdentifier("settings.typesafe.checkText")
                .onChange(of: checkTypedMeals) { _, isOn in
                    TypeSafeSettings.checkTypedMeals = isOn
                }
        }
    }

    private func loadCachedModels() {
        discovered = TypeSafeSettings.cachedCatalog(for: endpoint)?.models ?? []
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await refreshCatalog(force: false)
        }
    }

    private func refreshCatalog(force: Bool) async {
        let key = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if !force,
           let snapshot = TypeSafeSettings.cachedCatalog(for: endpoint),
           !ModelCatalogCachePolicy.isExpired(fetchedAt: snapshot.fetchedAt, now: Date()) {
            discovered = snapshot.models
            catalogFailed = false
            return
        }
        let client = TypeSafeClient(baseURL: endpoint.baseURL, apiKey: key)
        do {
            let models = try await client.listModels()
            TypeSafeSettings.storeCatalog(models, endpoint: endpoint)
            discovered = models
            catalogFailed = false
        } catch is CancellationError {
            return
        } catch {
            catalogFailed = true
        }
    }

    private func testKey() async {
        let key = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isTesting = true
        defer { isTesting = false }
        let client = TypeSafeClient(baseURL: endpoint.baseURL, apiKey: key)
        do {
            let models = try await client.listModels()
            TypeSafeSettings.storeCatalog(models, endpoint: endpoint)
            discovered = models
            catalogFailed = false
            testMessage = "Key works"
        } catch TypeSafeError.keyRejected {
            testMessage = "Key rejected"
        } catch {
            testMessage = "Couldn't reach TypeSafe"
        }
    }
}

/// Multi-word settings sit above the switch at accessibility sizes so the words can wrap.
struct AccessibleSettingToggle: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var systemImage: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                label
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
            }
        } else {
            Toggle(isOn: $isOn) {
                label
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TypeSafeEstimateCheckFooter: View {
    var body: some View {
        Text(.init("Get a key at [console.typesafe.ai](https://console.typesafe.ai/keys) (early access). About $0.00002 per check."))
            .font(.footnote)
    }
}

private struct TypeSafeModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var model: String
    var presets: [String]
    var discovered: [CatalogModel]
    var catalogFailed: Bool
    @State private var customID = ""

    var body: some View {
        NavigationStack {
            List {
                let sections = ModelCatalogLogic.sections(
                    presets: presets,
                    discovered: discovered,
                    visionOnly: false
                )
                Section("Recommended") {
                    ForEach(sections.recommended) { item in
                        modelRow(item.id)
                    }
                }
                if !sections.discovered.isEmpty {
                    Section("All models from TypeSafe") {
                        ForEach(sections.discovered) { item in
                            modelRow(item.id)
                        }
                    }
                }
                if catalogFailed {
                    Section {
                        Text(ModelCatalogCopy.couldNotRefresh)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Custom model ID") {
                    TextField("Model ID", text: $customID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { select(customID) }
                    Button("Use this model") { select(customID) }
                        .disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            customID = presets.contains(model) ? "" : model
        }
    }

    private func modelRow(_ id: String) -> some View {
        Button {
            select(id)
        } label: {
            HStack {
                Text(AIProvider.friendlyModelName(id))
                    .foregroundStyle(.primary)
                Spacer()
                if model == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.calorie)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func select(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model = trimmed
        TypeSafeSettings.model = trimmed
        dismiss()
    }
}
