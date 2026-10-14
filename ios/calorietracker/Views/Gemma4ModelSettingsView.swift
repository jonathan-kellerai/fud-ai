import SwiftUI

struct Gemma4ModelSettingsView: View {
    let onAvailabilityChange: () -> Void
    /// Visual QA only: draw a fixed install state (e.g. mid-download) instead of
    /// the shared manager's live state. Nil in the app; the manager is untouched.
    private let previewState: Gemma4LocalModelManager.InstallState?

    @State private var modelManager = Gemma4LocalModelManager.shared
    @State private var showDeleteConfirmation = false

    init(
        previewState: Gemma4LocalModelManager.InstallState? = nil,
        onAvailabilityChange: @escaping () -> Void
    ) {
        self.previewState = previewState
        self.onAvailabilityChange = onAvailabilityChange
    }

    private var state: Gemma4LocalModelManager.InstallState {
        previewState ?? modelManager.state
    }

    private var isEligible: Bool {
        previewState != nil || modelManager.isEligible
    }

    private var downloadProgress: Double? {
        guard case .downloading(let progress) = state else { return nil }
        return progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveLabelValue {
                Label {
                    UnbrokenText(localized("gemma.name", "Gemma 4 E2B"))
                } icon: {
                    Image(systemName: "cpu")
                }
                .font(.body.weight(.medium))
            } value: {
                UnbrokenText(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text(statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let progress = downloadProgress {
                ProgressView(value: progress)
                    .tint(AppColors.calorie)
                    .accessibilityLabel(localized("gemma.downloadProgress", "Gemma 4 download progress"))
                    .accessibilityValue(Text(progress, format: .percent))
            } else if state == .verifying {
                ProgressView()
                    .tint(AppColors.calorie)
                    .accessibilityLabel(localized("gemma.verifyingDownload", "Verifying Gemma 4 download"))
            }

            HStack {
                if isDownloading {
                    Button(localized("common.cancel", "Cancel"), role: .cancel) {
                        modelManager.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(downloadButtonTitle) {
                        Task {
                            if modelManager.isDownloaded {
                                await modelManager.prepare()
                            } else {
                                await modelManager.download()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.calorie)
                    .disabled(
                        !isEligible
                            || state.isBusy
                            || state == .ready
                    )
                }

                if modelManager.hasStoredData {
                    Button(localized("common.delete", "Delete"), role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isBusy)
                }
            }

            HStack(spacing: 12) {
                Link("Apache 2.0", destination: Gemma4LocalModelManager.licenseURL)
                    .font(.caption2)

                Link(destination: Gemma4LocalModelManager.sourceURL) {
                    Label(localized("gemma.modelSource", "Model source"), systemImage: "arrow.up.right.square")
                        .font(.caption2)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { modelManager.refresh() }
        .onChange(of: modelManager.isSelectable) { _, _ in
            onAvailabilityChange()
        }
        .confirmationDialog(
            localized("gemma.deleteTitle", "Delete Gemma 4?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("common.deleteModel", "Delete Model"), role: .destructive) {
                deleteModel()
            }
            Button(localized("common.cancel", "Cancel"), role: .cancel) { }
        } message: {
            Text(localized(
                "gemma.deleteMessage",
                "The downloaded model and its compiled cache will be removed from this iPhone. You can download it again later."
            ))
        }
    }

    private var statusLabel: String {
        guard isEligible else {
            return localized("gemma.requires8GB", "Requires an 8 GB RAM device")
        }
        switch state {
        case .notDownloaded:
            return localized("common.notDownloaded", "Not downloaded")
        case .downloaded:
            return localized("common.downloaded", "Downloaded")
        case .downloading(let progress):
            return "\(Int(progress * 100))%"
        case .verifying:
            return localized("common.verifying", "Verifying")
        case .preparing:
            return localized("common.preparing", "Preparing")
        case .ready:
            return localized("common.ready", "Ready")
        case .generating:
            return localized("common.inUse", "In use")
        case .failed:
            return localized("common.needsAttention", "Needs attention")
        }
    }

    private var statusColor: Color {
        guard isEligible else { return .secondary }
        switch state {
        case .downloaded, .ready:
            return .green
        case .failed:
            return .red
        case .notDownloaded, .downloading, .verifying, .preparing, .generating:
            return .secondary
        }
    }

    private var statusDescription: String {
        guard isEligible else {
            return localized(
                "gemma.unsupportedDescription",
                "This on-device image and text model is available on iPhones with at least 8 GB of physical memory."
            )
        }

        switch state {
        case .notDownloaded:
            // New key: the LocalModels catalog still carries the old "Fud AI"
            // English value under "gemma.downloadDescription".
            return localized(
                "gemma.downloadDescription.jlPhysical",
                "2.59 GB download. JL Physical checks for an additional 1 GB of free installation headroom."
            )
        case .downloaded:
            if let size = modelManager.installedSizeDescription {
                return LocalModelStrings.format(
                    "gemma.storedWithSize",
                    defaultValue: "Verified and stored locally (%@). Tap Prepare now, or it will load on first use.",
                    size
                )
            }
            return localized(
                "gemma.stored",
                "Verified and stored locally. Tap Prepare now, or it will load on first use."
            )
        case .downloading:
            return localized(
                "gemma.downloading.jlPhysical",
                "Downloading the pinned Gemma 4 model… Keep JL Physical open until it finishes."
            )
        case .verifying:
            return localized(
                "gemma.checking",
                "Checking the exact file size and SHA-256 before installation…"
            )
        case .preparing:
            return localized(
                "gemma.compiling",
                "Compiling and loading the LiteRT-LM Metal runtime…"
            )
        case .ready:
            return localized(
                "gemma.readyDescription",
                "Ready for private, offline food images and text."
            )
        case .generating:
            return localized("gemma.generating", "Generating locally on this iPhone…")
        case .failed(let message):
            return message
        }
    }

    private var downloadButtonTitle: String {
        switch state {
        case .ready:
            return localized("common.ready", "Ready")
        default:
            return modelManager.isDownloaded
                ? localized("common.prepare", "Prepare")
                : localized("common.download", "Download")
        }
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private func deleteModel() {
        do {
            try modelManager.delete()
            AIProviderSettings.replaceDeletedLocalGemmaSelections()
            onAvailabilityChange()
        } catch {
            modelManager.refresh()
        }
    }

    private func localized(_ key: String, _ defaultValue: String) -> String {
        LocalModelStrings.text(key, defaultValue: defaultValue)
    }
}
