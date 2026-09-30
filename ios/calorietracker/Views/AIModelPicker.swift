import SwiftUI

/// Presets first, then every model the provider listed, plus a custom id for hosted providers.
struct AIModelPickerRow: View {
    let provider: AIProvider
    let presets: [String]
    @Binding var model: String
    let baseURL: String
    let apiKey: String
    var visionOnly: Bool
    var excludedModelIDs: Set<String> = []

    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            AdaptiveLabelValue {
                Label {
                    Text("Model")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } icon: {
                    Image(systemName: "brain")
                        .foregroundStyle(AppColors.calorie)
                }
            } value: {
                HStack(spacing: 6) {
                    Text(model.isEmpty ? "Choose a model" : AIProvider.friendlyModelName(model))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            AIModelPickerSheet(
                provider: provider,
                presets: presets,
                model: $model,
                baseURL: baseURL,
                apiKey: apiKey,
                visionOnly: visionOnly,
                excludedModelIDs: excludedModelIDs
            )
        }
    }
}

private struct AIModelPickerSheet: View {
    let provider: AIProvider
    let presets: [String]
    @Binding var model: String
    let baseURL: String
    let apiKey: String
    var visionOnly: Bool
    var excludedModelIDs: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var customModelID = ""
    @State private var catalog = ModelCatalogService.shared

    var body: some View {
        NavigationStack {
            List {
                if catalog.couldNotRefresh(provider: provider, baseURL: resolvedBaseURL) {
                    Section {
                        Text(ModelCatalogCopy.couldNotRefresh)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !filteredRecommended.isEmpty {
                    Section("Recommended") {
                        modelRows(filteredRecommended)
                    }
                }

                if !filteredDiscovered.isEmpty {
                    Section("All models from \(provider.displayName)") {
                        modelRows(filteredDiscovered)
                    }
                }

                if provider.acceptsCustomModelID {
                    Section("Custom model ID") {
                        TextField("Model ID", text: $customModelID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { useCustomModel() }
                        Button("Use this model") { useCustomModel() }
                            .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .id(catalog.revision)
            .searchable(text: $query, prompt: "Search models")
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable {
                await catalog.refresh(
                    provider: provider,
                    baseURL: resolvedBaseURL,
                    apiKey: apiKey,
                    force: true
                )
            }
        }
        .onAppear {
            customModelID = model
            Task {
                await catalog.refresh(
                    provider: provider,
                    baseURL: resolvedBaseURL,
                    apiKey: apiKey,
                    force: false
                )
            }
        }
    }

    private var resolvedBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.baseURL : trimmed
    }

    private var sections: ModelPickerSections {
        catalog.sections(
            provider: provider,
            presets: presets,
            baseURL: resolvedBaseURL,
            visionOnly: visionOnly,
            excludedModelIDs: excludedModelIDs
        )
    }

    private var filteredRecommended: [CatalogModel] {
        sections.recommended.filter { ModelCatalogLogic.matches($0, query: query) }
    }

    private var filteredDiscovered: [CatalogModel] {
        sections.discovered.filter { ModelCatalogLogic.matches($0, query: query) }
    }

    @ViewBuilder
    private func modelRows(_ models: [CatalogModel]) -> some View {
        ForEach(models) { item in
            Button {
                model = item.id
                dismiss()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.id)
                            .foregroundStyle(.primary)
                        if visionOnly && item.vision == .unverified {
                            Text(ModelCatalogCopy.imageSupportUnverified)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if item.id == model {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func useCustomModel() {
        let trimmed = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model = trimmed
        dismiss()
    }
}
