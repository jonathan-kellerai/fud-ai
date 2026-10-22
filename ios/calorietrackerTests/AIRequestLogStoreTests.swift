import Foundation
import Testing
@testable import calorietracker

@MainActor
struct AIRequestLogStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-request-log-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ai-request-log.json")
    }

    private func entry(_ index: Int, body: String? = nil, parsed: Bool = true) -> AIRequestLogEntry {
        AIRequestLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)),
            provider: "OpenRouter",
            model: "openai/gpt-5-mini",
            kind: index.isMultiple(of: 2) ? .mealPhoto : .textFood,
            httpStatus: parsed ? 200 : 401,
            latencyMs: 100 + index,
            errorBody: body,
            parsed: parsed
        )
    }

    @Test func roundTripsThroughTheFile() throws {
        let url = tempFile()
        let first = AIRequestLogStore(fileURL: url)
        let written = [entry(1), entry(2, body: #"{"error":"nope"}"#, parsed: false)]
        first.append(written)

        let second = AIRequestLogStore(fileURL: url)
        #expect(second.entries == written)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func listsNewestFirst() {
        let store = AIRequestLogStore(fileURL: tempFile())
        store.append([entry(1), entry(2)])
        store.append([entry(3)])
        #expect(store.newestFirst.map(\.latencyMs) == [103, 102, 101])
        #expect(store.entry(id: store.entries[0].id) == store.entries[0])
    }

    @Test func keepsAtMostTwoHundredEntriesDroppingTheOldest() {
        let store = AIRequestLogStore(fileURL: tempFile())
        store.append((0..<150).map { entry($0) })
        store.append((150..<230).map { entry($0) })
        #expect(store.entries.count == AIRequestLogStore.maxEntries)
        #expect(store.entries.first?.latencyMs == 130)
        #expect(store.entries.last?.latencyMs == 329)
    }

    @Test func keepsTheEncodedFileUnderTheByteCap() throws {
        let body = String(repeating: "e", count: 3_900)
        let entries = (0..<200).map { entry($0, body: body, parsed: false) }
        let capped = AIRequestLogStore.capped(entries)
        let size = try AIRequestLogStore.makeEncoder().encode(capped).count
        #expect(size <= AIRequestLogStore.maxBytes)
        #expect(capped.count < entries.count)
        // Only the oldest are dropped, and dropping one fewer would break the cap.
        #expect(capped == Array(entries.suffix(capped.count)))
        let oneMore = Array(entries.suffix(capped.count + 1))
        #expect(try AIRequestLogStore.makeEncoder().encode(oneMore).count > AIRequestLogStore.maxBytes)
    }

    @Test func byteCapMatchesTheExactEncodedSize() throws {
        let entries = (0..<5).map { entry($0, body: "body \($0)") }
        let exact = try AIRequestLogStore.makeEncoder().encode(entries).count
        #expect(AIRequestLogStore.capped(entries, maxBytes: exact) == entries)
        #expect(AIRequestLogStore.capped(entries, maxBytes: exact - 1) == Array(entries.dropFirst()))
        #expect(AIRequestLogStore.capped(entries, maxBytes: 1).isEmpty)
    }

    @Test func clearEmptiesTheFileToo() {
        let url = tempFile()
        let store = AIRequestLogStore(fileURL: url)
        store.append([entry(1)])
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(AIRequestLogStore(fileURL: url).entries.isEmpty)
    }

    @Test func unreadableFileLoadsAsAnEmptyLog() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = AIRequestLogStore(fileURL: url)
        #expect(store.entries.isEmpty)
        store.append([entry(1)])
        #expect(AIRequestLogStore(fileURL: url).entries.count == 1)
    }

    @Test func reportTextCarriesEveryField() {
        let item = entry(1, body: #"{"error":"bad"}"#, parsed: false)
        let text = item.reportText(timeZone: TimeZone(identifier: "UTC")!)
        #expect(text.contains("Kind: Text food"))
        #expect(text.contains("Provider: OpenRouter"))
        #expect(text.contains("Model: openai/gpt-5-mini"))
        #expect(text.contains("HTTP status: 401"))
        #expect(text.contains("Latency: 101 ms"))
        #expect(text.contains("Parsed: no"))
        #expect(text.contains(#"{"error":"bad"}"#))
        #expect(text.contains("Time: 2026-09-21T"))
    }
}
