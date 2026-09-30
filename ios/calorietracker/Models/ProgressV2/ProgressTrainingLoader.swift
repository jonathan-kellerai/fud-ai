import Foundation

enum ProgressTrainingLoadState: Equatable {
    case idle
    case loading
    case notConfigured
    case failed(String)
    case loaded(ProgressTrainingSummary)
}

/// Loads the Training card from the Neon bridge: GET /api/workouts for the
/// session list, then GET /api/workouts/{id} for the sets of the most recent
/// completed sessions in range. The list is cached for a few minutes and
/// per-workout sets for the app session; Retry / pull to refresh bypasses
/// both, because a saved workout can be edited in Workout History.
enum ProgressTrainingLoader {
    private static let freshness: TimeInterval = 5 * 60
    private static var workoutCache: [String: (fetchedAt: Date, workouts: [ProgressBridgeWorkout])] = [:]
    private static var detailCache = ProgressWorkoutDetailCache()

    static func currentConfig() -> ProgressBridgeConfig {
        let settings = NeonBridgeService.shared.settings
        return ProgressBridgeConfig(baseURL: settings.baseURL, apiKey: settings.apiKey)
    }

    /// Range start and today are both Eastern day keys from one calendar,
    /// matching how sessions are bucketed.
    static func load(
        range: TimeRange,
        forceRefresh: Bool,
        now: Date = .now
    ) async -> ProgressTrainingLoadState {
        let config = currentConfig()
        guard config.isConfigured else { return .notConfigured }

        let workouts: [ProgressBridgeWorkout]
        if !forceRefresh,
           let cached = workoutCache[config.baseURL],
           now.timeIntervalSince(cached.fetchedAt) < freshness {
            workouts = cached.workouts
        } else {
            do {
                workouts = try await ProgressTrainingAPI.fetchWorkouts(config: config)
                workoutCache[config.baseURL] = (now, workouts)
            } catch {
                return .failed(message(for: error))
            }
        }

        let oldestWorkout = workouts
            .filter(ProgressTrainingMath.isCompleted)
            .compactMap { ProgressTrainingMath.dayKey(for: $0) }
            .min()
        let (startKey, todayKey) = ProgressTrainingMath.rangeDayKeys(for: range, now: now, oldestWorkoutDay: oldestWorkout)

        let wanted = ProgressTrainingMath.detailWorkoutIDs(workouts: workouts, startDayKey: startKey, todayKey: todayKey)
        if forceRefresh {
            // Drop every cached set total for this bridge so edited workouts
            // (in this range or another) are fetched again.
            detailCache.invalidate(baseURL: config.baseURL)
        }
        let cached = detailCache.lookup(ids: wanted, baseURL: config.baseURL)
        var details = cached.found
        let missing = cached.missing

        let fetched = await fetchTotals(ids: missing, config: config)
        guard !Task.isCancelled else { return .loading }
        var failed = 0
        for (id, totals) in fetched {
            if let totals {
                details[id] = totals
                detailCache.store(totals, id: id, baseURL: config.baseURL)
            } else {
                failed += 1
            }
        }
        // Ids never started because the task was cancelled are neither loaded nor failed.
        failed += max(0, missing.count - fetched.count)

        return .loaded(ProgressTrainingMath.summary(
            workouts: workouts,
            details: details,
            startDayKey: startKey,
            todayKey: todayKey,
            failedDetails: failed
        ))
    }

    /// GET /api/workouts/{id} for each id, at most `maxConcurrentRequests` at a time.
    private static func fetchTotals(ids: [String], config: ProgressBridgeConfig) async -> [(String, ProgressWorkoutTotals?)] {
        guard !ids.isEmpty else { return [] }
        return await withTaskGroup(of: (String, ProgressWorkoutTotals?).self) { group -> [(String, ProgressWorkoutTotals?)] in
            var pending = ids.makeIterator()
            for _ in 0..<ProgressTrainingMath.maxConcurrentRequests {
                guard let id = pending.next() else { break }
                group.addTask {
                    (id, try? await ProgressTrainingAPI.fetchWorkoutTotals(config: config, id: id))
                }
            }
            var collected: [(String, ProgressWorkoutTotals?)] = []
            while let row = await group.next() {
                collected.append(row)
                if !Task.isCancelled, let id = pending.next() {
                    group.addTask {
                        (id, try? await ProgressTrainingAPI.fetchWorkoutTotals(config: config, id: id))
                    }
                }
            }
            return collected
        }
    }

    static func message(for error: Error) -> String {
        switch error as? ProgressTrainingError {
        case .notConfigured:
            return String(localized: "The Neon bridge is not set up.")
        case .offline:
            return String(localized: "Couldn't reach the Neon bridge. Check your connection.")
        case .http(let status) where status == 401 || status == 403:
            return String(localized: "The Neon bridge rejected the API key (HTTP \(status)).")
        case .http(let status):
            return String(localized: "The Neon bridge returned an error (HTTP \(status)).")
        case .badResponse:
            return String(localized: "The Neon bridge sent a response Progress could not read.")
        case .transport, .none:
            return String(localized: "Couldn't reach the Neon bridge.")
        }
    }
}
