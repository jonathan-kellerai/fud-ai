//
//  PeptideArchive.swift
//  calorietracker
//
//  The one file format for peptide export, import and the iCloud backup:
//  {format, format_version, exported_at, vials, schedules, entries}.
//  Records only: every number is one the user (or their records) entered.
//

import Foundation

/// What an import adds, counted before anything is applied.
struct PeptideImportSummary: Equatable {
    var newVials = 0
    var newSchedules = 0
    var newEntries = 0
    /// New vials whose file names no person; they go to the person picked on import.
    var newVialsWithoutPerson = 0
    /// Records whose id is already on this phone (left unchanged).
    var alreadyHere = 0
    /// Records in the file that couldn't be read.
    var skipped = 0

    var added: Int { newVials + newSchedules + newEntries }
}

enum PeptideArchiveError: LocalizedError, Equatable {
    case tooLarge
    case unreadable
    case wrongFormat
    case newerVersion
    /// A restore needs every record: some lists or records couldn't be read.
    case incomplete

    var errorDescription: String? {
        switch self {
        case .tooLarge: "This file is larger than 1 MB, so it isn't a peptides file from this app."
        case .unreadable: "This file couldn't be read as JSON."
        case .wrongFormat: "This isn't a JL Physical peptides file."
        case .newerVersion: "This file was made by a newer version of the app. Update the app, then import it."
        case .incomplete: "Some peptide records in the backup couldn't be read."
        }
    }
}

struct PeptideArchive: Equatable {
    static let format = "jl-peptides"
    static let formatVersion = 1
    static let maxBytes = 1_000_000

    var exportedAt: String?
    var vials: [Vial]
    var schedules: [Schedule]
    var entries: [PeptideLogEntry]
    /// Records in the file that couldn't be read. Never written.
    var skipped = 0

    init(exportedAt: String?, vials: [PeptideVial], schedules: [PeptideUserSchedule], entries: [PeptideLogEntry]) {
        self.exportedAt = exportedAt
        self.vials = vials.map { Vial($0) }
        self.schedules = schedules.map { Schedule($0) }
        self.entries = entries
    }

    /// Validates size, format and version before anything is read. With
    /// `complete`, every list must be there and every record readable (a
    /// restore replaces everything); otherwise unreadable records are skipped
    /// and counted (an import only adds).
    static func decode(_ data: Data, complete: Bool = false) throws -> PeptideArchive {
        guard data.count <= maxBytes else { throw PeptideArchiveError.tooLarge }
        let file: FileIn
        do {
            file = try JSONDecoder().decode(FileIn.self, from: data)
        } catch {
            throw PeptideArchiveError.unreadable
        }
        guard file.format == format, let version = file.formatVersion, version >= 1 else {
            throw PeptideArchiveError.wrongFormat
        }
        guard version <= formatVersion else { throw PeptideArchiveError.newerVersion }
        if complete, file.vials == nil || file.schedules == nil || file.entries == nil {
            throw PeptideArchiveError.incomplete
        }
        let vials = (file.vials ?? []).compactMap(\.value)
        let schedules = (file.schedules ?? []).compactMap(\.value)
        let entries = (file.entries ?? []).compactMap(\.value)
        var archive = PeptideArchive(exportedAt: file.exportedAt, vials: [], schedules: [], entries: entries)
        archive.vials = vials
        archive.schedules = schedules
        archive.skipped = ((file.vials?.count ?? 0) - vials.count)
            + ((file.schedules?.count ?? 0) - schedules.count)
            + ((file.entries?.count ?? 0) - entries.count)
        if complete, archive.skipped > 0 { throw PeptideArchiveError.incomplete }
        return archive
    }

    /// A file the user picked (security-scoped). Refuses anything over 1 MB before reading it.
    static func load(from url: URL) throws -> PeptideArchive {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
            throw PeptideArchiveError.tooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw PeptideArchiveError.unreadable
        }
        return try decode(data)
    }

    /// Stable bytes: sorted keys, so the same records always encode the same.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(FileOut(
            format: Self.format,
            formatVersion: Self.formatVersion,
            exportedAt: exportedAt,
            vials: vials,
            schedules: schedules,
            entries: entries
        ))
    }

    static func fileName(exportedOn date: Date) -> String {
        "jl-peptides-" + PeptideMath.civilDate(date) + ".json"
    }

    // MARK: File shape

    private enum FileKeys: String, CodingKey {
        case format, vials, schedules, entries
        case formatVersion = "format_version"
        case exportedAt = "exported_at"
    }

    /// Read side: one unreadable record never drops the rest. A list that is
    /// missing or isn't an array reads as nil.
    private struct FileIn: Decodable {
        var format: String?
        var formatVersion: Int?
        var exportedAt: String?
        var vials: [PeptideLossy<Vial>]?
        var schedules: [PeptideLossy<Schedule>]?
        var entries: [PeptideLossy<PeptideLogEntry>]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: FileKeys.self)
            format = try? container.decodeIfPresent(String.self, forKey: .format)
            formatVersion = try? container.decodeIfPresent(Int.self, forKey: .formatVersion)
            exportedAt = try? container.decodeIfPresent(String.self, forKey: .exportedAt)
            vials = try? container.decodeIfPresent([PeptideLossy<Vial>].self, forKey: .vials)
            schedules = try? container.decodeIfPresent([PeptideLossy<Schedule>].self, forKey: .schedules)
            entries = try? container.decodeIfPresent([PeptideLossy<PeptideLogEntry>].self, forKey: .entries)
        }
    }

    private struct FileOut: Encodable {
        var format: String
        var formatVersion: Int
        var exportedAt: String?
        var vials: [Vial]
        var schedules: [Schedule]
        var entries: [PeptideLogEntry]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: FileKeys.self)
            try container.encode(format, forKey: .format)
            try container.encode(formatVersion, forKey: .formatVersion)
            try container.encodeIfPresent(exportedAt, forKey: .exportedAt)
            try container.encode(vials, forKey: .vials)
            try container.encode(schedules, forKey: .schedules)
            try container.encode(entries, forKey: .entries)
        }
    }

    // MARK: Vial

    /// A vial in the file. `person` may be null (records kept elsewhere have
    /// no owner); amounts are never inferred from notes.
    struct Vial: Codable, Equatable {
        var id: String
        var person: String?
        var compound: String
        var isBlend: Bool
        var components: [Component]
        var diluentML: Double?
        /// yyyy-MM-dd, or nil.
        var mixedOn: String?
        var concentrationConfirmed: Bool
        var lowStockThresholdML: Double?
        var status: PeptideVialStatus
        var notes: String
        var createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, person, compound, components, status, notes
            case isBlend = "is_blend"
            case diluentML = "diluent_ml"
            case mixedOn = "mixed_on"
            case concentrationConfirmed = "concentration_confirmed"
            case lowStockThresholdML = "low_stock_threshold_ml"
            case createdAt = "created_at"
        }

        struct Component: Codable, Equatable {
            var id: String?
            var name: String
            var amount: Double?
            var unit: String
        }

        init(_ vial: PeptideVial) {
            id = vial.id
            person = vial.person
            compound = vial.compound
            isBlend = vial.isBlend
            components = vial.components.map { Component(id: $0.id, name: $0.name, amount: $0.amount, unit: $0.unit) }
            diluentML = vial.diluentML
            mixedOn = vial.mixedOn
            concentrationConfirmed = vial.concentrationConfirmed
            lowStockThresholdML = vial.lowStockThresholdML
            status = vial.status
            notes = vial.notes
            createdAt = PeptideMath.iso8601NewYork(vial.createdAt)
        }

        /// `id` and `compound` are required; anything else missing reads as empty or off.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty id")
            }
            let owner = try container.decodeIfPresent(String.self, forKey: .person)?.trimmingCharacters(in: .whitespacesAndNewlines)
            person = (owner?.isEmpty ?? true) ? nil : owner
            compound = try container.decode(String.self, forKey: .compound)
            isBlend = (try container.decodeIfPresent(Bool.self, forKey: .isBlend)) ?? false
            components = (try container.decodeIfPresent([Component].self, forKey: .components)) ?? []
            diluentML = try container.decodeIfPresent(Double.self, forKey: .diluentML)
            let mixed = try container.decodeIfPresent(String.self, forKey: .mixedOn)
            mixedOn = mixed.flatMap { $0.count == 10 && ReconMath.parseISO($0) != nil ? $0 : nil }
            concentrationConfirmed = (try container.decodeIfPresent(Bool.self, forKey: .concentrationConfirmed)) ?? false
            lowStockThresholdML = try container.decodeIfPresent(Double.self, forKey: .lowStockThresholdML)
            status = (try? container.decodeIfPresent(PeptideVialStatus.self, forKey: .status)) ?? .active
            notes = (try container.decodeIfPresent(String.self, forKey: .notes)) ?? ""
            createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        }

        /// The on-device vial. A vial with no person goes to `person`.
        func vial(defaultPerson person: String, now: Date) -> PeptideVial {
            PeptideVial(
                id: id,
                person: PeptidePerson.normalized(self.person ?? person),
                compound: compound,
                isBlend: isBlend,
                components: components.map {
                    PeptideVialComponent(id: $0.id ?? UUID().uuidString, name: $0.name, amount: $0.amount, unit: $0.unit)
                },
                diluentML: diluentML,
                mixedOn: mixedOn,
                concentrationConfirmed: concentrationConfirmed,
                lowStockThresholdML: lowStockThresholdML,
                status: status,
                notes: notes,
                createdAt: createdAt.flatMap(PeptideMath.parseISO8601) ?? now
            )
        }
    }

    // MARK: Schedule

    /// A schedule the user typed. The amount is a note; it never fills a log.
    struct Schedule: Codable, Equatable {
        var id: String
        var person: String?
        var compound: String
        var amount: Double?
        var units: String?
        var frequency: ReconMath.Frequency
        var startDate: String
        var endDate: String?
        var timeOfDay: Int?
        var active: Bool
        var notes: String
        var createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, person, compound, amount, units, frequency, active, notes
            case startDate = "start_date"
            case endDate = "end_date"
            case timeOfDay = "time_of_day"
            case createdAt = "created_at"
        }

        init(_ schedule: PeptideUserSchedule) {
            id = schedule.id
            person = schedule.person
            compound = schedule.compound
            amount = schedule.amount
            units = schedule.units
            frequency = schedule.frequency
            startDate = schedule.startDate
            endDate = schedule.endDate
            timeOfDay = schedule.timeOfDay
            active = schedule.active
            notes = schedule.notes
            createdAt = PeptideMath.iso8601NewYork(schedule.createdAt)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty id")
            }
            let owner = try container.decodeIfPresent(String.self, forKey: .person)?.trimmingCharacters(in: .whitespacesAndNewlines)
            person = (owner?.isEmpty ?? true) ? nil : owner
            compound = try container.decode(String.self, forKey: .compound)
            amount = try container.decodeIfPresent(Double.self, forKey: .amount)
            units = try container.decodeIfPresent(String.self, forKey: .units)
            frequency = try container.decode(ReconMath.Frequency.self, forKey: .frequency)
            startDate = try container.decode(String.self, forKey: .startDate)
            guard ReconMath.parseISO(startDate) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .startDate, in: container, debugDescription: "Not yyyy-MM-dd")
            }
            endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
            timeOfDay = try container.decodeIfPresent(Int.self, forKey: .timeOfDay)
            active = (try container.decodeIfPresent(Bool.self, forKey: .active)) ?? true
            notes = (try container.decodeIfPresent(String.self, forKey: .notes)) ?? ""
            createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        }

        /// The on-device schedule. A schedule with no person goes to `person`.
        func schedule(defaultPerson person: String, now: Date) -> PeptideUserSchedule {
            PeptideUserSchedule(
                id: id,
                person: PeptidePerson.normalized(self.person ?? person),
                compound: compound,
                amount: amount,
                units: units,
                frequency: frequency,
                startDate: startDate,
                endDate: endDate,
                timeOfDay: timeOfDay,
                active: active,
                notes: notes,
                createdAt: createdAt.flatMap(PeptideMath.parseISO8601) ?? now
            )
        }
    }
}
