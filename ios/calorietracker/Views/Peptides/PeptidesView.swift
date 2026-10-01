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
    var person: String
    var compound: String?
}

struct PeptidesView: View {
    @Environment(PeptideLogStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var person: String
    @State private var day: String
    @State private var logRequest: PeptideLogRequest?
    @State private var editTarget: PeptideLogEntry?
    @State private var voidTarget: PeptideLogEntry?
    @State private var failedTarget: PeptideLogEntry?
    @State private var showVoided = false
    @State private var actionMessage: String?

    init(initialPerson: String? = nil, initialDay: String? = nil) {
        _person = State(initialValue: initialPerson.map(PeptidePerson.normalized) ?? PeptidePersonMemory.load())
        _day = State(initialValue: initialDay ?? PeptideMath.civilDate(Date()))
    }

    private var today: String { PeptideMath.civilDate(Date()) }

    var body: some View {
        List {
            headerSection
            bannerSection
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
        .refreshable {
            await store.refresh()
        }
        .task {
            await store.refreshIfStale()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.flush() }
            }
        }
        .onChange(of: person) { _, newValue in
            PeptidePersonMemory.save(newValue)
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
        .confirmationDialog(
            "Not saved to the bridge",
            isPresented: failedDialogBinding,
            titleVisibility: .visible,
            presenting: failedTarget
        ) { entry in
            Button("Retry") {
                if let opID = entry.pendingOpID { store.retry(opID: opID) }
            }
            Button("Discard", role: .destructive) {
                if let opID = entry.pendingOpID { store.discard(opID: opID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.syncState.failureMessage ?? "The bridge didn't accept this entry.")
        }
    }

    private var failedDialogBinding: Binding<Bool> {
        Binding(
            get: { failedTarget != nil },
            set: { shown in if !shown { failedTarget = nil } }
        )
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                PeptideScreenTitle(title: "Peptides", subtitle: "What you took, as you typed it.")
                PeptidePersonToggle(person: $person)
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
                    .font(.system(size: 17, weight: .heavy))
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

    @ViewBuilder
    private var bannerSection: some View {
        let pending = store.pendingCount
        let failed = store.failedCount
        if pending > 0 || failed > 0 || store.lastSyncError != nil || store.historyUnavailable || actionMessage != nil {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let actionMessage {
                        PeptideBanner(title: actionMessage, tone: IronTheme.bloodText, actionTitle: "Dismiss") {
                            self.actionMessage = nil
                        }
                    }
                    if pending > 0 || failed > 0 {
                        PeptideBanner(
                            title: queueTitle(pending: pending, failed: failed),
                            message: "Saved on this phone. They go to the bridge when it answers.",
                            tone: failed > 0 ? IronTheme.rust : IronTheme.brass,
                            actionTitle: "Sync now"
                        ) {
                            Task { await store.flush() }
                        }
                    }
                    if store.historyUnavailable {
                        PeptideBanner(title: "Bridge needs the history update", message: PeptideLogStore.historyUnavailableMessage, tone: IronTheme.rust)
                    } else if let error = store.lastSyncError {
                        PeptideBanner(title: "Couldn’t refresh from the bridge", message: error, tone: IronTheme.rust, actionTitle: "Retry") {
                            Task { await store.refresh() }
                        }
                    }
                }
                .peptideListRow()
            }
        }
    }

    private func queueTitle(pending: Int, failed: Int) -> String {
        var parts: [String] = []
        if pending > 0 { parts.append(pending == 1 ? "1 change waiting to sync" : "\(pending) changes waiting to sync") }
        if failed > 0 { parts.append(failed == 1 ? "1 not accepted" : "\(failed) not accepted") }
        return parts.joined(separator: " · ")
    }

    private var summarySection: some View {
        Section {
            PeptideDaySummaryCard(person: person, day: day)
                .peptideListRow()
        } header: {
            IronSectionTitle(title: day == today ? "Today" : "Day summary")
        }
    }

    @ViewBuilder
    private var dueSection: some View {
        let items = PeptideMath.dueItems(date: day, person: person, schedules: store.schedules, entries: store.entries)
        let planned = store.plannedEntries(day, person: person)
        if !items.isEmpty || !planned.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        dueRow(item)
                    }
                    ForEach(planned) { entry in
                        plannedRow(entry)
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
                if item.taken {
                    PeptideTag(text: "Logged", tone: IronTheme.olive)
                }
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
                    logRequest = PeptideLogRequest(person: person, compound: item.schedule.compound)
                }
                .buttonStyle(IronCompactButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plannedRow(_ entry: PeptideLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.compound)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                PeptideTag(text: entry.completedID == nil ? "Planned" : "Taken", tone: entry.completedID == nil ? IronTheme.brass : IronTheme.olive)
            }
            Text("From the peptide assistant · " + PeptideMath.amountText(entry.dose, entry.units))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if entry.completedID == nil {
                Text("Mark it taken from the Home card.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logSection: some View {
        let rows = store.dayEntries(day, person: person, includeVoided: showVoided).reversed()
        let voidedCount = store.dayEntries(day, person: person, includeVoided: true).filter(\.voided).count
        return Section {
            Button {
                logRequest = PeptideLogRequest(person: person, compound: nil)
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
            PeptideEntryDetailView(entryID: entry.id, clientRequestID: entry.clientRequestID)
        } label: {
            PeptideLogRow(
                entry: entry,
                vialName: store.vial(id: entry.vialID)?.displayName,
                onFailedTap: { failedTarget = entry }
            )
        }
        .listRowBackground(IronTheme.surface)
        .listRowSeparatorTint(IronTheme.hairline)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !entry.isAgentRow && !entry.voided {
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
        let low = store.lowStockVials(person: person).count
        let active = store.personVials(person: person).count
        let schedules = store.personSchedules(person: person).filter(\.active).count
        return Section {
            NavigationLink {
                PeptideVialsView(person: person)
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
                PeptideScheduleView(person: person)
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
                PeptideHistoryView(person: person)
            } label: {
                linkLabel("History", systemImage: "chart.bar.xaxis", detail: "Calendar, totals, chart", warning: nil)
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
        PeptideLogSheet(person: request.person, compound: request.compound)
    }
}

/// Today's (or the picked day's) count, totals per unit and adherence.
struct PeptideDaySummaryCard: View {
    @Environment(PeptideLogStore.self) private var store
    let person: String
    let day: String

    var body: some View {
        let summary = PeptideMath.dailySummary(entries: store.entries, date: day, person: person)
        let due = PeptideMath.dueItems(date: day, person: person, schedules: store.schedules, entries: store.entries)
        let planned = store.plannedEntries(day, person: person)
        let dueCount = due.count + planned.count
        let doneCount = due.filter(\.taken).count + planned.filter { $0.completedID != nil }.count
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
            if summary.totals.isEmpty {
                Text("No doses logged for \(PeptidePerson.name(person)).")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(summary.totals) { total in
                    PeptideDetailRow(label: total.compound, value: total.text)
                }
            }
            if let first = summary.first, let last = summary.last {
                Text(first == last ? "At \(PeptideMath.timeText(first))" : "First \(PeptideMath.timeText(first)) · last \(PeptideMath.timeText(last))")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Totals add only matching units. mg and mcg stay separate; IU is never converted.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(IronTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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
