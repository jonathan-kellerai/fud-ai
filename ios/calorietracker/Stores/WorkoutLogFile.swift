//
//  WorkoutLogFile.swift
//  calorietracker
//
//  Where the workout log is saved. DeviceLogFile reads and writes the bytes;
//  WorkoutLogStore owns what they mean.
//

import Foundation

enum WorkoutLogPersistence {
    /// `Application Support/WorkoutLog/workout_log_v1.json` in the app's own container.
    case applicationSupport
    /// Nothing is written (Visual QA).
    case inMemory
    /// A file (tests).
    case file(URL)
}

struct WorkoutLogFile {
    static let fileName = "workout_log_v1.json"

    let persistence: WorkoutLogPersistence

    var isInMemory: Bool {
        if case .inMemory = persistence { return true }
        return false
    }

    var url: URL? {
        switch persistence {
        case .inMemory:
            return nil
        case .file(let url):
            return url
        case .applicationSupport:
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            return support.appendingPathComponent("WorkoutLog", isDirectory: true).appendingPathComponent(Self.fileName)
        }
    }

    /// No UserDefaults fallback: the app's own Application Support is always there.
    private var file: DeviceLogFile {
        DeviceLogFile(url: url, defaults: nil, defaultsKey: "workout.log.v1")
    }

    /// Missing, the bytes, or a file that is there but can't be read now.
    func read() -> DeviceLogRead {
        if isInMemory { return .missing }
        return file.readFile()
    }

    /// True only when the copy is on disk and reads back the same.
    @discardableResult
    func keepUnreadable(_ data: Data) -> Bool {
        file.keepUnreadable(data)
    }

    /// The log as it was before an import changed it, as `workout_log_v1.pre-import-<stamp>.json`.
    func keepBeforeImport(_ data: Data, now: Date = Date()) -> Bool {
        file.keepCopy(data, label: "pre-import", now: now)
    }

    func removeAll() {
        file.removeAll()
    }

    /// Nil when there is no file to write (in memory).
    func write(_ data: Data) -> Result<Void, Error>? {
        if isInMemory { return nil }
        return file.write(data)
    }
}
