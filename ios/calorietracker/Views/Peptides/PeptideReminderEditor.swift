//
//  PeptideReminderEditor.swift
//  calorietracker
//
//  A one-off reminder: what it's for, the day (any day) and the time window.
//  Shown in its slot on that day above the doses, with a local notification
//  at its start time when notifications are allowed. Dismissing keeps it.
//

import SwiftUI

struct PeptideReminderEditor: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let existing: PeptideReminder?
    @State private var title: String
    @State private var date: Date
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var showsOnToday: Bool
    @State private var errorText: String?
    @State private var confirmDelete = false

    init(reminder: PeptideReminder?) {
        existing = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _date = State(initialValue: reminder.map { PeptideViewDates.localDate(fromCivil: $0.date) } ?? Date())
        _start = State(initialValue: PeptideViewDates.localDate(minutes: reminder?.startMinutes ?? 8 * 60))
        _hasEnd = State(initialValue: reminder?.endMinutes != nil)
        _end = State(initialValue: PeptideViewDates.localDate(minutes: reminder?.endMinutes ?? 10 * 60))
        _showsOnToday = State(initialValue: !(reminder?.dismissed ?? false))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeptideInputField(title: "Reminder", text: $title, prompt: "What it's for")
                    VStack(alignment: .leading, spacing: 4) {
                        PeptideFieldLabel("Day")
                        DatePicker("Day", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                        Text(ReconMath.formatDate(PeptideViewDates.civil(fromLocal: date)))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        PeptideFieldLabel("From")
                        DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Toggle("Has an end time", isOn: $hasEnd)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                        .tint(IronTheme.blood)
                    if hasEnd {
                        DatePicker("To", selection: $end, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Toggle("Show on Today", isOn: $showsOnToday)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                        .tint(IronTheme.olive)
                    Text("A notification comes at the start time on this phone, if notifications are allowed. Nothing leaves the phone.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                    Button("Save reminder") { save() }
                        .buttonStyle(IronPrimaryButtonStyle())
                    if existing != nil {
                        Button("Delete reminder", role: .destructive) { confirmDelete = true }
                            .buttonStyle(PeptideSecondaryButtonStyle())
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle(existing == nil ? "Add reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete reminder", role: .destructive) {
                    if let existing, let refusal = store.deleteReminder(id: existing.id) {
                        errorText = refusal
                        return
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        let reminder = PeptideReminder(
            id: existing?.id ?? UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: PeptideViewDates.civil(fromLocal: date),
            startMinutes: PeptideViewDates.minutes(fromLocal: start),
            endMinutes: hasEnd ? PeptideViewDates.minutes(fromLocal: end) : nil,
            dismissed: !showsOnToday,
            origin: existing?.origin,
            createdAt: existing?.createdAt ?? Date()
        )
        if let refusal = store.saveReminder(reminder) {
            errorText = refusal
            return
        }
        dismiss()
    }
}
