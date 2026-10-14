//
//  PeptidePresetSheet.swift
//  calorietracker
//
//  "Load my schedule": lists exactly what will be saved (the user's own or
//  prescribed doses, their vial mixes and the lab reminder) before anything
//  changes. Loading again replaces what an earlier load saved; schedules the
//  user added stay. Not advice: the app suggests no dose.
//

import SwiftUI

struct PeptidePresetSheet: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// yyyy-MM-dd: schedules start and vials are mixed on it.
    let today: String
    /// Fixed "now" (Visual QA). Nil uses the live time.
    var now: Date?
    private let preset = PeptideOwnSchedulePreset.own
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("These are your own or prescribed doses, saved as records. The app doesn't suggest or change doses.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.brass)
                        .fixedSize(horizontal: false, vertical: true)
                    section("Schedules and reminder", lines: preset.summaryLines())
                    section("Vials, mixed " + ReconMath.formatDate(today), lines: preset.vialLines())
                    Text("Loading again replaces only what an earlier load saved. Schedules, vials and reminders you added yourself stay as they are. Nothing is logged until you tap Taken.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                    Button("Save these records") {
                        if let refusal = store.loadPreset(preset, today: today, now: now ?? Date()) {
                            errorText = refusal
                            return
                        }
                        dismiss()
                    }
                    .buttonStyle(IronPrimaryButtonStyle())
                    .accessibilityIdentifier("peptides.preset.save")
                    PeptideFooter()
                }
                .padding(16)
            }
            .background(IronTheme.canvas)
            .navigationTitle("Load my schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel(title)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }
}
