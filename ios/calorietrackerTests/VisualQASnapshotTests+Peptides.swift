import SwiftUI
import XCTest
@testable import calorietracker

/// Shots 130-134: the build-72 peptide schedule (AM / PM slots, planned doses,
/// the lab reminder, Load my schedule, vial doses left). The store holds the
/// own-schedule preset plus synthetic taps (VisualQAPeptideFixtures.swift);
/// "now" is Thu 2026-12-31 07:30 New York, the lab-reminder morning.
extension VisualQASnapshotTests {
    private var scheduleNow: Date { VisualQAFixtures.peptideScheduleReferenceDate }

    private func ownSchedule(_ tab: PeptideTab) -> some View {
        VisualQATabShell(selected: .more) {
            VisualQAPushed(rootTitle: "More") {
                PeptidesView(initialTab: tab, referenceDate: VisualQAFixtures.peptideScheduleReferenceDate)
            }
        }
    }

    private func withOwnSchedule(_ body: () async throws -> Void) async throws {
        VisualQAFixtures.loadsOwnPeptideSchedule = true
        defer { VisualQAFixtures.loadsOwnPeptideSchedule = false }
        try await body()
    }

    /// Schedule list grouped AM / PM, with planned doses, units and the Prescription badge.
    func test130PeptideScheduleAMPM() async throws {
        let store = PeptideLogStore(persistence: .inMemory)
        VisualQAFixtures.loadOwnPeptideSchedule(store)
        XCTAssertEqual(store.schedules.filter { $0.daySlot == .am }.count, 4)
        XCTAssertEqual(store.schedules.filter { $0.daySlot == .pm }.count, 2)
        try await withOwnSchedule {
            try await capture("130-peptide-schedule-am-pm", heightMultiplier: 3.2) { _ in
                VisualQATabShell(selected: .more) {
                    VisualQAPushed(rootTitle: "Peptides") { PeptideScheduleView(referenceDate: self.scheduleNow) }
                }
            }
        }
    }

    /// The editor on Testosterone: AM, days of week Mon/Thu, 0.3 mL, SQ.
    func test131PeptideScheduleEditorWeekdaysAndUnits() async throws {
        let schedule = try XCTUnwrap(PeptideOwnSchedulePreset.own
            .schedules(startDate: "2026-12-28", existing: [], now: VisualQAFixtures.peptideScheduleReferenceDate).first)
        XCTAssertEqual(schedule.frequency.days, [1, 4])
        try await withOwnSchedule {
            try await capture("131-peptide-schedule-editor", heightMultiplier: 3, sheet: {
                PeptideScheduleEditor(schedule: schedule)
            }) { _ in
                VisualQATabShell(selected: .more) {
                    VisualQAPushed(rootTitle: "Peptides") { PeptideScheduleView(referenceDate: self.scheduleNow) }
                }
            }
        }
    }

    /// Today on Thu 31 Dec: the lab reminder above the testosterone dose in AM, two compounds in PM.
    func test132PeptidesTodayLabReminderDay() async throws {
        let store = PeptideLogStore(persistence: .inMemory)
        VisualQAFixtures.loadOwnPeptideSchedule(store)
        let am = try XCTUnwrap(store.dayPlan("2026-12-31").slots.first)
        XCTAssertEqual(am.items.map(\.id), ["reminder-preset-labs", "dose-preset-testosterone"])
        try await withOwnSchedule {
            try await capture("132-peptides-today-lab-reminder", heightMultiplier: 2.6) { _ in
                self.ownSchedule(.today)
            }
        }
    }

    /// Load my schedule: everything that will be saved, before anything changes.
    func test133PeptidePresetConfirmation() async throws {
        try await capture("133-peptide-preset-confirmation", heightMultiplier: 2, sheet: {
            PeptidePresetSheet(today: "2026-12-31", now: VisualQAFixtures.peptideScheduleReferenceDate)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Peptides") { PeptideScheduleView(referenceDate: self.scheduleNow) }
            }
        }
    }

    /// Vials: each mixing record with doses left; Tesamorelin after three doses asks to remix.
    func test134PeptideVialDosesLeft() async throws {
        let store = PeptideLogStore(persistence: .inMemory)
        VisualQAFixtures.loadOwnPeptideSchedule(store)
        let tesa = try XCTUnwrap(store.plannedVial(for: "Tesamorelin"))
        XCTAssertEqual(store.supply(for: tesa)?.remixSoon, true)
        try await withOwnSchedule {
            try await capture("134-peptide-vials-doses-left", heightMultiplier: 4) { _ in
                self.ownSchedule(.vials)
            }
        }
    }
}
