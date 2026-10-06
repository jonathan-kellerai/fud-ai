//
//  PeptideLogFile.swift
//  calorietracker
//
//  Where the Peptides log is saved and how its bytes are read and written.
//  No decoding here: PeptideLogStore owns what the bytes mean.
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

    /// The saved bytes: the file, else the UserDefaults fallback.
    func read() -> Data? {
        if isInMemory { return nil }
        var data: Data?
        if let url {
            data = try? Data(contentsOf: url)
        }
        if data == nil, let defaults {
            data = defaults.data(forKey: defaultsKey)
        }
        return data
    }

    /// Never overwrite data that could not be read: set it aside first.
    func keepUnreadable(_ data: Data) {
        guard let url else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("peptide_log_v1.unreadable-\(stamp).json")
        try? data.write(to: backup, options: .atomic)
    }

    /// Writes the untouched bytes of an older log next to it before it is
    /// upgraded. True only when the copy is on disk and reads back the same.
    func keepBeforeUpgrade(_ data: Data, now: Date = Date()) -> Bool {
        guard let url else { return false }
        let directory = url.deletingLastPathComponent()
        let copy = directory.appendingPathComponent("peptide_log_v1.pre-local-\(Int(now.timeIntervalSince1970)).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: copy, options: .atomic)
        } catch {
            return false
        }
        return (try? Data(contentsOf: copy)) == data
    }

    /// Writes the file atomically and keeps the UserDefaults copy only while
    /// the file can't be written. Nil when there is no file to write.
    @discardableResult
    func write(_ data: Data) -> Result<Void, Error>? {
        var result: Result<Void, Error>?
        if let url {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }
        if let defaults {
            if case .success = result {
                defaults.removeObject(forKey: defaultsKey)
            } else {
                defaults.set(data, forKey: defaultsKey)
            }
        }
        return result
    }
}
