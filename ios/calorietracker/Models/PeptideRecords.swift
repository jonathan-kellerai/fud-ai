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

    enum CodingKeys: String, CodingKey {
        case id, datetime, compound, dose, units, volume, route, notes, status, badges
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
