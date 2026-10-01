//
//  PeptideRecords.swift
//  calorietracker
//
//  Read models for the peptide bridge. The app does not compute dose,
//  volume, concentration, or unit conversions.
//

import Foundation

struct PeptideTodayResponse: Decodable, Equatable {
    var date: String
    var timezone: String
    var hasActiveSchedules: Bool
    var planned: [PeptideAdministration]
    var completed: [PeptideAdministration]

    enum CodingKeys: String, CodingKey {
        case date, timezone
        case hasActiveSchedules = "has_active_schedules"
        case planned, completed
    }
}

struct PeptideInventoryList: Decodable {
    var inventory: [PeptideInventoryItem]
}

struct PeptideScheduleList: Decodable {
    var schedules: [PeptideSchedule]
}

struct PeptideSchedule: Decodable, Equatable, Identifiable {
    var id: String
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case id, active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        active = (try? container.decode(Bool.self, forKey: .active)) ?? false
    }
}

struct PeptideWarning: Decodable, Equatable, Hashable {
    var type: String
    var text: String

    enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
    }
}

struct PeptideInventoryItem: Decodable, Equatable, Identifiable {
    var id: String
    var compound: String
    var calcGate: String?
    var concentrationBasis: String?
    var identityBasis: String?
    var badges: [String]
    var warnings: [PeptideWarning]

    enum CodingKeys: String, CodingKey {
        case id, compound, badges, warnings
        case calcGate = "calc_gate"
        case concentrationBasis = "concentration_basis"
        case identityBasis = "identity_basis"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        compound = (try? container.decode(String.self, forKey: .compound)) ?? ""
        calcGate = try container.decodeIfPresent(String.self, forKey: .calcGate)
        concentrationBasis = try container.decodeIfPresent(String.self, forKey: .concentrationBasis)
        identityBasis = try container.decodeIfPresent(String.self, forKey: .identityBasis)
        badges = (try? container.decode([String].self, forKey: .badges)) ?? []
        let decodedWarnings = (try? container.decode([PeptideWarning].self, forKey: .warnings)) ?? []
        warnings = decodedWarnings.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct PeptideAdministration: Decodable, Equatable, Identifiable {
    var id: String
    var datetime: String
    var compound: String
    var dose: Double?
    var units: String?
    var volume: Double?
    var volumeUnits: String?
    var route: String?
    var notes: String?
    var status: String
    var plannedId: String?
    var scheduleId: String?
    var completedId: String?
    var sourceVial: String?
    var voided: Bool
    var doseDeviatesFromPlanned: Bool
    var volumeBasis: String?
    var calcGate: String?
    var concentrationBasis: String?
    var badges: [String]
    /// v1.1: nil means Jonathan (legacy rows).
    var person: String? = nil
    /// "app" or "peptide-agent".
    var recordedVia: String? = nil
    var voidReason: String? = nil
    var correctionHistory: [PeptideCorrection] = []
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var clientRequestID: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, datetime, compound, dose, units, volume, route, notes, status, badges
        case person
        case recordedVia = "recorded_via"
        case voidReason = "void_reason"
        case correctionHistory = "correction_history"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case clientRequestID = "client_request_id"
        case volumeUnits = "volume_units"
        case plannedId = "planned_id"
        case scheduleId = "schedule_id"
        case completedId = "completed_id"
        case sourceVial = "source_vial"
        case voided
        case doseDeviatesFromPlanned = "dose_deviates_from_planned"
        case volumeBasis = "volume_basis"
        case calcGate = "calc_gate"
        case concentrationBasis = "concentration_basis"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        datetime = (try? container.decode(String.self, forKey: .datetime)) ?? ""
        compound = (try? container.decode(String.self, forKey: .compound)) ?? ""
        dose = Self.double(container, .dose)
        units = try container.decodeIfPresent(String.self, forKey: .units)
        volume = Self.double(container, .volume)
        volumeUnits = try container.decodeIfPresent(String.self, forKey: .volumeUnits)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        status = (try? container.decode(String.self, forKey: .status)) ?? ""
        plannedId = try container.decodeIfPresent(String.self, forKey: .plannedId)
        scheduleId = try container.decodeIfPresent(String.self, forKey: .scheduleId)
        completedId = try container.decodeIfPresent(String.self, forKey: .completedId)
        sourceVial = try container.decodeIfPresent(String.self, forKey: .sourceVial)
        voided = (try? container.decode(Bool.self, forKey: .voided)) ?? false
        doseDeviatesFromPlanned = (try? container.decode(Bool.self, forKey: .doseDeviatesFromPlanned)) ?? false
        volumeBasis = try container.decodeIfPresent(String.self, forKey: .volumeBasis)
        calcGate = try container.decodeIfPresent(String.self, forKey: .calcGate)
        concentrationBasis = try container.decodeIfPresent(String.self, forKey: .concentrationBasis)
        badges = (try? container.decode([String].self, forKey: .badges)) ?? []
        person = try? container.decodeIfPresent(String.self, forKey: .person)
        recordedVia = try? container.decodeIfPresent(String.self, forKey: .recordedVia)
        voidReason = try? container.decodeIfPresent(String.self, forKey: .voidReason)
        let lossyHistory = (try? container.decode([PeptideLossy<PeptideCorrection>].self, forKey: .correctionHistory)) ?? []
        correctionHistory = lossyHistory.compactMap(\.value)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        clientRequestID = try? container.decodeIfPresent(String.self, forKey: .clientRequestID)
    }

    private static func double(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Double? {
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

/// One entry of a row's `correction_history`. `old` and `new` can be any JSON
/// value on the bridge; they are kept as display strings only.
nonisolated struct PeptideCorrection: Codable, Equatable, Hashable {
    var at: String
    var field: String
    var old: String
    var new: String
    var reason: String
    var by: String
    var derived: Bool

    enum CodingKeys: String, CodingKey {
        case at, field, old, new, reason, by, derived
    }

    init(at: String, field: String, old: String, new: String, reason: String, by: String, derived: Bool = false) {
        self.at = at
        self.field = field
        self.old = old
        self.new = new
        self.reason = reason
        self.by = by
        self.derived = derived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = (try? container.decode(String.self, forKey: .at)) ?? ""
        field = (try? container.decode(String.self, forKey: .field)) ?? ""
        old = (try? container.decode(PeptideJSONDisplay.self, forKey: .old))?.text ?? "—"
        new = (try? container.decode(PeptideJSONDisplay.self, forKey: .new))?.text ?? "—"
        reason = (try? container.decode(String.self, forKey: .reason)) ?? ""
        by = (try? container.decode(String.self, forKey: .by)) ?? ""
        derived = (try? container.decode(Bool.self, forKey: .derived)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        try container.encode(field, forKey: .field)
        try container.encode(old, forKey: .old)
        try container.encode(new, forKey: .new)
        try container.encode(reason, forKey: .reason)
        try container.encode(by, forKey: .by)
        try container.encode(derived, forKey: .derived)
    }
}

/// Any JSON value rendered as plain text for the correction trail.
nonisolated struct PeptideJSONDisplay: Decodable {
    var text: String

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() {
                text = "—"
                return
            }
            if let value = try? single.decode(String.self) {
                text = value.isEmpty ? "—" : value
                return
            }
            if let value = try? single.decode(Bool.self) {
                text = value ? "true" : "false"
                return
            }
            if let value = try? single.decode(Double.self) {
                text = PeptideMath.number(value)
                return
            }
        }
        if var list = try? decoder.unkeyedContainer() {
            var parts: [String] = []
            while !list.isAtEnd {
                if let item = try? list.decode(PeptideJSONDisplay.self) {
                    parts.append(item.text)
                } else {
                    break
                }
            }
            text = parts.joined(separator: ", ")
            return
        }
        if let object = try? decoder.container(keyedBy: AnyKey.self) {
            let parts: [String] = object.allKeys.sorted { $0.stringValue < $1.stringValue }.map { key in
                let value = (try? object.decode(PeptideJSONDisplay.self, forKey: key))?.text ?? "—"
                return key.stringValue + ": " + value
            }
            text = parts.joined(separator: ", ")
            return
        }
        text = "—"
    }
}

/// Decodes one array element without failing the whole list.
struct PeptideLossy<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// `GET /api/peptides/administrations` (bridge v1.1).
struct PeptideAdministrationList: Decodable {
    var from: String
    var to: String
    var timezone: String
    var administrations: [PeptideAdministration]

    enum CodingKeys: String, CodingKey {
        case from, to, timezone, administrations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? container.decode(String.self, forKey: .from)) ?? ""
        to = (try? container.decode(String.self, forKey: .to)) ?? ""
        timezone = (try? container.decode(String.self, forKey: .timezone)) ?? "America/New_York"
        let rows = try container.decode([PeptideLossy<PeptideAdministration>].self, forKey: .administrations)
        administrations = rows.compactMap(\.value).filter { !$0.id.isEmpty }
    }
}
