//
//  PeptideScheduleView.swift
//  calorietracker
//
//  Schedules the user typed (device only) and adherence against them. The app
//  never generates or proposes a schedule, dose or protocol.
//

import SwiftUI

struct PeptideScheduleEditorTarget: Identifiable {
    let id = UUID().uuidString
    var schedule: PeptideUserSchedule?
    var person: String
}

struct PeptideScheduleView: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var person: String
    @State private var editorTarget: PeptideScheduleEditorTarget?

    /// Fixed "now" for adherence (Visual QA). Nil uses the live date,
    /// refreshed on foreground and when the day changes.
    private let referenceDate: Date?
    @State private var now: Date

    init(person: String = PeptidePerson.jonathan, referenceDate: Date? = nil) {
        _person = State(initialValue: PeptidePerson.normalized(person))
        _now = State(initialValue: referenceDate ?? Date())
        self.referenceDate = referenceDate
    }

    private var today: String { PeptideMath.civilDate(referenceDate ?? now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PeptideScreenTitle(title: "Schedule", subtitle: "You enter these. The app doesn't suggest doses or protocols.")
                PeptidePersonToggle(person: $person)
                Button {
                    editorTarget = PeptideScheduleEditorTarget(schedule: nil, person: person)
                } label: {
                    Label("Add schedule", systemImage: "plus")
                }
                .buttonStyle(IronPrimaryButtonStyle())
                schedulesSection
                PeptideFooter()
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Schedule & adherence")
        .navigationBarTitleDisplayMode(.inline)
        .peptideLiveDate($now, fixed: referenceDate != nil)
        .sheet(item: $editorTarget) { target in
            PeptideScheduleEditor(schedule: target.schedule, person: target.person)
        }
    }

    @ViewBuilder
    private var schedulesSection: some View {
        let schedules = store.personSchedules(person: person)
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "Your schedules")
            if schedules.isEmpty {
                Text("No schedules for \(PeptidePerson.name(person)). Add one to see what's due and track adherence.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(schedules) { schedule in
                PeptideScheduleCard(schedule: schedule, today: today) {
                    editorTarget = PeptideScheduleEditorTarget(schedule: schedule, person: person)
                }
            }
        }
    }
}

struct PeptideScheduleCard: View {
    @Environment(PeptideLogStore.self) private var store
    let schedule: PeptideUserSchedule
    let today: String
    var onEdit: () -> Void

    var body: some View {
        let week = PeptideMath.adherence(schedule, entries: store.entries, from: ReconMath.addDays(today, -6), to: today, today: today)
        let month = PeptideMath.adherence(schedule, entries: store.entries, from: ReconMath.addDays(today, -29), to: today, today: today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(schedule.compound)
                    .font(.system(size: 22, weight: .black))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(schedule.active ? IronTheme.textPrimary : IronTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !schedule.active {
                    PeptideTag(text: "Paused", tone: IronTheme.concrete, filled: true)
                }
            }
            Text(PeptideMath.scheduleText(schedule))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(rangeText)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if schedule.active {
                adherenceRow(week: week, month: month)
                missedList(month)
            }
            Toggle("Active", isOn: activeBinding)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textSecondary)
                .tint(IronTheme.olive)
            Button("Edit", action: onEdit)
                .buttonStyle(IronCompactButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { schedule.active },
            set: { store.setScheduleActive(id: schedule.id, active: $0) }
        )
    }

    private var rangeText: String {
        var text = "From " + ReconMath.formatDate(schedule.startDate)
        if let end = schedule.endDate { text += " to " + ReconMath.formatDate(end) }
        return text
    }

    private func adherenceRow(week: PeptideMath.Adherence, month: PeptideMath.Adherence) -> some View {
        PeptideFlowLayout(spacing: 12) {
            stat("7 days", value: week.percentText, detail: "\(week.taken) of \(week.due)")
            stat("30 days", value: month.percentText, detail: "\(month.taken) of \(month.due)")
            stat("Streak", value: "\(month.streak)", detail: schedule.frequency.type == "perWeek" ? "weeks" : "in a row")
        }
    }

    private func stat(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PeptideFieldLabel(title)
            Text(value)
                .font(.system(size: 24, weight: .black).monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
        }
        .padding(8)
        .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
    }

    @ViewBuilder
    private func missedList(_ month: PeptideMath.Adherence) -> some View {
        if !month.missedDates.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                PeptideFieldLabel(schedule.frequency.type == "perWeek" ? "Short weeks (last 30 days)" : "Missed (last 30 days)")
                Text(month.missedDates.suffix(10).reversed().map { prefixWeek($0) }.joined(separator: ", "))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if month.todayDue && !month.todayTaken {
            Text("Due today, not logged yet.")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.brass)
        }
    }

    private func prefixWeek(_ date: String) -> String {
        schedule.frequency.type == "perWeek" ? "week of " + ReconMath.formatDateShort(date) : ReconMath.formatDateShort(date)
    }
}

// MARK: - Editor

struct PeptideScheduleEditor: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let existing: PeptideUserSchedule?
    @State private var person: String
    @State private var compound: String
    @State private var amountText: String
    @State private var units: String?
    /// Nil until the user picks one. A new schedule never preselects a frequency.
    @State private var frequencyType: String?
    @State private var weekdays: Set<Int>
    @State private var nText: String
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var active: Bool
    @State private var notes: String
    @State private var errorText: String?
    @State private var confirmDelete = false

    private static let frequencyOptions: [(type: String, title: String)] = [
        ("daily", "Daily"),
        ("weekdays", "Days of week"),
        ("everyN", "Every N days"),
        ("perWeek", "N× per week"),
        ("weekly", "Weekly"),
    ]

    init(schedule: PeptideUserSchedule?, person: String) {
        existing = schedule
        _person = State(initialValue: PeptidePerson.normalized(schedule?.person ?? person))
        _compound = State(initialValue: schedule?.compound ?? "")
        _amountText = State(initialValue: schedule?.amount.map(PeptideMath.number) ?? "")
        _units = State(initialValue: schedule?.units)
        _frequencyType = State(initialValue: schedule?.frequency.type)
        _weekdays = State(initialValue: Set(schedule?.frequency.days ?? []))
        _nText = State(initialValue: schedule?.frequency.n.map(PeptideMath.number) ?? "")
        _startDate = State(initialValue: schedule.map { PeptideViewDates.localDate(fromCivil: $0.startDate) } ?? Date())
        _hasEnd = State(initialValue: schedule?.endDate != nil)
        _endDate = State(initialValue: schedule?.endDate.map(PeptideViewDates.localDate(fromCivil:)) ?? Date())
        _hasTime = State(initialValue: schedule?.timeOfDay != nil)
        _time = State(initialValue: schedule?.timeOfDay.map(PeptideViewDates.localDate(minutes:)) ?? Date())
        _active = State(initialValue: schedule?.active ?? true)
        _notes = State(initialValue: schedule?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("You enter this schedule. The app doesn't suggest doses or protocols.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.brass)
                        .fixedSize(horizontal: false, vertical: true)
                    PeptidePersonToggle(person: $person)
                    compoundSection
                    amountSection
                    frequencySection
                    datesSection
                    Toggle("Active", isOn: $active)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(IronTheme.textPrimary)
                        .tint(IronTheme.olive)
                    VStack(alignment: .leading, spacing: 4) {
                        PeptideFieldLabel("Notes (optional)")
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                            .padding(10)
                            .background(IronTheme.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                    }
                    if let errorText {
                        PeptideIssueText(text: errorText)
                    }
                    if frequencyType == nil {
                        Text("Pick how often before saving.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Save schedule") { save() }
                        .buttonStyle(IronPrimaryButtonStyle())
                        .disabled(frequencyType == nil)
                    if existing != nil {
                        Button("Delete schedule", role: .destructive) { confirmDelete = true }
                            .font(.system(size: 15, weight: .heavy))
                            .fontWidth(.condensed)
                            .textCase(.uppercase)
                            .foregroundStyle(IronTheme.bloodText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    PeptideFooter()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(IronTheme.canvas)
            .navigationTitle(existing == nil ? "Add schedule" : "Edit schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Delete this schedule?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete schedule", role: .destructive) {
                    if let existing { store.deleteSchedule(id: existing.id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var compoundSection: some View {
        let options = PeptideMath.compoundOptions(person: person, loggedCompounds: store.loggedCompounds(person: person))
        return VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("Compound")
            PeptideFlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    PeptideChoiceChip(title: option, selected: compound == option) { compound = option }
                }
            }
            PeptideInputField(title: "Compound name", text: $compound, prompt: "Or type a compound")
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideInputField(title: "Your amount note (optional)", text: $amountText, prompt: "Leave blank if you like", keyboard: .decimalPad, monospaced: true)
            PeptideFlowLayout(spacing: 8) {
                PeptideChoiceChip(title: "No units", selected: units == nil) { units = nil }
                ForEach(PeptideMath.unitOptions, id: \.self) { unit in
                    PeptideChoiceChip(title: unit, selected: units == unit) { units = unit }
                }
            }
            Text("Shown next to the schedule only. It is never put into a log for you.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PeptideFieldLabel("How often")
            PeptideFlowLayout(spacing: 8) {
                ForEach(Self.frequencyOptions, id: \.type) { option in
                    PeptideChoiceChip(title: option.title, selected: frequencyType == option.type) {
                        frequencyType = option.type
                    }
                }
            }
            if frequencyType == "weekdays" {
                weekdayPicker
            }
            if frequencyType == "everyN" {
                PeptideInputField(title: "Every how many days", text: $nText, prompt: "Days", keyboard: .numberPad, monospaced: true)
            }
            if frequencyType == "perWeek" {
                PeptideInputField(title: "Times per week", text: $nText, prompt: "Times", keyboard: .numberPad, monospaced: true)
            }
        }
    }

    private var weekdayPicker: some View {
        PeptideFlowLayout(spacing: 6) {
            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                PeptideChoiceChip(title: ReconMath.weekdayShort[day], selected: weekdays.contains(day)) {
                    if weekdays.contains(day) {
                        weekdays.remove(day)
                    } else {
                        weekdays.insert(day)
                    }
                }
            }
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                PeptideFieldLabel("Start")
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                Text("Starts " + ReconMath.formatDate(PeptideViewDates.civil(fromLocal: startDate)))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Has an end date", isOn: $hasEnd)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .tint(IronTheme.blood)
            if hasEnd {
                DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .labelsHidden()
            }
            Toggle("Time of day", isOn: $hasTime)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .tint(IronTheme.blood)
            if hasTime {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }

    private func save() {
        let name = compound.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorText = "Pick or type the compound."
            return
        }
        var amount: Double?
        let amountRaw = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !amountRaw.isEmpty {
            let value = ReconMath.toNumber(amountRaw)
            guard value.isFinite, value > 0 else {
                errorText = "Amount must be a number more than 0, or blank."
                return
            }
            amount = value
        }
        guard let frequencyType else {
            errorText = "Pick how often."
            return
        }
        var frequency = ReconMath.Frequency(type: frequencyType)
        switch frequencyType {
        case "weekdays":
            guard !weekdays.isEmpty else {
                errorText = "Pick at least one day."
                return
            }
            frequency.days = weekdays.sorted()
        case "everyN", "perWeek":
            let value = ReconMath.toNumber(nText)
            let limit: Double = frequencyType == "perWeek" ? 7 : 365
            guard value.isFinite, value >= 1, value == value.rounded(), value <= limit else {
                errorText = frequencyType == "perWeek" ? "Times per week must be a whole number from 1 to 7." : "Days must be a whole number from 1 to 365."
                return
            }
            frequency.n = value
        default:
            break
        }
        let start = PeptideViewDates.civil(fromLocal: startDate)
        let end = hasEnd ? PeptideViewDates.civil(fromLocal: endDate) : nil
        if let end, end < start {
            errorText = "End date is before the start date."
            return
        }
        let schedule = PeptideUserSchedule(
            id: existing?.id ?? UUID().uuidString,
            person: person,
            compound: name,
            amount: amount,
            units: amount == nil ? nil : units,
            frequency: frequency,
            startDate: start,
            endDate: end,
            timeOfDay: hasTime ? PeptideViewDates.minutes(fromLocal: time) : nil,
            active: active,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existing?.createdAt ?? Date()
        )
        store.saveSchedule(schedule)
        dismiss()
    }
}
