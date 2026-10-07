//
//  PeptideImportView.swift
//  calorietracker
//
//  Import a peptides file (the same format Export writes). The preview says
//  what would be added before anything changes. Everything goes into this
//  phone's log. Records only: nothing is calculated or suggested from the file.
//

import SwiftUI

/// A file that passed validation, waiting for the user to confirm.
struct PeptideImportRequest: Identifiable {
    let id = UUID().uuidString
    var archive: PeptideArchive
}

struct PeptideImportPreviewSheet: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let archive: PeptideArchive
    @State private var imported: PeptideImportSummary?

    init(archive: PeptideArchive) {
        self.archive = archive
    }

    var body: some View {
        let summary = store.importSummary(of: archive)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeptideScreenTitle(title: "Import", subtitle: "Check what this file adds before anything changes.")
                    if let imported {
                        PeptideBanner(
                            title: "Imported",
                            message: Self.addedText(imported) + ". Nothing already on this phone was changed.",
                            tone: IronTheme.olive
                        )
                    } else {
                        countsCard(summary)
                        Button(summary.added == 0 ? "Nothing new to import" : "Import " + Self.addedText(summary)) {
                            imported = store.importArchive(archive)
                        }
                        .buttonStyle(IronPrimaryButtonStyle(enabled: summary.added > 0))
                        .disabled(summary.added == 0)
                        Text("Only records that aren't on this phone yet are added. Nothing is changed or removed.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .background(IronTheme.canvas)
            .navigationTitle("Import peptides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(imported == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private func countsCard(_ summary: PeptideImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideDetailRow(label: "New vials", value: "\(summary.newVials)")
            PeptideDetailRow(label: "New schedules", value: "\(summary.newSchedules)")
            PeptideDetailRow(label: "New doses", value: "\(summary.newEntries)")
            if summary.alreadyHere > 0 {
                PeptideDetailRow(label: "Already on this phone", value: "\(summary.alreadyHere)")
            }
            if summary.skipped > 0 {
                PeptideDetailRow(label: "Couldn't be read", value: "\(summary.skipped)", valueColor: IronTheme.rust)
            }
            if let exported = archive.exportedAt.flatMap(PeptideMath.parseISO8601) {
                PeptideDetailRow(label: "File made", value: PeptideMath.shortDateTime(exported) + " ET")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private static func addedText(_ summary: PeptideImportSummary) -> String {
        var parts: [String] = []
        if summary.newVials > 0 { parts.append(summary.newVials == 1 ? "1 vial" : "\(summary.newVials) vials") }
        if summary.newSchedules > 0 { parts.append(summary.newSchedules == 1 ? "1 schedule" : "\(summary.newSchedules) schedules") }
        if summary.newEntries > 0 { parts.append(summary.newEntries == 1 ? "1 dose" : "\(summary.newEntries) doses") }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }
}
