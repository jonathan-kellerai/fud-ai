//
//  DeviceLogFile.swift
//  calorietracker
//
//  How an on-device log's bytes are read, written and set aside: one JSON
//  file written atomically, with an optional UserDefaults fallback. No
//  decoding here; each log's store owns what its bytes mean.
//

import Foundation

/// What reading a log file found.
enum DeviceLogRead {
    /// No file yet.
    case missing
    case data(Data)
    /// The file is there but couldn't be read; its bytes are unknown.
    case failed(Error)
}

struct DeviceLogFile {
    /// The log file. Nil when there is no file (in memory, or no app group).
    let url: URL?
    /// Holds the bytes only while the file can't be written. Nil: no fallback.
    let defaults: UserDefaults?
    let defaultsKey: String

    /// The file alone, saying whether it is missing or there but unreadable
    /// (locked by file protection, no permission). No UserDefaults fallback.
    func readFile() -> DeviceLogRead {
        guard let url else { return .missing }
        do {
            return .data(try Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            // No file at the path (nothing there, a folder in its place, or a plain
            // file where a folder should be) is no file, not an unreadable one;
            // a locked file is still there, so it stays `.failed`.
            var isFolder: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) || isFolder.boolValue {
                return .missing
            }
            return .failed(error)
        }
    }

    /// Never overwrite data that could not be read: set it aside first.
    /// True only when the copy is on disk and reads back the same.
    @discardableResult
    func keepUnreadable(_ data: Data, now: Date = Date()) -> Bool {
        guard let copy = copyURL(label: "unreadable", now: now) else { return false }
        do {
            try data.write(to: copy, options: .atomic)
        } catch {
            return false
        }
        return (try? Data(contentsOf: copy)) == data
    }

    /// Writes untouched bytes next to the log as `<stem>.<label>-<stamp>.json`
    /// before they are changed. True only when the copy is on disk and reads back the same.
    func keepCopy(_ data: Data, label: String, now: Date = Date()) -> Bool {
        guard let copy = copyURL(label: label, now: now) else { return false }
        do {
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: copy, options: .atomic)
        } catch {
            return false
        }
        return (try? Data(contentsOf: copy)) == data
    }

    /// Delete Everything: the log, every copy set aside next to it, and the
    /// UserDefaults fallback.
    func removeAll() {
        defaults?.removeObject(forKey: defaultsKey)
        guard let url else { return }
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(stem) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Writes the file atomically and keeps the UserDefaults copy only while
    /// the file can't be written. With `fallbackOnFailure` false (a restore),
    /// a failed file write leaves the UserDefaults copy as it was, so nothing
    /// saved changes. Nil when there is no file to write.
    @discardableResult
    func write(_ data: Data, fallbackOnFailure: Bool = true) -> Result<Void, Error>? {
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
        if case .failure = result, !fallbackOnFailure { return result }
        if let defaults {
            if case .success = result {
                defaults.removeObject(forKey: defaultsKey)
            } else {
                defaults.set(data, forKey: defaultsKey)
            }
        }
        return result
    }

    private func copyURL(label: String, now: Date) -> URL? {
        guard let url else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent("\(stem).\(label)-\(Int(now.timeIntervalSince1970)).json")
    }
}
