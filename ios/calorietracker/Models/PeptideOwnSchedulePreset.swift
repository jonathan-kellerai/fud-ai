//
//  PeptideOwnSchedulePreset.swift
//  calorietracker
//
//  "Load my schedule": the user's own (or prescribed) schedule, typed once
//  here so one tap saves it as records. It is the user's data, not advice:
//  the app never suggests, changes or computes a dose from it. The U-100
//  units the screens show are arithmetic on these vial numbers.
//

import Foundation

nonisolated struct PeptideOwnSchedulePreset: Equatable {
    /// How a vial was made up: amount and unit, and the bacteriostatic water
    /// added (premixed: the volume in it). Nil numbers are unknown.
    struct VialMix: Equatable {
        var amount: Double?
        var unit: String
        var waterML: Double?
        var premixed = false
    }

    struct Item: Equatable, Identifiable {
        /// Fixed, so loading again replaces instead of adding.
        var id: String
        var compound: String
        var slot: PeptideDoseSlot
        var frequency: ReconMath.Frequency
        var dose: PeptideDose
        var route: String?
        var notes = ""
        var vial: VialMix

        var vialID: String { "preset-vial-" + id }
    }

    struct Reminder: Equatable {
        var id: String
        var title: String
        /// yyyy-MM-dd.
        var date: String
        var startMinutes: Int
        var endMinutes: Int
    }

    var items: [Item]
    var reminder: Reminder

    /// Days are ReconMath weekdays: 0 Sunday … 6 Saturday.
    static let own = PeptideOwnSchedulePreset(
        items: [
            Item(
                id: "preset-testosterone", compound: "Testosterone", slot: .am,
                frequency: ReconMath.Frequency(type: "weekdays", days: [1, 4]),
                dose: PeptideDose(amount: 0.3, unit: .milliliters), route: "SQ",
                vial: VialMix(amount: nil, unit: "mg", waterML: nil, premixed: true)
            ),
            Item(
                id: "preset-mt2", compound: "MT2", slot: .am,
                frequency: ReconMath.Frequency(type: "weekdays", days: [2, 5]),
                dose: PeptideDose(amount: 250, unit: .mcg),
                vial: VialMix(amount: 10, unit: "mg", waterML: 2)
            ),
            Item(
                id: "preset-hcg", compound: "hCG", slot: .am,
                frequency: ReconMath.Frequency(type: "weekdays", days: [3, 6]),
                dose: PeptideDose(amount: 500, unit: .iu),
                vial: VialMix(amount: 10_000, unit: "IU", waterML: 2)
            ),
            Item(
                id: "preset-glp3", compound: "GLP3", slot: .am,
                frequency: ReconMath.Frequency(type: "weekly", days: [0]),
                dose: PeptideDose(amount: 2, unit: .mg), notes: "identity unverified",
                vial: VialMix(amount: 10, unit: "mg", waterML: 1)
            ),
            Item(
                id: "preset-tesamorelin", compound: "Tesamorelin", slot: .pm,
                frequency: ReconMath.Frequency(type: "daily"),
                dose: PeptideDose(amount: 1.4, unit: .mg),
                vial: VialMix(amount: 5, unit: "mg", waterML: 0.5)
            ),
            Item(
                id: "preset-bpc157", compound: "BPC-157", slot: .pm,
                frequency: ReconMath.Frequency(type: "daily"),
                dose: PeptideDose(amount: 500, unit: .mcg),
                vial: VialMix(amount: 10, unit: "mg", waterML: 3)
            ),
        ],
        reminder: Reminder(
            id: "preset-labs",
            title: "Labs: draw before testosterone injection",
            date: "2026-12-31",
            startMinutes: 8 * 60,
            endMinutes: 10 * 60
        )
    )

    /// The schedules, starting `startDate`. One already saved under an
    /// item's id keeps its start date and when it was made.
    func schedules(startDate: String, existing: [PeptideUserSchedule], now: Date) -> [PeptideUserSchedule] {
        items.map { item in
            let earlier = existing.first { $0.id == item.id }
            return PeptideUserSchedule(
                id: item.id,
                compound: item.compound,
                frequency: item.frequency,
                startDate: earlier?.startDate ?? startDate,
                notes: item.notes,
                createdAt: earlier?.createdAt ?? now,
                dose: item.dose,
                slot: item.slot,
                route: item.route,
                origin: .preset
            )
        }
    }

    /// One vial per item, mixed `mixedOn`, its numbers confirmed by loading
    /// (the confirmation sheet lists them). One already saved under the
    /// vial's id keeps its mixed date, status, notes and confirmation time.
    func vials(mixedOn: String, existing: [PeptideVial], now: Date) -> [PeptideVial] {
        items.map { item in
            let earlier = existing.first { $0.id == item.vialID }
            let mix = item.vial
            return PeptideVial(
                id: item.vialID,
                compound: item.compound,
                components: [PeptideVialComponent(id: item.vialID + "-c", name: item.compound, amount: mix.amount, unit: mix.unit)],
                diluentML: mix.waterML,
                mixedOn: earlier?.mixedOn ?? mixedOn,
                concentrationConfirmed: !mix.premixed,
                concentrationConfirmedAt: mix.premixed ? nil : (earlier?.concentrationConfirmedAt ?? now),
                lowStockThresholdML: earlier?.lowStockThresholdML,
                status: earlier?.status ?? .active,
                notes: earlier?.notes ?? item.notes,
                createdAt: earlier?.createdAt ?? now,
                premixed: mix.premixed
            )
        }
    }

    func reminders(existing: [PeptideReminder], now: Date) -> [PeptideReminder] {
        let earlier = existing.first { $0.id == reminder.id }
        return [PeptideReminder(
            id: reminder.id,
            title: reminder.title,
            date: reminder.date,
            startMinutes: reminder.startMinutes,
            endMinutes: reminder.endMinutes,
            origin: .preset,
            createdAt: earlier?.createdAt ?? now
        )]
    }

    /// The confirmation sheet's lines, one per record, in order.
    func summaryLines() -> [String] {
        items.map { item in
            var parts = [item.slot.label, PeptideMath.frequencyText(item.frequency), item.compound, item.dose.text]
            if let route = item.route { parts.append(route) }
            var line = parts.joined(separator: " · ")
            if PeptideCompoundCatalog.isPrescription(item.compound) { line += " (Prescription)" }
            if !item.notes.isEmpty { line += " — " + item.notes }
            return line
        } + [reminder.title + " · " + ReconMath.formatDate(reminder.date) + " · "
            + PeptideMath.clockText(minutes: reminder.startMinutes) + "–" + PeptideMath.clockText(minutes: reminder.endMinutes)]
    }

    /// "MT2: 10 mg + 2 mL water, mixed today" lines for the vials.
    func vialLines() -> [String] {
        items.map { item in
            let mix = item.vial
            if mix.premixed { return item.compound + ": premixed, concentration not entered" }
            let amount = mix.amount.map { PeptideMath.number($0) + " " + mix.unit } ?? "amount not entered"
            let water = mix.waterML.map { PeptideMath.number($0) + " mL bacteriostatic water" } ?? "water not entered"
            return item.compound + ": " + amount + " + " + water
        }
    }
}
