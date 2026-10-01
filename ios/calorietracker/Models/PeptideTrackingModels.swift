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
    /// Optional link to a peptide-assistant inventory row, for its badges only.
    var bridgeInventoryID: String?
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
        bridgeInventoryID: String? = nil,
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
        self.bridgeInventoryID = bridgeInventoryID
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

/// Device-only details for one administration, keyed by client_request_id
/// (or the bridge row id for rows without one).
nonisolated struct PeptideLocalMeta: Codable, Equatable {
    var key: String
    var vialID: String?
    /// Drawn volume the user typed.
    var drawnVolume: Double?
    /// "mL" or "units" (U-100 insulin syringe units; 100 units = 1 mL).
    var drawnUnit: String?

    init(key: String, vialID: String? = nil, drawnVolume: Double? = nil, drawnUnit: String? = nil) {
        self.key = key
        self.vialID = vialID
        self.drawnVolume = drawnVolume
        self.drawnUnit = drawnUnit
    }

    var isEmpty: Bool { vialID == nil && drawnVolume == nil }
}

/// Body of `POST /api/peptides/administrations`.
nonisolated struct PeptideCreatePayload: Codable, Equatable {
    var clientRequestID: String
    var plannedID: String?
    /// ISO-8601 with offset (America/New_York).
    var datetime: String
    var dose: Double?
    var units: String?
    var compound: String?
    var route: String?
    var notes: String?
    var sourceVial: String?
    var person: String?

    func body() -> [String: Any] {
        var body: [String: Any] = [
            "client_request_id": clientRequestID,
            "datetime": datetime,
        ]
        if let plannedID, !plannedID.isEmpty { body["planned_id"] = plannedID }
        if let dose { body["dose"] = dose }
        if let units, !units.isEmpty { body["units"] = units }
        if let compound, !compound.isEmpty { body["compound"] = compound }
        if let route, !route.isEmpty { body["route"] = route }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let sourceVial, !sourceVial.isEmpty { body["source_vial"] = sourceVial }
        if let person, !person.isEmpty { body["person"] = person }
        return body
    }
}

/// `changes` of a PATCH correct. Nil fields are left alone.
nonisolated struct PeptideCorrectionChanges: Codable, Equatable {
    var datetime: String?
    var dose: Double?
    var route: String?
    var notes: String?
    /// Unscheduled rows only.
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

    func dictionary() -> [String: Any] {
        var body: [String: Any] = [:]
        if let datetime { body["datetime"] = datetime }
        if let dose { body["dose"] = dose }
        if let route { body["route"] = route }
        if let notes { body["notes"] = notes }
        if let compound { body["compound"] = compound }
        if let units { body["units"] = units }
        if let sourceVial { body["source_vial"] = sourceVial }
        return body
    }

    /// Applies the changes to a queued create (no reason needed before it syncs).
    func apply(to payload: inout PeptideCreatePayload) {
        if let datetime { payload.datetime = datetime }
        if let dose { payload.dose = dose }
        if let route { payload.route = route.isEmpty ? nil : route }
        if let notes { payload.notes = notes.isEmpty ? nil : notes }
        if let compound { payload.compound = compound }
        if let units { payload.units = units }
        if let sourceVial { payload.sourceVial = sourceVial.isEmpty ? nil : sourceVial }
    }
}

nonisolated enum PeptidePendingKind: String, Codable, Equatable {
    case create
    case correct
    case void
}

/// One queued bridge write. Kept until the bridge accepts it or the user discards it.
nonisolated struct PeptidePendingOp: Codable, Equatable, Identifiable {
    var id: String
    var kind: PeptidePendingKind
    var create: PeptideCreatePayload?
    var rowID: String?
    var reason: String?
    var changes: PeptideCorrectionChanges?
    var attempts: Int
    var lastError: String?
    /// The bridge refused it (4xx). It waits for Retry or Discard.
    var failed: Bool
    var createdAt: Date

    static func makeCreate(_ payload: PeptideCreatePayload, now: Date = Date()) -> PeptidePendingOp {
        PeptidePendingOp(
            id: payload.clientRequestID,
            kind: .create,
            create: payload,
            rowID: nil,
            reason: nil,
            changes: nil,
            attempts: 0,
            lastError: nil,
            failed: false,
            createdAt: now
        )
    }

    static func makeCorrect(rowID: String, reason: String, changes: PeptideCorrectionChanges, now: Date = Date()) -> PeptidePendingOp {
        PeptidePendingOp(
            id: UUID().uuidString.lowercased(),
            kind: .correct,
            create: nil,
            rowID: rowID,
            reason: reason,
            changes: changes,
            attempts: 0,
            lastError: nil,
            failed: false,
            createdAt: now
        )
    }

    static func makeVoid(rowID: String, reason: String, now: Date = Date()) -> PeptidePendingOp {
        PeptidePendingOp(
            id: UUID().uuidString.lowercased(),
            kind: .void,
            create: nil,
            rowID: rowID,
            reason: reason,
            changes: nil,
            attempts: 0,
            lastError: nil,
            failed: false,
            createdAt: now
        )
    }
}

nonisolated enum PeptideSyncState: Equatable {
    case synced
    case pending
    case failed(String)
    /// Recorded by the peptide assistant. Read-only in the app.
    case readOnlyAgent

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// One administration for display: a bridge row or a queued create.
nonisolated struct PeptideLogEntry: Identifiable, Equatable {
    var id: String
    var rowID: String?
    var clientRequestID: String?
    var person: String
    var compound: String
    var dose: Double?
    var units: String?
    var date: Date?
    var datetimeRaw: String
    var route: String?
    var notes: String?
    var sourceVial: String?
    /// "COMPLETED" or "PLANNED" (upper-cased).
    var status: String
    var plannedID: String?
    var scheduleID: String?
    var completedID: String?
    var voided: Bool
    var voidReason: String?
    var recordedVia: String?
    var corrections: [PeptideCorrection]
    var badges: [String]
    var vialID: String?
    var drawnVolume: Double?
    var drawnUnit: String?
    var syncState: PeptideSyncState
    var pendingOpID: String?
    var createdAt: String?
    /// yyyy-MM-dd in America/New_York, computed once from `date`.
    let civilDate: String?

    init(
        id: String,
        rowID: String? = nil,
        clientRequestID: String? = nil,
        person: String,
        compound: String,
        dose: Double? = nil,
        units: String? = nil,
        date: Date? = nil,
        datetimeRaw: String = "",
        route: String? = nil,
        notes: String? = nil,
        sourceVial: String? = nil,
        status: String = "COMPLETED",
        plannedID: String? = nil,
        scheduleID: String? = nil,
        completedID: String? = nil,
        voided: Bool = false,
        voidReason: String? = nil,
        recordedVia: String? = nil,
        corrections: [PeptideCorrection] = [],
        badges: [String] = [],
        vialID: String? = nil,
        drawnVolume: Double? = nil,
        drawnUnit: String? = nil,
        syncState: PeptideSyncState = .synced,
        pendingOpID: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.rowID = rowID
        self.clientRequestID = clientRequestID
        self.person = person
        self.compound = compound
        self.dose = dose
        self.units = units
        self.date = date
        self.datetimeRaw = datetimeRaw
        self.route = route
        self.notes = notes
        self.sourceVial = sourceVial
        self.status = status
        self.plannedID = plannedID
        self.scheduleID = scheduleID
        self.completedID = completedID
        self.voided = voided
        self.voidReason = voidReason
        self.recordedVia = recordedVia
        self.corrections = corrections
        self.badges = badges
        self.vialID = vialID
        self.drawnVolume = drawnVolume
        self.drawnUnit = drawnUnit
        self.syncState = syncState
        self.pendingOpID = pendingOpID
        self.createdAt = createdAt
        self.civilDate = date.map(PeptideMath.civilDate)
    }

    var isCompleted: Bool { status == "COMPLETED" }
    var isPlanned: Bool { status == "PLANNED" }
    /// Counts toward logs, totals and adherence.
    var countsAsTaken: Bool { isCompleted && !voided }
    var isAgentRow: Bool { syncState == .readOnlyAgent }
    /// Unscheduled rows can have compound/units corrected.
    var isScheduled: Bool { plannedID != nil || scheduleID != nil }
    var isPendingCreate: Bool { rowID == nil }
    /// Local meta key.
    var metaKey: String { clientRequestID ?? rowID ?? id }
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
    var drawnUnit: String
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
            drawnUnit: "mL",
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
