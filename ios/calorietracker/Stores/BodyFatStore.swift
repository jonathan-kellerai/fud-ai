import Foundation
import SwiftUI

/// Local-only store for body-fat history. Mirrors WeightStore but trimmer:
///   - no HealthKit sync (no body-fat callbacks wired into calorietrackerApp)
///   - no goal-crossing notification yet (goalBodyFatPercentage exists but
///     the celebration UX hasn't been requested — easy to add later)
///   - the latest entry's value is treated as the user's "current" body fat
///     and pushed to UserProfile.bodyFatPercentage on every add, so Katch-McArdle
///     BMR/TDEE re-evaluates every time the user logs a new reading
@Observable
class BodyFatStore {
    private(set) var entries: [BodyFatEntry] = []
    /// Wired in calorietrackerApp.swift → HealthKitManager.writeBodyFat(for:)
    /// when HealthKit sync is enabled. Mirrors WeightStore.onEntryAdded.
    var onEntryAdded: ((BodyFatEntry) -> Void)?
    /// Wired to HealthKitManager.deleteBodyFat(entryID:) so per-entry deletes
    /// also pull the matching HK sample (matched by fudai_bodyfat_id metadata).
    var onEntryDeleted: ((UUID) -> Void)?

    static let externalChangeNotification = "ai.fud.bodyFatEntriesDidChange"
    private let storageKey = "bodyFatEntries"
    private let observesExternalChanges: Bool

    init(observesExternalChanges: Bool = true) {
        self.observesExternalChanges = observesExternalChanges
        loadEntries()
        if observesExternalChanges {
            startObservingExternalChanges()
        }
    }

    deinit {
        guard observesExternalChanges else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            CFNotificationName(Self.externalChangeNotification as CFString),
            nil
        )
    }

    /// Seed the first entry from the user's onboarding-set body fat. Called
    /// once from calorietrackerApp once onboarding completes — idempotent
    /// (no-op if any entry already exists, so re-onboarding can't duplicate).
    func seedInitialBodyFatFromProfileIfEmpty(_ fraction: Double) {
        guard entries.isEmpty else { return }
        addEntry(BodyFatEntry(date: .now, bodyFatFraction: fraction))
    }

    var latestEntry: BodyFatEntry? {
        entries.sorted { $0.date > $1.date }.first
    }

    func entries(in range: ClosedRange<Date>) -> [BodyFatEntry] {
        entries
            .filter { range.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    func addEntry(_ entry: BodyFatEntry) {
        entries.append(entry)
        saveEntries()
        onEntryAdded?(entry)
        syncProfileBodyFatToLatest()
    }

    func deleteEntry(_ entry: BodyFatEntry) {
        let id = entry.id
        entries.removeAll { $0.id == id }
        saveEntries()
        onEntryDeleted?(id)
        syncProfileBodyFatToLatest()
    }

    /// Keep UserProfile.bodyFatPercentage aligned with the latest reading so
    /// Katch-McArdle BMR + Settings → Profile → Body Fat row never drift apart.
    /// If the store is empty after a delete, leave the profile value alone —
    /// silently dropping someone's BMR formula because they cleared one row
    /// would surprise them; they can clear it explicitly via Settings.
    private func syncProfileBodyFatToLatest() {
        guard var profile = UserProfile.load(),
              let newest = entries.sorted(by: { $0.date > $1.date }).first else { return }
        if abs((profile.bodyFatPercentage ?? -1) - newest.bodyFatFraction) > 0.0001 {
            profile.bodyFatPercentage = newest.bodyFatFraction
            profile.save()
        }
    }

    func reloadFromDefaults() {
        loadEntries()
    }

    func replaceAllEntries(_ newEntries: [BodyFatEntry]) {
        entries = newEntries
        saveEntries()
    }

    /// Bulk-import body-fat samples discovered from HealthKit. Bypasses
    /// onEntryAdded so the imports don't echo back to HealthKit. Dedupes by
    /// entry id and HealthKit sample UUID.
    func importExternalEntries(_ external: [BodyFatEntry]) {
        var seenIDs = Set(entries.map(\.id))
        var seenHealthUUIDs = Set(entries.compactMap(\.healthKitSampleUUID))
        let fresh = external.filter { entry in
            if let sampleUUID = entry.healthKitSampleUUID,
               seenHealthUUIDs.contains(sampleUUID) || seenIDs.contains(sampleUUID) {
                return false
            }
            guard seenIDs.insert(entry.id).inserted else { return false }
            if let sampleUUID = entry.healthKitSampleUUID {
                seenHealthUUIDs.insert(sampleUUID)
            }
            return true
        }
        guard !fresh.isEmpty else { return }
        entries.append(contentsOf: fresh)
        saveEntries()
        syncProfileBodyFatToLatest()
        Self.postExternalChangeNotification()
    }

    static func postExternalChangeNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(externalChangeNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private func startObservingExternalChanges() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let store = Unmanaged<BodyFatStore>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    store.reloadFromDefaults()
                }
            },
            Self.externalChangeNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BodyFatEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
