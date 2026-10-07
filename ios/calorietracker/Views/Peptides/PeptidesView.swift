//
//  PeptidesView.swift
//  calorietracker
//
//  The one Peptides screen: Today, Week and Vials. Logs what the user enters;
//  sets no doses and recommends no protocol. Everything stays on this phone.
//

import SwiftUI

/// Opens the log sheet. The draw always starts empty.
struct PeptideLogRequest: Identifiable {
    let id = UUID().uuidString
    var compound: String?
}

struct PeptidesView: View {
    @Environment(PeptideLogStore.self) private var store
    @State private var tab: PeptideTab
    @State private var logRequest: PeptideLogRequest?

    /// Fixed "now" (Visual QA). Nil uses the live date, refreshed on
    /// foreground and when the day changes.
    private let referenceDate: Date?
    @State private var now: Date

    init(initialTab: PeptideTab = .today, referenceDate: Date? = nil) {
        _tab = State(initialValue: initialTab)
        _now = State(initialValue: referenceDate ?? Date())
        self.referenceDate = referenceDate
    }

    private var today: String { PeptideMath.civilDate(referenceDate ?? now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.heldAsideCount > 0 {
                    PeptideSecondProfileCard()
                }
                PeptideTabPicker(tab: $tab)
                storageNotes
                switch tab {
                case .today:
                    PeptideTodayView(today: today) { compound in
                        logRequest = PeptideLogRequest(compound: compound)
                    }
                case .week:
                    PeptideWeekView(today: today, referenceDate: referenceDate)
                case .vials:
                    PeptideVialsView()
                }
                PeptideFooter()
                    .padding(.bottom, 24)
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Peptides")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PeptideSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(IronTheme.brass)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Peptide settings")
                .accessibilityHint("Syringe scale")
            }
        }
        .peptideLiveDate($now, fixed: referenceDate != nil)
        .sheet(item: $logRequest) { request in
            PeptideLogSheetHost(request: request)
        }
    }

    /// Why the saved log isn't complete or isn't being saved, as plain text.
    @ViewBuilder
    private var storageNotes: some View {
        ForEach([store.storageNote, store.persistError].compactMap { $0 }, id: \.self) { note in
            Text(note)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .peptideAccentCard(IronTheme.rust)
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
