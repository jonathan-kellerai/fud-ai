import Foundation
import Testing
@testable import calorietracker

/// A saved peptide log this app can't open or can't read in full is never
/// written over: the store refuses changes until the file opens or its bytes
/// are kept aside. Real files in a temp directory, a throwaway UserDefaults
/// suite, synthetic data only.
@MainActor
struct PeptideUnreadableLogTests {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func draft(compound: String = "BPC-157") -> PeptideLogDraft {
        var draft = PeptideLogDraft.new(compound: compound, now: takenAt)
        draft.drawText = "50"
        draft.drawUnit = .units
        return draft
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peptide-unreadable-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("peptide_log_v1.json")
    }

    private func cleanUp(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func files(beside url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []).sorted()
    }

    // MARK: Reading the file

    private func isMissing(_ url: URL) -> Bool {
        if case .missing = DeviceLogFile(url: url, defaults: nil, defaultsKey: "unused").readFile() { return true }
        return false
    }

    @Test func noFileAtThePathReadsAsMissingAndALockedFileDoesNot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("device-log-\(UUID().uuidString)")
        defer { cleanUp(directory.appendingPathComponent("locked.json")) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A plain file where a folder should be.
        let blocker = directory.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        #expect(isMissing(blocker.appendingPathComponent("log.json")))
        // A folder where the file should be.
        let folder = directory.appendingPathComponent("folder.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(isMissing(folder))
        // A file that is there but can't be read.
        let locked = directory.appendingPathComponent("locked.json")
        try Data("{}".utf8).write(to: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        guard case .failed = DeviceLogFile(url: locked, defaults: nil, defaultsKey: "unused").readFile() else {
            Issue.record("A locked file should read as failed")
            return
        }
    }
}
