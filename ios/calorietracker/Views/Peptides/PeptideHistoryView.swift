//
//  PeptideHistoryView.swift
//  calorietracker
//
//  Month calendar, per-compound summaries, a weekly count chart and every
//  logged dose by day.
//

import Charts
import SwiftUI

struct PeptideHistoryView: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var person: String
    @State private var compoundFilter: String?
    @State private var anchor: String
    @State private var selectedDay: String?
    @State private var showVoided = false
    @State private var exportError: String?

    /// Fixed "now" for the calendar and windows (Visual QA). Nil uses the
    /// live date, refreshed on foreground and when the day changes.
    private let referenceDate: Date?
    @State private var now: Date

    init(person: String = PeptidePerson.jonathan, initialDay: String? = nil, referenceDate: Date? = nil) {
        let start = referenceDate ?? Date()
        _person = State(initialValue: PeptidePerson.normalized(person))
        let today = PeptideMath.civilDate(start)
        _anchor = State(initialValue: initialDay ?? today)
        _selectedDay = State(initialValue: initialDay)
        _now = State(initialValue: start)
        self.referenceDate = referenceDate
    }

    private var today: String { PeptideMath.civilDate(referenceDate ?? now) }

    private var personEntries: [PeptideLogEntry] {
        let owner = PeptidePerson.normalized(person)
        let key = compoundFilter.map(PeptideMath.compoundKey)
        return store.entries.filter {
            PeptidePerson.normalized($0.person) == owner
                && (key == nil || PeptideMath.compoundKey($0.compound) == key)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PeptideScreenTitle(title: "History", subtitle: "Every dose you logged, by day.")
                storageNotes
                exportButton
                PeptidePersonToggle(person: $person)
                filterChips
                PeptideMonthCalendar(
                    person: person,
                    compound: compoundFilter,
                    anchor: $anchor,
                    selectedDay: $selectedDay,
                    today: today
                )
                selectedDaySection
                summariesSection
                chartSection
                listSection
                PeptideFooter()
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Peptide history")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: person) { _, _ in
            compoundFilter = nil
        }
        .peptideLiveDate($now, fixed: referenceDate != nil)
    }

    private var exportButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                export()
            } label: {
                Label("Export all peptides", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PeptideSecondaryButtonStyle())
            .accessibilityHint("Saves both people's doses, vials and schedules as a file you can keep or import later.")
            if let exportError {
                PeptideIssueText(text: exportError)
            }
        }
    }

    /// Writes every record (both people) to a peptides file and opens the share sheet.
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

    /// Why the saved log isn't complete or isn't being saved, as plain text.
    @ViewBuilder
    private var storageNotes: some View {
        ForEach([store.storageNote, store.persistError].compactMap { $0 }, id: \.self) { note in
            Text(note)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.rust)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var compoundChoices: [String] {
        var seen = Set<String>()
        var names: [String] = []
        let candidates = store.loggedCompounds(person: person) + store.personSchedules(person: person).map(\.compound)
        for name in candidates {
            let key = PeptideMath.compoundKey(name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            names.append(name)
        }
        return names
    }

    private var filterChips: some View {
        PeptideFlowLayout(spacing: 8) {
            PeptideChoiceChip(title: "All", selected: compoundFilter == nil) { compoundFilter = nil }
            ForEach(compoundChoices, id: \.self) { name in
                PeptideChoiceChip(
                    title: name,
                    selected: compoundFilter.map { PeptideMath.sameCompound($0, name) } ?? false
                ) {
                    compoundFilter = name
                }
            }
        }
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        if let selectedDay {
            let rows = personEntries.filter { $0.civilDate == selectedDay && (showVoided || !$0.voided) }
            VStack(alignment: .leading, spacing: 8) {
                IronSectionTitle(title: ReconMath.formatDate(selectedDay))
                if rows.isEmpty {
                    Text("Nothing logged this day.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                }
                ForEach(rows.reversed()) { entry in
                    entryLink(entry)
                }
            }
        }
    }

    @ViewBuilder
    private var summariesSection: some View {
        let summaries = PeptideMath.compoundSummaries(entries: personEntries, person: person, today: today)
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                IronSectionTitle(title: "By compound")
                ForEach(summaries) { summary in
                    PeptideCompoundSummaryCard(summary: summary)
                }
            }
        }
    }

    private var chartSection: some View {
        let counts = PeptideMath.weeklyCounts(entries: store.entries, compound: compoundFilter, person: person, weeks: 12, today: today)
        return VStack(alignment: .leading, spacing: 8) {
            IronSectionTitle(title: "Doses per week")
            Chart(counts) { week in
                BarMark(
                    x: .value("Week", PeptideMath.date(civil: week.weekStart) ?? Date(), unit: .weekOfYear),
                    y: .value("Doses", week.count)
                )
                .foregroundStyle(IronTheme.blood)
            }
            .chartXAxis {
                ProgressV2DateAxis.marks(format: .dateTime.month(.abbreviated).day())
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(IronTheme.hairline)
                    AxisValueLabel()
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Doses per week, last 12 weeks")
            .accessibilityValue(counts.map { "\(ReconMath.formatDateShort($0.weekStart)): \($0.count)" }.joined(separator: ", "))
        }
        .padding(12)
        .ironCard()
    }

    @ViewBuilder
    private var listSection: some View {
        let rows = personEntries.filter { showVoided || !$0.voided }
        let days = groupedDays(rows)
        let voidedCount = personEntries.filter(\.voided).count
        VStack(alignment: .leading, spacing: 12) {
            IronSectionTitle(title: "All doses")
            if voidedCount > 0 {
                Toggle(showVoided ? "Showing voided (\(voidedCount))" : "Show voided (\(voidedCount))", isOn: $showVoided)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
                    .tint(IronTheme.blood)
            }
            if days.isEmpty {
                Text("No doses logged yet.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 6) {
                    PeptideFieldLabel(ReconMath.formatDate(group.day))
                    ForEach(group.entries) { entry in
                        entryLink(entry)
                    }
                }
            }
        }
    }

    private func groupedDays(_ rows: [PeptideLogEntry]) -> [(day: String, entries: [PeptideLogEntry])] {
        var order: [String] = []
        var grouped: [String: [PeptideLogEntry]] = [:]
        for entry in rows.reversed() {
            let day = entry.civilDate ?? "—"
            if grouped[day] == nil { order.append(day) }
            grouped[day, default: []].append(entry)
        }
        return order.map { (day: $0, entries: grouped[$0] ?? []) }
    }

    private func entryLink(_ entry: PeptideLogEntry) -> some View {
        NavigationLink {
            PeptideEntryDetailView(entryID: entry.id)
        } label: {
            PeptideLogRow(entry: entry, vialName: store.vial(id: entry.vialID)?.displayName)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ironCard()
        }
        .buttonStyle(.plain)
    }
}

struct PeptideCompoundSummaryCard: View {
    let summary: PeptideMath.CompoundWindowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.compound)
                .font(.system(size: 20, weight: .black))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PeptideFlowLayout(spacing: 10) {
                count("7 days", summary.count7)
                count("30 days", summary.count30)
                count("90 days", summary.count90)
            }
            if !summary.totals30.isEmpty {
                PeptideFieldLabel("Totals, last 30 days (same units only)")
                ForEach(summary.totals30) { total in
                    Text(total.text)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let last = summary.lastDose {
                Text("Last dose " + PeptideMath.shortDateTime(last) + " ET")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard()
    }

    private func count(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 24, weight: .black).monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
            PeptideFieldLabel(title)
        }
        .padding(8)
        .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
    }
}

/// Month grid from ReconMath.monthDays. Olive: every scheduled dose logged.
/// Rust: a scheduled dose was missed. Brass: logged with nothing scheduled.
struct PeptideMonthCalendar: View {
    @Environment(PeptideLogStore.self) private var store
    let person: String
    let compound: String?
    @Binding var anchor: String
    @Binding var selectedDay: String?
    let today: String

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let month = ReconMath.monthDays(anchor: anchor)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    anchor = ReconMath.shiftAnchor(anchor, view: "month", direction: -1)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(month.label)
                    .font(IronTheme.heavyHeadline)
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
                Spacer()
                Button {
                    anchor = ReconMath.shiftAnchor(anchor, view: "month", direction: 1)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(ReconMath.shiftAnchor(anchor, view: "month", direction: 1) > today)
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(IronTheme.bloodText)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                    Text(String(name.prefix(1)))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(IronTheme.textTertiary)
                        .accessibilityHidden(true)
                }
                ForEach(month.days, id: \.iso) { day in
                    dayCell(day.iso, inMonth: day.inMonth)
                }
            }
            legend
        }
        .padding(12)
        .ironCard()
        // Seven fixed columns can't grow with accessibility text; each day keeps a full VoiceOver label.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayCell(_ iso: String, inMonth: Bool) -> some View {
        let marker = PeptideMath.dayMarker(
            date: iso,
            person: person,
            compound: compound,
            schedules: store.schedules,
            entries: store.entries,
            today: today
        )
        let selected = selectedDay == iso
        let number = ReconMath.parseISO(iso)?.day ?? 0
        return Button {
            selectedDay = selected ? nil : iso
        } label: {
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.system(size: 14, weight: iso == today ? .black : .semibold).monospacedDigit())
                    .foregroundStyle(inMonth ? IronTheme.textPrimary : IronTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Circle()
                    .fill(markerColor(marker))
                    .frame(width: 6, height: 6)
                    .opacity(marker == .none ? 0 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(selected ? IronTheme.blood : (iso == today ? IronTheme.surfaceRaised : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(iso > today)
        .accessibilityLabel(ReconMath.formatDate(iso) + ", " + markerWord(marker))
    }

    private func markerColor(_ marker: PeptideMath.DayMarker) -> Color {
        switch marker {
        case .none: return Color.clear
        case .allTaken: return IronTheme.olive
        case .missed: return IronTheme.rust
        case .unscheduledOnly: return IronTheme.brass
        }
    }

    private func markerWord(_ marker: PeptideMath.DayMarker) -> String {
        switch marker {
        case .none: return "nothing logged"
        case .allTaken: return "all scheduled doses logged"
        case .missed: return "missed a scheduled dose"
        case .unscheduledOnly: return "logged, nothing scheduled"
        }
    }

    private var legend: some View {
        PeptideFlowLayout(spacing: 10) {
            legendItem(IronTheme.olive, "All scheduled logged")
            legendItem(IronTheme.rust, "Missed")
            legendItem(IronTheme.brass, "Unscheduled")
        }
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IronTheme.textSecondary)
        }
    }
}
