//
//  LocalProgramStore.swift
//  calorietracker
//
//  Programs live on this phone (build 73), like workouts and peptides. The
//  store keeps every version in one JSON file and mirrors the active one into
//  ActiveProgramCache, which the rest of the app already reads. No network.
//

import Foundation

enum LocalProgramError: LocalizedError {
    case notFound
    case notDraft

    var errorDescription: String? {
        switch self {
        case .notFound: return "That program isn't on this phone."
        case .notDraft: return "Only drafts can be changed this way."
        }
    }
}

final class LocalProgramStore {
    static let shared = LocalProgramStore()
    static let fileName = "jl-programs.json"
    /// Bumped when the seed program changes; a lower stored value reseeds.
    static let seedVersion = 1
    static let seedVersionKey = "jl.physical.localPrograms.seedVersion"

    private let directory: URL
    private let defaults: UserDefaults
    private let mirrorsActiveProgram: Bool
    private let lock = NSLock()
    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// `directory` and `defaults` are injectable for tests.
    init(directory: URL? = nil, defaults: UserDefaults = .standard, mirrorsActiveProgram: Bool = true) {
        self.directory = directory ?? URL.applicationSupportDirectory
        self.defaults = defaults
        self.mirrorsActiveProgram = mirrorsActiveProgram
    }

    /// Program V3 exactly as approved and activated on the bridge on 10/19.
    static func bundledV3() -> TrainingProgramRecord? {
        guard let url = Bundle.main.url(forResource: "ProgramV3", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeSeed(data)
    }

    static func decodeSeed(_ data: Data) -> TrainingProgramRecord? {
        try? JSONDecoder().decode(TrainingProgramRecord.self, from: data)
    }

    // MARK: Migration

    /// First launch on build 73: any program cached from the bridge is replaced
    /// by the bundled V3, which becomes the only active program. Workouts and
    /// the in-progress draft live in their own stores and are not touched.
    @discardableResult
    func seedIfNeeded(seed: TrainingProgramRecord? = LocalProgramStore.bundledV3()) -> [TrainingProgramRecord] {
        lock.lock(); defer { lock.unlock() }
        var records = loadRecords()
        guard defaults.integer(forKey: Self.seedVersionKey) < Self.seedVersion, let seed else { return records }
        records = records.map { record in
            var copy = record
            if copy.status == .active { copy.status = .archived }
            return copy
        }
        var active = seed
        active.status = .active
        records.removeAll { $0.id == active.id }
        records.append(active)
        writeRecords(records)
        defaults.set(Self.seedVersion, forKey: Self.seedVersionKey)
        mirror(records)
        return records
    }

    // MARK: Same surface the editor used on the bridge

    func listPrograms(status: String? = nil, lineageID: String? = nil) async throws -> [TrainingProgramRecord] {
        #if DEBUG
        if let pinned = Self.visualQAOverride { return [pinned] }
        #endif
        return seedIfNeeded().filter { record in
            (status.map { record.status.rawValue == $0 } ?? true)
                && (lineageID.map { record.lineageId == $0 } ?? true)
        }
    }

    func activeProgram() async throws -> TrainingProgramRecord {
        guard let record = activeProgramNow() else { throw LocalProgramError.notFound }
        return record
    }

    #if DEBUG
    /// Visual QA pins the program its screenshots were written against.
    nonisolated(unsafe) static var visualQAOverride: TrainingProgramRecord?
    #endif

    /// Synchronous read for views that load on appear.
    func activeProgramNow() -> TrainingProgramRecord? {
        #if DEBUG
        if let pinned = Self.visualQAOverride { return pinned }
        #endif
        return seedIfNeeded().last { $0.status == .active && $0.body != nil }
    }

    func program(id: String) async throws -> TrainingProgramRecord {
        #if DEBUG
        if let pinned = Self.visualQAOverride, pinned.id == id { return pinned }
        #endif
        guard let record = seedIfNeeded().first(where: { $0.id == id }) else { throw LocalProgramError.notFound }
        return record
    }

    func createProgram(name: String, body: TrainingProgramBody, parentID: String? = nil,
                       changeReason: String? = nil) async throws -> TrainingProgramRecord {
        let id = UUID().uuidString.lowercased()
        let parent = parentID.flatMap { pid in seedIfNeeded().first { $0.id == pid } }
        let record = TrainingProgramRecord(
            id: id, lineageId: parent?.lineageId ?? id, version: (parent?.version ?? 0) + 1,
            name: name, status: .draft, parentId: parentID, createdAt: Self.timestamp(),
            activatedAt: nil, createdBy: "app", changeReason: changeReason, body: body.normalizedForSave())
        try mutate { $0.append(record) }
        return record
    }

    func updateDraft(id: String, name: String, body: TrainingProgramBody,
                     changeReason: String? = nil) async throws -> TrainingProgramRecord {
        var updated: TrainingProgramRecord?
        try mutate { records in
            guard let index = records.firstIndex(where: { $0.id == id }) else { throw LocalProgramError.notFound }
            guard records[index].status == .draft else { throw LocalProgramError.notDraft }
            records[index].name = name
            records[index].body = body.normalizedForSave()
            if let changeReason { records[index].changeReason = changeReason }
            updated = records[index]
        }
        return updated!
    }

    func reviseProgram(id: String, name: String, body: TrainingProgramBody,
                       changeReason: String, activate: Bool) async throws -> TrainingProgramRecord {
        let revision = try await createProgram(name: name, body: body, parentID: id, changeReason: changeReason)
        if activate { try await activateProgram(id: revision.id) }
        return try await program(id: revision.id)
    }

    /// Activates immediately and archives the previous active program.
    func activateProgram(id: String) async throws {
        try mutate { records in
            guard records.contains(where: { $0.id == id }) else { throw LocalProgramError.notFound }
            for index in records.indices {
                if records[index].id == id {
                    records[index].status = .active
                    records[index].activatedAt = Self.timestamp()
                } else if records[index].status == .active {
                    records[index].status = .archived
                }
            }
        }
    }

    func deleteDraft(id: String) async throws {
        try mutate { records in
            guard let index = records.firstIndex(where: { $0.id == id }) else { throw LocalProgramError.notFound }
            guard records[index].status == .draft else { throw LocalProgramError.notDraft }
            records.remove(at: index)
        }
    }

    // MARK: Storage

    private func mutate(_ change: (inout [TrainingProgramRecord]) throws -> Void) throws {
        _ = seedIfNeeded()
        lock.lock(); defer { lock.unlock() }
        var records = loadRecords()
        try change(&records)
        writeRecords(records)
        mirror(records)
    }

    private func mirror(_ records: [TrainingProgramRecord]) {
        guard mirrorsActiveProgram else { return }
        if let active = records.last(where: { $0.status == .active && $0.body != nil }) {
            ActiveProgramCache.save(active)
        }
    }

    private func loadRecords() -> [TrainingProgramRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([TrainingProgramRecord].self, from: data)) ?? []
    }

    private func writeRecords(_ records: [TrainingProgramRecord]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save programs: \(error)")
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
