import Foundation
import Observation

/// The on-device AI request log: a capped JSON file in Application Support.
/// It is never uploaded and stays out of device backups.
@Observable
final class AIRequestLogStore {
    static let maxEntries = 200
    static let maxBytes = 512 * 1024

    static let shared = AIRequestLogStore()

    /// Oldest first, as stored.
    private(set) var entries: [AIRequestLogEntry] = []
    private(set) var lastSaveError: String?

    let fileURL: URL

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ai-request-log.json")
    }

    init(fileURL: URL = AIRequestLogStore.defaultFileURL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    var newestFirst: [AIRequestLogEntry] { entries.reversed() }

    func entry(id: UUID) -> AIRequestLogEntry? {
        entries.first { $0.id == id }
    }

    func append(_ newEntries: [AIRequestLogEntry]) {
        guard !newEntries.isEmpty else { return }
        entries = Self.capped(entries + newEntries)
        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Caps

    /// Drops the oldest entries until there are at most `maxEntries` and the encoded file
    /// is at most `maxBytes`. Input and output are oldest first.
    static func capped(
        _ entries: [AIRequestLogEntry],
        maxEntries: Int = AIRequestLogStore.maxEntries,
        maxBytes: Int = AIRequestLogStore.maxBytes
    ) -> [AIRequestLogEntry] {
        var kept = Array(entries.suffix(max(0, maxEntries)))
        let encoder = makeEncoder()
        var sizes = kept.map { (try? encoder.encode($0).count) ?? 0 }
        // A JSON array is "[" + entries joined by "," + "]".
        var total = 2 + sizes.reduce(0, +) + max(0, sizes.count - 1)
        while !kept.isEmpty, total > maxBytes {
            let dropped = sizes.removeFirst()
            kept.removeFirst()
            total -= dropped + (kept.isEmpty ? 0 : 1)
        }
        return kept
    }

    // MARK: - File

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A missing or unreadable file reads as an empty log; the log is diagnostics, not data.
    private static func load(from url: URL) -> [AIRequestLogEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([AIRequestLogEntry].self, from: data)
        else { return [] }
        return capped(decoded)
    }

    private func save() {
        do {
            let data = try Self.makeEncoder().encode(entries)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            Self.excludeFromBackup(fileURL)
            lastSaveError = nil
        } catch {
            // Keep the in-memory log; the next successful save writes it.
            lastSaveError = error.localizedDescription
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }
}
