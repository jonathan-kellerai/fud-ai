import SwiftUI
import UIKit

/// The on-device log of meal identification requests, newest first.
struct AIRequestLogListView: View {
    let store: AIRequestLogStore
    @State private var confirmingClear = false

    var body: some View {
        List {
            if store.entries.isEmpty {
                Section {
                    Text("No requests yet. Meal photos, typed foods and the AI Providers tests appear here.")
                        .font(.subheadline)
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(AppColors.appCard)
            } else {
                Section {
                    ForEach(store.newestFirst) { entry in
                        NavigationLink {
                            AIRequestLogDetailView(entry: entry)
                        } label: {
                            AIRequestLogRow(entry: entry)
                        }
                    }
                } footer: {
                    Text("Kept on this iPhone only, never uploaded. Keys and tokens are removed before saving. The newest \(AIRequestLogStore.maxEntries) requests are kept.")
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    Button {
                        confirmingClear = true
                    } label: {
                        Text("Clear log")
                            .foregroundStyle(IronTheme.bloodText)
                    }
                    .accessibilityIdentifier("settings.requestLog.clear")
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("Request log")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear the request log?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear log", role: .destructive) {
                store.clear()
            }
        } message: {
            Text("This deletes every entry on this iPhone.")
        }
    }
}

struct AIRequestLogRow: View {
    let entry: AIRequestLogEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IronTheme.textPrimary)
                Text("\(entry.provider) · \(entry.model ?? "no model")")
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(IronTheme.textSecondary)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                IronStatusPill(text: entry.statusLabel, tone: entry.severity.pillTone)
                Text("\(entry.latencyMs) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(IronTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every field of one request, the redacted error body, and Copy / Share.
struct AIRequestLogDetailView: View {
    let entry: AIRequestLogEntry
    @State private var copied = false

    var body: some View {
        List {
            Section {
                field("Status", entry.statusLabel)
                field("Kind", entry.kind.title)
                field("Provider", entry.provider)
                field("Model", entry.model ?? "Unknown")
                field("HTTP status", entry.httpStatus.map { String($0) } ?? "None")
                field("Latency", "\(entry.latencyMs) ms")
                field("Parsed", entry.parsed ? "Yes" : "No")
                field("Time", entry.timestamp.formatted(date: .abbreviated, time: .standard))
            }
            .listRowBackground(AppColors.appCard)

            if let errorBody = entry.errorBody, !errorBody.isEmpty {
                Section {
                    Text(errorBody)
                        .font(.footnote.monospaced())
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.requestLog.errorBody")
                } header: {
                    IronSectionTitle(title: "Error")
                }
                .listRowBackground(AppColors.appCard)
            }

            Section {
                Button {
                    UIPasteboard.general.string = entry.reportText()
                    copied = true
                } label: {
                    Label {
                        Text(copied ? "Copied" : "Copy")
                            .foregroundStyle(IronTheme.textPrimary)
                    } icon: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .accessibilityIdentifier("settings.requestLog.copy")

                ShareLink(item: entry.reportText()) {
                    Label {
                        Text("Share")
                            .foregroundStyle(IronTheme.textPrimary)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .accessibilityIdentifier("settings.requestLog.share")
            } footer: {
                Text("Copy and Share include no keys or tokens.")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ value: String) -> some View {
        AdaptiveLabelValue {
            Text(title)
                .foregroundStyle(IronTheme.textPrimary)
        } value: {
            Text(value)
                .foregroundStyle(IronTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension AIRequestLogEntry.Severity {
    var pillTone: IronStatusPill.Tone {
        switch self {
        case .ok: .olive
        case .warning: .rust
        case .error: .blood
        }
    }
}
