//
//  PeptideHistoryView.swift
//  calorietracker
//
//  Peptides › Week › History: every draw in the shown week, newest day first,
//  each opening its entry detail. Voided entries say "Voided" (no
//  strikethrough) and show only when asked. Export lives here.
//

import SwiftUI

struct PeptideHistoryView: View {
    @Environment(PeptideLogStore.self) private var store
    /// yyyy-MM-dd, inclusive.
    let from: String
    let to: String
    @State private var showVoided = false
    @State private var exportError: String?

    var body: some View {
        let days = PeptideMath.historyDays(entries: store.entries, from: from, to: to, includeVoided: showVoided)
        let voidedCount = store.entries.filter { entry in
            entry.voided && (entry.civilDate.map { $0 >= from && $0 <= to } ?? false)
        }.count
        VStack(alignment: .leading, spacing: 12) {
            PeptideHeader(text: "History")
            if days.isEmpty {
                Text("Nothing logged this week.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            ForEach(days) { day in
                dayCard(day)
            }
            if voidedCount > 0 {
                Toggle(showVoided ? "Showing voided (\(voidedCount))" : "Show voided (\(voidedCount))", isOn: $showVoided)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
                    .tint(IronTheme.olive)
            }
            exportButton
        }
    }

    private func dayCard(_ day: PeptideMath.HistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReconMath.formatDateShort(day.day))
                .font(.system(.title3, design: .default, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(day.entries) { entry in
                NavigationLink {
                    PeptideEntryDetailView(entryID: entry.id)
                } label: {
                    row(entry)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .peptideAccentCard(IronTheme.brass)
    }

    /// "BPC-157   50 units · 7:30 AM". Never mg.
    private func row(_ entry: PeptideLogEntry) -> some View {
        let time = entry.date.map { PeptideMath.timeText($0).replacingOccurrences(of: " ET", with: "") } ?? ""
        let value = [entry.drawText ?? "draw not recorded", time].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            AdaptiveLabelValue {
                Text(entry.compound)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
            } value: {
                Text(entry.voided ? value + " · Voided" : value)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(entry.voided ? IronTheme.textSecondary : IronTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(IronTheme.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the draw")
    }

    private var exportButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                export()
            } label: {
                Label("Export all peptides", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PeptideSecondaryButtonStyle())
            .accessibilityHint("Saves your draws, vials and schedules as a file you can keep or import later.")
            if let exportError {
                PeptideIssueText(text: exportError)
            }
        }
    }

    /// Writes every record to a peptides file and opens the share sheet.
    private func export() {
        let now = Date()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(PeptideArchive.fileName(exportedOn: now))
        do {
            try store.archive(exportedAt: now).encoded().write(to: url, options: .atomic)
            exportError = nil
            FileShareSheet.present(url)
        } catch {
            exportError = "The peptides file couldn't be written. " + error.localizedDescription
        }
    }
}
