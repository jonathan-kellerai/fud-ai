//
//  PeptideTrackingModels.swift
//  calorietracker
//
//  Local Peptides models. Every amount here is a number the user typed.
//  The app logs what the user enters; it sets no doses and recommends no protocol.
//

import Foundation

/// The two people the Peptides section tracks. Keys match Recon Bench.
nonisolated enum PeptidePerson {
    static let jonathan = "jonathan"
    static let victoria = "victoria"
    static let order = ReconMath.peopleOrder

    /// Bridge rows with no person are Jonathan's (legacy rows).
    static func normalized(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? jonathan : trimmed
    }

    static func name(_ raw: String?) -> String {
        let key = normalized(raw)
        return ReconMath.peopleNames[key] ?? key.capitalized
    }
}

nonisolated struct PeptideVialComponent: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Amount in the vial as the user typed it. Nil until the user enters it.
    var amount: Double?
    /// "mg", "mcg" or "IU".
    var unit: String

    init(id: String = UUID().uuidString, name: String, amount: Double? = nil, unit: String = "mg") {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
    }
}

nonisolated enum PeptideVialStatus: String, Codable, Equatable {
    case active
    case finished
}

/// A vial the user mixed. Remaining volume is only calculated from these numbers.
nonisolated struct PeptideVial: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var person: String
    var compound: String
    var isBlend: Bool
    var components: [PeptideVialComponent]
    var diluentML: Double?
    /// yyyy-MM-dd.
    var mixedOn: String?
    /// The user ticked "I mixed this vial with exactly this diluent volume".
    var concentrationConfirmed: Bool
    var lowStockThresholdML: Double?
    var status: PeptideVialStatus
    var notes: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        person: String,
        compound: String,
        isBlend: Bool = false,
        components: [PeptideVialComponent] = [],
        diluentML: Double? = nil,
        mixedOn: String? = nil,
        concentrationConfirmed: Bool = false,
        lowStockThresholdML: Double? = nil,
        status: PeptideVialStatus = .active,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.person = person
        self.compound = compound
        self.isBlend = isBlend
        self.components = components
        self.diluentML = diluentML
        self.mixedOn = mixedOn
        self.concentrationConfirmed = concentrationConfirmed
        self.lowStockThresholdML = lowStockThresholdML
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmed = compound.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Vial" : trimmed
    }
}

/// A schedule the user typed. The amount is the user's own note and is never
/// used to fill a log.
nonisolated struct PeptideUserSchedule: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var person: String
    var compound: String
    var amount: Double?
    var units: String?
    /// ReconMath frequency types: "daily", "weekly", "weekdays", "everyN",
    /// plus "perWeek" (n times per week, no fixed days).
    var frequency: ReconMath.Frequency
    /// yyyy-MM-dd, America/New_York.
    var startDate: String
    var endDate: String?
    /// Minutes after midnight.
    var timeOfDay: Int?
    var active: Bool
    var notes: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        person: String,
        compound: String,
        amount: Double? = nil,
        units: String? = nil,
        frequency: ReconMath.Frequency,
        startDate: String,
        endDate: String? = nil,
        timeOfDay: Int? = nil,
        active: Bool = true,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.person = person
        self.compound = compound
        self.amount = amount
        self.units = units
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.timeOfDay = timeOfDay
        self.active = active
        self.notes = notes
        self.createdAt = createdAt
    }

    static func == (lhs: PeptideUserSchedule, rhs: PeptideUserSchedule) -> Bool {
        lhs.id == rhs.id && lhs.person == rhs.person && lhs.compound == rhs.compound
            && lhs.amount == rhs.amount && lhs.units == rhs.units && lhs.frequency == rhs.frequency
            && lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate && lhs.timeOfDay == rhs.timeOfDay
            && lhs.active == rhs.active && lhs.notes == rhs.notes && lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Everything the Peptides log holds: logged doses, vials and schedules.
nonisolated struct PeptideRecordSet: Equatable {
    var entries: [PeptideLogEntry]
    var vials: [PeptideVial]
    var schedules: [PeptideUserSchedule]

    init(entries: [PeptideLogEntry] = [], vials: [PeptideVial] = [], schedules: [PeptideUserSchedule] = []) {
        self.entries = entries
        self.vials = vials
        self.schedules = schedules
    }
}

/// What a correction changes. Nil fields are left alone.
nonisolated struct PeptideCorrectionChanges: Codable, Equatable {
    /// ISO-8601 with offset (America/New_York).
    var datetime: String?
    var dose: Double?
    var route: String?
    var notes: String?
    var compound: String?
    var units: String?
    var sourceVial: String?

    init(
        datetime: String? = nil,
        dose: Double? = nil,
        route: String? = nil,
        notes: String? = nil,
        compound: String? = nil,
        units: String? = nil,
        sourceVial: String? = nil
    ) {
        self.datetime = datetime
        self.dose = dose
        self.route = route
        self.notes = notes
        self.compound = compound
        self.units = units
        self.sourceVial = sourceVial
    }

    var isEmpty: Bool {
        datetime == nil && dose == nil && route == nil && notes == nil
            && compound == nil && units == nil && sourceVial == nil
    }
}

/// One administration the user logged, saved on this phone. Every amount is
/// what the user typed.
nonisolated struct PeptideLogEntry: Identifiable, Equatable, Codable {
    var id: String
    var person: String
    var compound: String
    var dose: Double?
    var units: String?
    var date: Date?
    /// ISO-8601 with offset, as saved.
    var datetimeRaw: String
    var route: String?
    var notes: String?
    /// Where the dose came from, as recorded (kept from bridge-era rows).
    var sourceVial: String?
    var voided: Bool
    var voidReason: String?
    var corrections: [PeptideCorrection]
    var vialID: String?
    /// Drawn volume the user typed.
    var drawnVolume: Double?
    /// "mL" or "units" (U-100 insulin syringe units; 100 units = 1 mL).
    var drawnUnit: String?
    var createdAt: String?
    /// yyyy-MM-dd in America/New_York, computed once from `date`.
    let civilDate: String?

    enum CodingKeys: String, CodingKey {
        case id, person, compound, dose, units, datetime, route, notes, voided, corrections
        case sourceVial = "source_vial"
        case voidReason = "void_reason"
        case vialID = "vial_id"
        case drawnVolume = "drawn_volume"
        case drawnUnit = "drawn_unit"
        case createdAt = "created_at"
    }

    init(
        id: String,
        person: String,
        compound: String,
        dose: Double? = nil,
        units: String? = nil,
        date: Date? = nil,
        datetimeRaw: String = "",
        route: String? = nil,
        notes: String? = nil,
        sourceVial: String? = nil,
        voided: Bool = false,
        voidReason: String? = nil,
        corrections: [PeptideCorrection] = [],
        vialID: String? = nil,
        drawnVolume: Double? = nil,
        drawnUnit: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.person = person
        self.compound = compound
        self.dose = dose
        self.units = units
        self.date = date
        self.datetimeRaw = datetimeRaw.isEmpty ? (date.map(PeptideMath.iso8601NewYork) ?? "") : datetimeRaw
        self.route = route
        self.notes = notes
        self.sourceVial = sourceVial
        self.voided = voided
        self.voidReason = voidReason
        self.corrections = corrections
        self.vialID = vialID
        self.drawnVolume = drawnVolume
        self.drawnUnit = drawnUnit
        self.createdAt = createdAt
        self.civilDate = date.map(PeptideMath.civilDate)
    }

    /// `id` and `compound` are required; anything else that's missing reads as empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty id")
        }
        let datetime = (try container.decodeIfPresent(String.self, forKey: .datetime)) ?? ""
        self.init(
            id: id,
            person: PeptidePerson.normalized(try container.decodeIfPresent(String.self, forKey: .person)),
            compound: try container.decode(String.self, forKey: .compound),
            dose: try container.decodeIfPresent(Double.self, forKey: .dose),
            units: try container.decodeIfPresent(String.self, forKey: .units),
            date: PeptideMath.parseISO8601(datetime),
            datetimeRaw: datetime,
            route: try container.decodeIfPresent(String.self, forKey: .route),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            sourceVial: try container.decodeIfPresent(String.self, forKey: .sourceVial),
            voided: (try container.decodeIfPresent(Bool.self, forKey: .voided)) ?? false,
            voidReason: try container.decodeIfPresent(String.self, forKey: .voidReason),
            corrections: (try container.decodeIfPresent([PeptideCorrection].self, forKey: .corrections)) ?? [],
            vialID: try container.decodeIfPresent(String.self, forKey: .vialID),
            drawnVolume: try container.decodeIfPresent(Double.self, forKey: .drawnVolume),
            drawnUnit: try container.decodeIfPresent(String.self, forKey: .drawnUnit),
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(person, forKey: .person)
        try container.encode(compound, forKey: .compound)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encodeIfPresent(units, forKey: .units)
        try container.encode(datetimeRaw, forKey: .datetime)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(sourceVial, forKey: .sourceVial)
        try container.encode(voided, forKey: .voided)
        try container.encodeIfPresent(voidReason, forKey: .voidReason)
        try container.encode(corrections, forKey: .corrections)
        try container.encodeIfPresent(vialID, forKey: .vialID)
        try container.encodeIfPresent(drawnVolume, forKey: .drawnVolume)
        try container.encodeIfPresent(drawnUnit, forKey: .drawnUnit)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    /// Counts toward logs, totals and adherence.
    var countsAsTaken: Bool { !voided }

    /// This entry with `changes` applied, each changed field added to the
    /// correction trail with the user's reason.
    func corrected(_ changes: PeptideCorrectionChanges, reason: String, at: String) -> PeptideLogEntry {
        var trail = corrections
        func record(_ field: String, _ old: String?, _ new: String?) {
            let before = Self.trailText(old)
            let after = Self.trailText(new)
            guard before != after else { return }
            trail.append(PeptideCorrection(at: at, field: field, old: before, new: after, reason: reason, by: "app"))
        }
        let datetime = changes.datetime ?? datetimeRaw
        record("datetime", datetimeRaw, datetime)
        record("dose", dose.map(PeptideMath.number), (changes.dose ?? dose).map(PeptideMath.number))
        record("compound", compound, changes.compound ?? compound)
        record("units", units, changes.units ?? units)
        record("route", route, changes.route ?? route)
        record("notes", notes, changes.notes ?? notes)
        record("source_vial", sourceVial, changes.sourceVial ?? sourceVial)
        var newDate = date
        if let typed = changes.datetime { newDate = PeptideMath.parseISO8601(typed) }
        return PeptideLogEntry(
            id: id,
            person: person,
            compound: changes.compound ?? compound,
            dose: changes.dose ?? dose,
            units: changes.units ?? units,
            date: newDate,
            datetimeRaw: datetime,
            route: Self.replacing(route, with: changes.route),
            notes: Self.replacing(notes, with: changes.notes),
            sourceVial: Self.replacing(sourceVial, with: changes.sourceVial),
            voided: voided,
            voidReason: voidReason,
            corrections: trail,
            vialID: vialID,
            drawnVolume: drawnVolume,
            drawnUnit: drawnUnit,
            createdAt: createdAt
        )
    }

    /// This entry voided with the user's reason. It stays in history.
    func voiding(reason: String, at: String) -> PeptideLogEntry {
        var entry = self
        entry.voided = true
        entry.voidReason = reason
        entry.corrections.append(PeptideCorrection(at: at, field: "voided", old: "false", new: "true", reason: reason, by: "app"))
        return entry
    }

    private static func trailText(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    /// A typed change replaces the value; an empty one clears it.
    private static func replacing(_ current: String?, with change: String?) -> String? {
        guard let change else { return current }
        return change.isEmpty ? nil : change
    }
}

/// What the log sheet collects. Starts with the amount EMPTY: the app never
/// fills an amount.
nonisolated struct PeptideLogDraft: Equatable {
    var person: String
    var compound: String
    var amountText: String
    /// Nil until the user picks one (or picks a single-component vial).
    var units: String?
    var takenAt: Date
    var site: String
    var vialID: String?
    var drawnText: String
    /// "mL" or "units". Nil until the user picks one.
    var drawnUnit: String?
    var notes: String

    static func new(person: String, compound: String = "", now: Date = Date()) -> PeptideLogDraft {
        PeptideLogDraft(
            person: person,
            compound: compound,
            amountText: "",
            units: nil,
            takenAt: now,
            site: "",
            vialID: nil,
            drawnText: "",
            drawnUnit: nil,
            notes: ""
        )
    }

    var amount: Double? {
        let value = ReconMath.toNumber(amountText)
        return value.isFinite ? value : nil
    }

    var drawnVolume: Double? {
        let value = ReconMath.toNumber(drawnText)
        return value.isFinite ? value : nil
    }

    var trimmedCompound: String { compound.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSite: String { site.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated enum PeptideDraftField: String, Hashable {
    case compound
    case amount
    case units
    case drawn
    case site
    case notes
}
