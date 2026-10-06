//
//  PeptideRecords.swift
//  calorietracker
//
//  Bridge-era peptide rows, read only to migrate a version-1 log, plus the
//  tolerant decoding and correction trail the local log still uses.
//

import Foundation

/// One cached bridge row from a version-1 log.
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

    /// Every field is read on its own: one odd field never drops the row.
    /// Only a row without an id is skipped (by the list that holds it).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = PeptideDecode.string(container, .id) ?? ""
        datetime = PeptideDecode.string(container, .datetime) ?? ""
        compound = PeptideDecode.string(container, .compound) ?? ""
        dose = PeptideDecode.double(container, .dose)
        units = PeptideDecode.string(container, .units)
        volume = PeptideDecode.double(container, .volume)
        volumeUnits = PeptideDecode.string(container, .volumeUnits)
        route = PeptideDecode.string(container, .route)
        notes = PeptideDecode.string(container, .notes)
        status = PeptideDecode.string(container, .status) ?? ""
        plannedId = PeptideDecode.string(container, .plannedId)
        scheduleId = PeptideDecode.string(container, .scheduleId)
        completedId = PeptideDecode.string(container, .completedId)
        sourceVial = PeptideDecode.string(container, .sourceVial)
        voided = PeptideDecode.bool(container, .voided) ?? false
        doseDeviatesFromPlanned = PeptideDecode.bool(container, .doseDeviatesFromPlanned) ?? false
        volumeBasis = PeptideDecode.string(container, .volumeBasis)
        calcGate = PeptideDecode.string(container, .calcGate)
        concentrationBasis = PeptideDecode.string(container, .concentrationBasis)
        badges = PeptideDecode.strings(container, .badges)
        person = PeptideDecode.string(container, .person)
        recordedVia = PeptideDecode.string(container, .recordedVia)
        voidReason = PeptideDecode.string(container, .voidReason)
        let lossyHistory = (try? container.decode([PeptideLossy<PeptideCorrection>].self, forKey: .correctionHistory)) ?? []
        correctionHistory = lossyHistory.compactMap(\.value)
        createdAt = PeptideDecode.string(container, .createdAt)
        updatedAt = PeptideDecode.string(container, .updatedAt)
        clientRequestID = PeptideDecode.string(container, .clientRequestID)
    }
}

/// Field-by-field tolerant reads for bridge JSON. Numbers may arrive as
/// strings and strings as numbers; anything else reads as nil.
nonisolated enum PeptideDecode {
    static func string<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> String? {
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return PeptideMath.number(value) }
        if let value = try? container.decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    static func double<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Double? {
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        if let value = try? container.decode(Double.self, forKey: key) { return value.isFinite ? value : nil }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let text = try? container.decode(String.self, forKey: key),
           let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite {
            return value
        }
        return nil
    }

    static func bool<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Bool? {
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let text = try? container.decode(String.self, forKey: key) {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no", "": return false
            default: return nil
            }
        }
        return nil
    }

    /// A list of strings; non-string items are skipped, numbers become text.
    static func strings<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> [String] {
        if let values = try? container.decode([String].self, forKey: key) { return values }
        guard let items = try? container.decode([PeptideJSONDisplay].self, forKey: key) else { return [] }
        return items.map(\.text).filter { !$0.isEmpty && $0 != "—" }
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
