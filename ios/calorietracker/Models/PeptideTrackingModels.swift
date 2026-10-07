//
//  PeptideTrackingModels.swift
//  calorietracker
//
//  Local Peptides models. Every amount here is a number the user typed.
//  The app logs what the user enters; it sets no doses and recommends no protocol.
//

import Foundation

/// Peptides track one person: whoever uses this phone. Build 67 and earlier
/// tagged every record with one of two profiles in a `person` field. This is
/// the only place those saved raw values are read, to sort old records: the
/// first profile (or none) is the user's own; the second profile's records are
/// held aside until the user keeps or deletes them. Nothing new is tagged.
nonisolated enum PeptideLegacyProfile: Equatable {
    case own
    case second

    // Legacy raw values of build 67's `person` field. Migration decoding
    // only: never written or shown. Tests build old saves from these.
    /// The first profile: its records (and untagged ones) are the user's own.
    static let firstProfileRawValue = "jonathan"
    /// The second profile: its records are held aside.
    static let secondProfileRawValue = "victoria"

    init(raw: String?) {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case Self.secondProfileRawValue:
            self = .second
        default:
            // The first profile, an empty tag or no tag at all.
            self = .own
        }
    }
}

/// A record as any build saved it, plus the legacy profile it was tagged with
/// (the `person` key, read here and nowhere else).
struct PeptideProfiled<Value: Decodable>: Decodable {
    var value: Value
    var profile: PeptideLegacyProfile

    private enum LegacyKeys: String, CodingKey {
        case person
    }

    init(value: Value, profile: PeptideLegacyProfile) {
        self.value = value
        self.profile = profile
    }

    init(from decoder: Decoder) throws {
        value = try Value(from: decoder)
        let container = try decoder.container(keyedBy: LegacyKeys.self)
        profile = PeptideLegacyProfile(raw: try? container.decodeIfPresent(String.self, forKey: .person))
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
    var compound: String
    var isBlend: Bool
    var components: [PeptideVialComponent]
    var diluentML: Double?
    /// yyyy-MM-dd.
    var mixedOn: String?
    /// The user ticked "I mixed this vial with exactly this diluent volume".
    var concentrationConfirmed: Bool
    /// When they ticked it (Reconstitute, step 3). Who: this phone's user.
    /// Nil for vials confirmed before build 68, and whenever not confirmed.
    var concentrationConfirmedAt: Date?
    var lowStockThresholdML: Double?
    var status: PeptideVialStatus
    var notes: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        compound: String,
        isBlend: Bool = false,
        components: [PeptideVialComponent] = [],
        diluentML: Double? = nil,
        mixedOn: String? = nil,
        concentrationConfirmed: Bool = false,
        concentrationConfirmedAt: Date? = nil,
        lowStockThresholdML: Double? = nil,
        status: PeptideVialStatus = .active,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.compound = compound
        self.isBlend = isBlend
        self.components = components
        self.diluentML = diluentML
        self.mixedOn = mixedOn
        self.concentrationConfirmed = concentrationConfirmed
        self.concentrationConfirmedAt = concentrationConfirmed ? concentrationConfirmedAt : nil
        self.lowStockThresholdML = lowStockThresholdML
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmed = compound.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Vial" : trimmed
    }

    /// A single-compound vial from Reconstitute: the amount and diluent as
    /// typed, confirmed only when the user ticked step 3, stamped with when.
    /// Re-confirming an existing vial keeps its other details.
    static func reconstituted(
        id: String,
        compound: String,
        amount: Double,
        unit: String,
        diluentML: Double,
        mixedOn: String?,
        confirmedAt: Date?,
        existing: PeptideVial?,
        now: Date
    ) -> PeptideVial {
        let componentID = existing?.components.first?.id ?? UUID().uuidString
        return PeptideVial(
            id: id,
            compound: compound.trimmingCharacters(in: .whitespacesAndNewlines),
            components: [PeptideVialComponent(id: componentID, name: compound.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount, unit: unit)],
            diluentML: diluentML,
            mixedOn: mixedOn,
            concentrationConfirmed: confirmedAt != nil,
            concentrationConfirmedAt: confirmedAt,
            lowStockThresholdML: existing?.lowStockThresholdML,
            status: existing?.status ?? .active,
            notes: existing?.notes ?? "",
            createdAt: existing?.createdAt ?? now
        )
    }

    /// The amounts and diluent as typed differ from `other`'s.
    func numbersDiffer(from other: PeptideVial) -> Bool {
        diluentML != other.diluentML
            || components.map(\.amount) != other.components.map(\.amount)
            || components.map(\.unit) != other.components.map(\.unit)
    }

    /// `edited` saved over this vial. A confirmation was for exactly these
    /// numbers, so changing the amount or diluent clears it, unless the user
    /// ticked "I mixed this vial..." again in the same edit (a new stamp).
    func applyingEdit(_ edited: PeptideVial) -> PeptideVial {
        var result = edited
        let restamped = edited.concentrationConfirmedAt != nil && edited.concentrationConfirmedAt != concentrationConfirmedAt
        if numbersDiffer(from: edited) && !restamped {
            result.concentrationConfirmed = false
            result.concentrationConfirmedAt = nil
        }
        return result
    }
}

/// A schedule the user typed. The amount is the user's own note and is never
/// used to fill a log.
nonisolated struct PeptideUserSchedule: Codable, Equatable, Identifiable, Hashable {
    var id: String
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
        lhs.id == rhs.id && lhs.compound == rhs.compound
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

    var count: Int { entries.count + vials.count + schedules.count }
    var isEmpty: Bool { count == 0 }

    /// `other`'s records whose id isn't here yet, added after these.
    func adding(_ other: PeptideRecordSet) -> PeptideRecordSet {
        var result = self
        var entryIDs = Set(entries.map(\.id))
        result.entries += other.entries.filter { entryIDs.insert($0.id).inserted }
        var vialIDs = Set(vials.map(\.id))
        result.vials += other.vials.filter { vialIDs.insert($0.id).inserted }
        var scheduleIDs = Set(schedules.map(\.id))
        result.schedules += other.schedules.filter { scheduleIDs.insert($0.id).inserted }
        return result
    }
}

/// Records read from a save or a file, sorted by the legacy profile an
/// earlier build tagged them with: the user's own, and those held aside.
struct PeptideRecordsByProfile: Equatable {
    var own = PeptideRecordSet()
    var heldAside = PeptideRecordSet()

    init(own: PeptideRecordSet = PeptideRecordSet(), heldAside: PeptideRecordSet = PeptideRecordSet()) {
        self.own = own
        self.heldAside = heldAside
    }

    init(
        entries: [PeptideProfiled<PeptideLogEntry>],
        vials: [PeptideProfiled<PeptideVial>],
        schedules: [PeptideProfiled<PeptideUserSchedule>]
    ) {
        for item in entries {
            if item.profile == .second { heldAside.entries.append(item.value) } else { own.entries.append(item.value) }
        }
        for item in vials {
            if item.profile == .second { heldAside.vials.append(item.value) } else { own.vials.append(item.value) }
        }
        for item in schedules {
            if item.profile == .second { heldAside.schedules.append(item.value) } else { own.schedules.append(item.value) }
        }
    }
}

/// The unit a draw was typed in. Raw values match what build 67 saved.
nonisolated enum PeptideDrawUnit: String, Codable, CaseIterable, Identifiable {
    case units
    case milliliters = "mL"

    var id: String { rawValue }

    /// "units" / "mL", after a number.
    var label: String {
        switch self {
        case .units: "units"
        case .milliliters: "mL"
        }
    }

    /// Compact form for a week cell: "u" / "mL".
    var shortLabel: String {
        switch self {
        case .units: "u"
        case .milliliters: "mL"
        }
    }

    /// For VoiceOver.
    var spokenLabel: String {
        switch self {
        case .units: "units"
        case .milliliters: "millilitres"
        }
    }
}

/// Insulin-syringe scale: how many units are marked per mL. Recorded by the
/// user in Settings (or for one draw); never assumed.
nonisolated enum PeptideSyringeScale: Int, Codable, CaseIterable, Identifiable {
    case u100 = 100
    case u50 = 50
    case u40 = 40

    var id: Int { rawValue }

    var unitsPerML: Double { Double(rawValue) }

    /// "U-100".
    var label: String { "U-\(rawValue)" }
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
    /// The draw as typed, and its unit. Set together.
    var draw: Double?
    var drawUnit: PeptideDrawUnit?

    init(
        datetime: String? = nil,
        dose: Double? = nil,
        route: String? = nil,
        notes: String? = nil,
        compound: String? = nil,
        units: String? = nil,
        sourceVial: String? = nil,
        draw: Double? = nil,
        drawUnit: PeptideDrawUnit? = nil
    ) {
        self.datetime = datetime
        self.dose = dose
        self.route = route
        self.notes = notes
        self.compound = compound
        self.units = units
        self.sourceVial = sourceVial
        self.draw = draw
        self.drawUnit = drawUnit
    }

    var isEmpty: Bool {
        datetime == nil && dose == nil && route == nil && notes == nil
            && compound == nil && units == nil && sourceVial == nil
            && draw == nil && drawUnit == nil
    }
}

/// One draw the user logged, saved on this phone. Every number is what the
/// user typed. The `...AtSave` fields are copied once, when the entry is
/// saved, and never re-read from Settings or the vial.
nonisolated struct PeptideLogEntry: Identifiable, Equatable, Codable {
    var id: String
    var compound: String
    /// An amount typed in an earlier version (before draws). New entries have none.
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
    /// The draw, exactly as typed.
    var drawnVolume: Double?
    var drawnUnit: PeptideDrawUnit?
    var createdAt: String?
    /// The syringe scale in force when saved (Settings, or this draw's own).
    var syringeScaleAtSave: PeptideSyringeScale?
    /// The linked vial's concentration in mg/mL when saved, from its typed numbers.
    var vialConcentrationAtSave: Double?
    /// The linked vial was confirmed ("I mixed this vial...") when saved.
    var concentrationConfirmedAtSave: Bool
    var vialIDAtSave: String?
    /// yyyy-MM-dd in America/New_York, computed once from `date`.
    let civilDate: String?

    enum CodingKeys: String, CodingKey {
        case id, compound, dose, units, datetime, route, notes, voided, corrections
        case sourceVial = "source_vial"
        case voidReason = "void_reason"
        case vialID = "vial_id"
        case drawnVolume = "drawn_volume"
        case drawnUnit = "drawn_unit"
        case createdAt = "created_at"
        case syringeScaleAtSave = "syringe_scale_at_save"
        case vialConcentrationAtSave = "vial_concentration_at_save"
        case concentrationConfirmedAtSave = "concentration_confirmed_at_save"
        case vialIDAtSave = "vial_id_at_save"
    }

    init(
        id: String,
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
        drawnUnit: PeptideDrawUnit? = nil,
        createdAt: String? = nil,
        syringeScaleAtSave: PeptideSyringeScale? = nil,
        vialConcentrationAtSave: Double? = nil,
        concentrationConfirmedAtSave: Bool = false,
        vialIDAtSave: String? = nil
    ) {
        self.id = id
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
        self.syringeScaleAtSave = syringeScaleAtSave
        self.vialConcentrationAtSave = vialConcentrationAtSave
        self.concentrationConfirmedAtSave = concentrationConfirmedAtSave
        self.vialIDAtSave = vialIDAtSave
        self.civilDate = date.map(PeptideMath.civilDate)
    }

    /// `id` and `compound` are required; anything else that's missing reads as
    /// empty. Entries saved before the snapshot fields read as not recorded.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty id")
        }
        let datetime = (try container.decodeIfPresent(String.self, forKey: .datetime)) ?? ""
        let unit = (try? container.decodeIfPresent(String.self, forKey: .drawnUnit)).flatMap { $0 }
        let scale = (try? container.decodeIfPresent(Int.self, forKey: .syringeScaleAtSave)).flatMap { $0 }
        self.init(
            id: id,
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
            drawnUnit: unit.flatMap(PeptideDrawUnit.init(rawValue:)),
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt),
            syringeScaleAtSave: scale.flatMap(PeptideSyringeScale.init(rawValue:)),
            vialConcentrationAtSave: try container.decodeIfPresent(Double.self, forKey: .vialConcentrationAtSave),
            concentrationConfirmedAtSave: (try container.decodeIfPresent(Bool.self, forKey: .concentrationConfirmedAtSave)) ?? false,
            vialIDAtSave: try container.decodeIfPresent(String.self, forKey: .vialIDAtSave)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
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
        try container.encodeIfPresent(drawnUnit?.rawValue, forKey: .drawnUnit)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(syringeScaleAtSave?.rawValue, forKey: .syringeScaleAtSave)
        try container.encodeIfPresent(vialConcentrationAtSave, forKey: .vialConcentrationAtSave)
        try container.encode(concentrationConfirmedAtSave, forKey: .concentrationConfirmedAtSave)
        try container.encodeIfPresent(vialIDAtSave, forKey: .vialIDAtSave)
    }

    /// Counts toward logs, totals and adherence.
    var countsAsTaken: Bool { !voided }

    /// "50 units" / "0.1 mL", or nil when no draw was typed.
    var drawText: String? {
        guard let drawnVolume, let drawnUnit else { return nil }
        return PeptideMath.drawText(drawnVolume, drawnUnit)
    }

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
        let newDraw = changes.draw ?? drawnVolume
        let newDrawUnit = changes.drawUnit ?? drawnUnit
        record("draw", drawText, newDraw.flatMap { value in newDrawUnit.map { PeptideMath.drawText(value, $0) } })
        record("route", route, changes.route ?? route)
        record("notes", notes, changes.notes ?? notes)
        record("source_vial", sourceVial, changes.sourceVial ?? sourceVial)
        var newDate = date
        if let typed = changes.datetime { newDate = PeptideMath.parseISO8601(typed) }
        return PeptideLogEntry(
            id: id,
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
            drawnVolume: newDraw,
            drawnUnit: newDraw == nil ? nil : newDrawUnit,
            createdAt: createdAt,
            syringeScaleAtSave: syringeScaleAtSave,
            vialConcentrationAtSave: vialConcentrationAtSave,
            concentrationConfirmedAtSave: concentrationConfirmedAtSave,
            vialIDAtSave: vialIDAtSave
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

/// What the log sheet collects. The draw starts EMPTY and no unit is picked:
/// the app never fills a draw or a dose.
nonisolated struct PeptideLogDraft: Equatable {
    var compound: String
    var drawText: String
    /// Nil until the user picks units or mL.
    var drawUnit: PeptideDrawUnit?
    /// This draw's own syringe scale. Nil uses the one in Settings.
    var scaleOverride: PeptideSyringeScale?
    var takenAt: Date
    var site: String
    var vialID: String?
    var notes: String

    static func new(compound: String = "", now: Date = Date()) -> PeptideLogDraft {
        PeptideLogDraft(
            compound: compound,
            drawText: "",
            drawUnit: nil,
            scaleOverride: nil,
            takenAt: now,
            site: "",
            vialID: nil,
            notes: ""
        )
    }

    var draw: Double? {
        let value = ReconMath.toNumber(drawText)
        return value.isFinite ? value : nil
    }

    var trimmedCompound: String { compound.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSite: String { site.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated enum PeptideDraftField: String, Hashable {
    case compound
    case draw
    case unit
    case site
    case notes
}
