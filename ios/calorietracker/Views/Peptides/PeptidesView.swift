//
//  PeptidesView.swift
//  calorietracker
//
//  Peptides section root: today's summary, what the user's own schedules list
//  as due, and the daily log. Logs what the user enters; sets no doses and
//  recommends no protocol.
//

import SwiftUI

/// Opens the log sheet. The amount always starts empty.
struct PeptideLogRequest: Identifiable {
    let id = UUID().uuidString
    var compound: String?
}

struct PeptidesView: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var day: String
    @State private var logRequest: PeptideLogRequest?
    @State private var editTarget: PeptideLogEntry?
    @State private var voidTarget: PeptideLogEntry?
    @State private var showVoided = false

    /// Fixed "now" for the date strip and due list (Visual QA). Nil uses the
    /// live date, refreshed on foreground and when the day changes.
    private let referenceDate: Date?
    @State private var now: Date

    init(initialDay: String? = nil, referenceDate: Date? = nil) {
        let start = referenceDate ?? Date()
        _day = State(initialValue: initialDay ?? PeptideMath.civilDate(start))
        _now = State(initialValue: start)
        self.referenceDate = referenceDate
    }

    private var today: String { PeptideMath.civilDate(referenceDate ?? now) }

    var body: some View {
        List {
            headerSection
            summarySection
            dueSection
            logSection
            linksSection
            footerSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(IronTheme.canvas)
        .navigationTitle("Peptides")
        .navigationBarTitleDisplayMode(.inline)
        .peptideLiveDate($now, fixed: referenceDate != nil)
        .onChange(of: today) { oldToday, newToday in
            // Showing "Today" when the date rolls over: follow it.
            if day == oldToday { day = newToday }
        }
        .sheet(item: $logRequest) { request in
            PeptideLogSheetHost(request: request)
        }
        .sheet(item: $editTarget) { entry in
            PeptideEditEntrySheet(entry: entry)
        }
        .sheet(item: $voidTarget) { entry in
            PeptideVoidSheet(entry: entry)
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                PeptideScreenTitle(title: "Peptides", subtitle: "What you took, as you typed it.")
                if store.heldAsideCount > 0 {
                    PeptideSecondProfileCard()
                }
                dateStrip
            }
            .peptideListRow()
        }
    }

    private var dateStrip: some View {
        HStack(spacing: 8) {
            Button {
                day = ReconMath.addDays(day, -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous day")
            VStack(spacing: 2) {
                Text(day == today ? "Today" : ReconMath.formatDateShort(day))
                    .font(IronTheme.heavyHeadline)
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .foregroundStyle(IronTheme.textPrimary)
                Text(ReconMath.formatDate(day))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                day = ReconMath.addDays(day, 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(day >= today)
            .accessibilityLabel("Next day")
            if day != today {
                Button("Today") { day = today }
                    .font(.system(size: 13, weight: .heavy))
                    .fontWidth(.condensed)
                    .buttonStyle(.borderless)
            }
        }
        .foregroundStyle(IronTheme.bloodText)
        .padding(.horizontal, 4)
        .ironCard()
    }

    private var summarySection: some View {
        Section {
            PeptideDaySummaryCard(day: day)
                .peptideListRow()
        } header: {
            IronSectionTitle(title: day == today ? "Today" : "Day summary")
        }
    }

    @ViewBuilder
    private var dueSection: some View {
        let items = PeptideMath.dueItems(date: day, schedules: store.schedules, entries: store.entries)
        if !items.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        dueRow(item)
                    }
                }
                .padding(12)
                .ironCard()
                .peptideListRow()
            } header: {
                IronSectionTitle(title: "Due")
            }
        }
    }

    private func dueRow(_ item: PeptideMath.DueItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.schedule.compound)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                PeptideDueStatus(taken: item.taken).pill
            }
            Text("Your schedule: " + PeptideMath.scheduleText(item.schedule))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let count = item.weekCount {
                Text("\(count) logged this week")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            if !item.taken {
                Button("Log") {
                    logRequest = PeptideLogRequest(compound: item.schedule.compound)
                }
                .buttonStyle(IronCompactButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logSection: some View {
        let rows = store.dayEntries(day, includeVoided: showVoided).reversed()
        let voidedCount = store.dayEntries(day, includeVoided: true).filter(\.voided).count
        return Section {
            Button {
                logRequest = PeptideLogRequest(compound: nil)
            } label: {
                Label("Log dose", systemImage: "plus")
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .peptideListRow()
            if rows.isEmpty {
                Text(day == today ? "Nothing logged today." : "Nothing logged this day.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .peptideListRow()
            }
            ForEach(Array(rows)) { entry in
                logRow(entry)
            }
            if voidedCount > 0 {
                Toggle(showVoided ? "Showing voided (\(voidedCount))" : "Show voided (\(voidedCount))", isOn: $showVoided)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
                    .tint(IronTheme.blood)
                    .peptideListRow()
            }
        } header: {
            IronSectionTitle(title: "Daily log")
        }
    }

    private func logRow(_ entry: PeptideLogEntry) -> some View {
        NavigationLink {
            PeptideEntryDetailView(entryID: entry.id)
        } label: {
            PeptideLogRow(entry: entry, vialName: store.vial(id: entry.vialID)?.displayName)
        }
        .listRowBackground(IronTheme.surface)
        .listRowSeparatorTint(IronTheme.hairline)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !entry.voided {
                Button {
                    voidTarget = entry
                } label: {
                    Label("Void", systemImage: "xmark.circle")
                }
                .tint(IronTheme.bloodPressed)
                Button {
                    editTarget = entry
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(IronTheme.concrete)
            }
        }
    }

    private var linksSection: some View {
        let low = store.lowStockVials().count
        let active = store.vialList().count
        let schedules = store.schedules.filter(\.active).count
        return Section {
            NavigationLink {
                PeptideVialsView()
            } label: {
                linkLabel(
                    "Vials",
                    systemImage: "testtube.2",
                    detail: active == 1 ? "1 active" : "\(active) active",
                    warning: low > 0 ? (low == 1 ? "1 low" : "\(low) low") : nil
                )
            }
            .listRowBackground(IronTheme.surface)
            NavigationLink {
                PeptideScheduleView(referenceDate: referenceDate)
            } label: {
                linkLabel(
                    "Schedule & adherence",
                    systemImage: "calendar",
                    detail: schedules == 1 ? "1 schedule" : "\(schedules) schedules",
                    warning: nil
                )
            }
            .listRowBackground(IronTheme.surface)
            NavigationLink {
                PeptideHistoryView(referenceDate: referenceDate)
            } label: {
                linkLabel("History", systemImage: "chart.bar.xaxis", detail: "Calendar, totals, chart", warning: nil)
            }
            .listRowBackground(IronTheme.surface)
            NavigationLink {
                PeptideSettingsView()
            } label: {
                linkLabel(
                    "Settings",
                    systemImage: "gearshape",
                    detail: "Syringe scale: " + (store.syringeScale?.label ?? "not set"),
                    warning: nil
                )
            }
            .listRowBackground(IronTheme.surface)
        } header: {
            IronSectionTitle(title: "More")
        }
    }

    private func linkLabel(_ title: String, systemImage: String, detail: String, warning: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(detail)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                    if let warning {
                        Text(warning)
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(IronTheme.rust)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(IronTheme.bloodText)
        }
    }

    private var footerSection: some View {
        Section {
            PeptideFooter()
                .peptideListRow()
                .padding(.bottom, 24)
        }
    }
}

/// Wraps the log sheet so `sheet(item:)` stays a single short expression.
struct PeptideLogSheetHost: View {
    let request: PeptideLogRequest

    var body: some View {
        PeptideLogSheet(compound: request.compound)
    }
}

/// Today's (or the picked day's) count, totals per unit and adherence.
struct PeptideDaySummaryCard: View {
    @Environment(PeptideLogStore.self) private var store
    let day: String

    var body: some View {
        let summary = PeptideMath.dailySummary(entries: store.entries, date: day)
        let due = PeptideMath.dueItems(date: day, schedules: store.schedules, entries: store.entries)
        let dueCount = due.count
        let doneCount = due.filter(\.taken).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(summary.count)")
                        .font(.system(size: 40, weight: .black).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(IronTheme.textPrimary)
                    PeptideFieldLabel(summary.count == 1 ? "Dose logged" : "Doses logged")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(dueCount == 0 ? "—" : "\(doneCount) of \(dueCount)")
                        .font(.system(size: 28, weight: .black).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(dueCount > 0 && doneCount >= dueCount ? IronTheme.olive : IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    PeptideFieldLabel(dueCount == 0 ? "Nothing scheduled" : "Due logged")
                }
            }
            if summary.count == 0 {
                Text("No draws logged.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let first = summary.first, let last = summary.last {
                Text(first == last ? "At \(PeptideMath.timeText(first))" : "First \(PeptideMath.timeText(first)) · last \(PeptideMath.timeText(last))")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ironCard(rule: true)
    }
}

extension View {
    /// Clear, full-width List row with Peptides spacing.
    func peptideListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}
