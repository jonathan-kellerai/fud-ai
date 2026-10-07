//
//  WorkoutImportFile.swift
//  calorietracker
//
//  The bridge's workout export (`jl-workouts-export-v1`), read once from a
//  file into the on-device log: workouts and their sets, nothing calculated.
//

import Foundation

struct WorkoutImportFile {
    static let format = "jl-workouts-export-v1"
    static let maxBytes = 5_000_000

    var exportedAt: String?
    /// Readable workouts, sets in set order, in file order.
    var workouts: [WorkoutDetailResponse]
    /// Workouts in the file that couldn't be read.
    var skipped: Int

    static func decode(_ data: Data) throws -> WorkoutImportFile {
        guard data.count <= maxBytes else { throw WorkoutImportError.tooLarge }
        let file: FileIn
        do {
            file = try JSONDecoder().decode(FileIn.self, from: data)
        } catch {
            throw WorkoutImportError.unreadable
        }
        guard file.format == format else { throw WorkoutImportError.wrongFormat }
        guard let rows = file.workouts else { throw WorkoutImportError.unreadable }
        let workouts = rows.compactMap(\.value).filter(isUsable).map { detail in
            WorkoutDetailResponse(workout: detail.workout, sets: detail.sets.sorted { $0.setOrder < $1.setOrder })
        }
        return WorkoutImportFile(exportedAt: file.exportedAt, workouts: workouts, skipped: rows.count - workouts.count)
    }

    /// A file the user picked (security-scoped). Refuses anything over the cap before reading it.
    static func load(from url: URL) throws -> WorkoutImportFile {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
            throw WorkoutImportError.tooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw WorkoutImportError.unreadable
        }
        return try decode(data)
    }

    /// A workout needs an id and a session date to be listed and counted.
    private static func isUsable(_ detail: WorkoutDetailResponse) -> Bool {
        !detail.workout.id.trimmingCharacters(in: .whitespaces).isEmpty
            && SessionDateFormatting.yearMonthDay(from: detail.workout.sessionDate) != nil
    }

    private struct FileIn: Decodable {
        var format: String?
        var exportedAt: String?
        var workouts: [WorkoutLossy<WorkoutDetailResponse>]?

        enum CodingKeys: String, CodingKey {
            case format, workouts
            case exportedAt = "exported_at_utc"
        }
    }
}

enum WorkoutImportError: LocalizedError, Equatable {
    case wrongFormat
    case tooLarge
    case unreadable

    var errorDescription: String? {
        switch self {
        case .wrongFormat: "This isn't a JL workouts export (jl-workouts-export-v1)."
        case .tooLarge: "This file is too large to be a workouts export."
        case .unreadable: "This file couldn't be read as a workouts export."
        }
    }
}

/// What an import adds. Duplicates are workouts already on this phone (by id
/// or content hash) or repeated in the file.
struct WorkoutImportSummary: Equatable {
    var added: Int
    var duplicates: Int
    var skipped: Int

    /// "11 workouts imported, 0 duplicates".
    var resultText: String {
        "\(WorkoutCount.text(added)) imported, \(duplicates) \(duplicates == 1 ? "duplicate" : "duplicates")"
    }
}

enum WorkoutCount {
    /// "1 workout", "11 workouts".
    static func text(_ count: Int) -> String {
        count == 1 ? "1 workout" : "\(count) workouts"
    }
}
