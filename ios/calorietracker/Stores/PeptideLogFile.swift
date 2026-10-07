//
//  PeptideLogFile.swift
//  calorietracker
//
//  Where the Peptides log is saved. DeviceLogFile reads and writes the bytes;
//  PeptideLogStore owns what they mean.
//

import Foundation

enum PeptideLogPersistence {
    /// App group `Library/Application Support/PeptideLog/peptide_log_v1.json`, UserDefaults fallback.
    case appGroup
    /// Nothing is written (tests, Visual QA).
    case inMemory
    /// A file, with an optional UserDefaults fallback (tests).
    case file(URL, defaults: UserDefaults? = nil)
}

struct PeptideLogFile {
    let persistence: PeptideLogPersistence
    let defaultsKey: String

    var isInMemory: Bool {
        if case .inMemory = persistence { return true }
        return false
    }

    var url: URL? {
        switch persistence {
        case .inMemory:
            return nil
        case .file(let url, _):
            return url
        case .appGroup:
            guard let directory = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)?
                .appendingPathComponent("Library/Application Support/PeptideLog", isDirectory: true) else { return nil }
            return directory.appendingPathComponent("peptide_log_v1.json")
        }
    }

    private var defaults: UserDefaults? {
        switch persistence {
        case .appGroup: return .standard
        case .inMemory: return nil
        case .file(_, let defaults): return defaults
        }
    }

    private var file: DeviceLogFile {
        DeviceLogFile(url: url, defaults: defaults, defaultsKey: defaultsKey)
    }

    /// The saved bytes: the file, else the UserDefaults fallback.
    func read() -> Data? {
        if isInMemory { return nil }
        return file.read()
    }

    /// Never overwrite data that could not be read: set it aside first.
    func keepUnreadable(_ data: Data) {
        file.keepUnreadable(data)
    }

    /// Writes the untouched bytes of an older log next to it before it is
    /// upgraded. True only when the copy is on disk and reads back the same.
    func keepBeforeUpgrade(_ data: Data, now: Date = Date()) -> Bool {
        file.keepCopy(data, label: "pre-local", now: now)
    }

    /// Delete Everything: the log, every copy set aside next to it, and the
    /// UserDefaults fallback.
    func removeAll() {
        file.removeAll()
    }

    /// Writes the file atomically and keeps the UserDefaults copy only while
    /// the file can't be written. With `fallbackOnFailure` false (a restore),
    /// a failed file write leaves the UserDefaults copy as it was, so nothing
    /// saved changes. Nil when there is no file to write.
    @discardableResult
    func write(_ data: Data, fallbackOnFailure: Bool = true) -> Result<Void, Error>? {
        file.write(data, fallbackOnFailure: fallbackOnFailure)
    }
}
