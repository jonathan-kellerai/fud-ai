import Foundation
import Observation

enum JevDecisionSource: String, Codable, Sendable {
    case network, cache, local, skipped
}

struct JevDecisionRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var date: Date
    var use: JevUse
    var preview: String
    var result: String
    var confidence: Double?
    var latencyMs: Int?
    var source: JevDecisionSource
    var reason: String?
    var resolvedModel: String?
}

enum JevFallback: String, Codable, CaseIterable, Sendable {
    case lowConfidence, none, noCandidates, guardRejected, skipped, validationFailed, parseFailed
}

struct JevUseStats: Codable, Equatable, Sendable {
    var requests = 0
    var cacheHits = 0
    var localShortcuts = 0
    var accepted = 0
    var userOverrides = 0
    var llmCallsAvoided = 0
    var inputTokens = 0
    var fallbacks: [String: Int] = [:]
    var skipped: [String: Int] = [:]
    var latencyBuckets: [Int] = [0, 0, 0, 0, 0, 0]
}

struct JevRouterStatsSnapshot: Codable, Equatable, Sendable {
    var since: Date
    var uses: [String: JevUseStats] = [:]
}

@MainActor
@Observable
final class JevRouterTelemetry {
    static let shared = JevRouterTelemetry()

    private(set) var snapshot: JevRouterStatsSnapshot
    private(set) var decisions: [JevDecisionRecord] = []
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastWrite: Date?
    private var pendingWrite: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: JevRouterSettings.statsKey),
           let stored = try? JSONDecoder().decode(JevRouterStatsSnapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = JevRouterStatsSnapshot(since: now())
        }
    }

    func recordNetwork(use: JevUse, latencyMs: Int, inputTokens: Int) {
        var stats = stats(for: use)
        stats.requests += 1
        stats.inputTokens += inputTokens
        stats.latencyBuckets[bucket(for: latencyMs)] += 1
        snapshot.uses[use.rawValue] = stats
        scheduleWrite()
    }

    func recordCacheHit(use: JevUse) {
        var stats = stats(for: use)
        stats.cacheHits += 1
        snapshot.uses[use.rawValue] = stats
        scheduleWrite()
    }

    func recordSkip(use: JevUse, reason: JevSkipReason) {
        var stats = stats(for: use)
        stats.skipped[reason.rawValue, default: 0] += 1
        snapshot.uses[use.rawValue] = stats
        scheduleWrite()
    }

    func record(_ use: JevUse, _ decision: JevDecision, preview: String, latencyMs: Int?, model: String?) {
        switch decision {
        case .accepted(_, let confidence, let avoided):
            var stats = stats(for: use)
            stats.accepted += 1
            stats.llmCallsAvoided += avoided
            snapshot.uses[use.rawValue] = stats
            append(use: use, preview: preview, result: "accepted", confidence: confidence, latencyMs: latencyMs, source: .network, model: model)
        case .localShortcut(let label, let avoided):
            var stats = stats(for: use)
            stats.localShortcuts += 1
            stats.llmCallsAvoided += avoided
            snapshot.uses[use.rawValue] = stats
            append(use: use, preview: preview, result: label, confidence: nil, latencyMs: nil, source: .local, model: nil)
        case .fellBack(let fallback):
            var stats = stats(for: use)
            stats.fallbacks[fallback.rawValue, default: 0] += 1
            snapshot.uses[use.rawValue] = stats
            append(use: use, preview: preview, result: "fallback", confidence: nil, latencyMs: latencyMs, source: .skipped, reason: fallback.rawValue, model: model)
        case .userOverride:
            var stats = stats(for: use)
            stats.userOverrides += 1
            snapshot.uses[use.rawValue] = stats
            append(use: use, preview: preview, result: "override", confidence: nil, latencyMs: nil, source: .local, model: nil)
        case .loggedAfterMatch:
            append(use: use, preview: preview, result: "logged after match", confidence: nil, latencyMs: nil, source: .local, model: nil)
        }
        scheduleWrite()
    }

    func reset() {
        snapshot = JevRouterStatsSnapshot(since: now())
        decisions = []
        pendingWrite?.cancel()
        defaults.removeObject(forKey: JevRouterSettings.statsKey)
        lastWrite = nil
    }

    func flush() {
        pendingWrite?.cancel()
        writeNow()
    }

    var netCallsAvoided: Int {
        snapshot.uses.values.reduce(0) { $0 + $1.llmCallsAvoided - $1.userOverrides }
    }

    var totalInputTokens: Int {
        snapshot.uses.values.reduce(0) { $0 + $1.inputTokens }
    }

    var estimatedSpend: Double {
        Double(totalInputTokens) * 0.042 / 1_000_000
    }

    func percentile(_ p: Double) -> Int? {
        let bounds = [100, 200, 400, 800, 1600, 3200]
        let buckets = JevUse.allCases.reduce(into: Array(repeating: 0, count: 6)) { total, use in
            let stats = snapshot.uses[use.rawValue]?.latencyBuckets ?? []
            for index in 0..<min(6, stats.count) { total[index] += stats[index] }
        }
        let total = buckets.reduce(0, +)
        guard total > 0 else { return nil }
        let target = Int((Double(total) * p).rounded(.up))
        var running = 0
        for index in buckets.indices {
            running += buckets[index]
            if running >= target { return bounds[index] }
        }
        return bounds.last
    }

    private func stats(for use: JevUse) -> JevUseStats {
        snapshot.uses[use.rawValue] ?? JevUseStats()
    }

    private func bucket(for latencyMs: Int) -> Int {
        switch latencyMs {
        case ...100: 0
        case ...200: 1
        case ...400: 2
        case ...800: 3
        case ...1600: 4
        default: 5
        }
    }

    private func append(
        use: JevUse,
        preview: String,
        result: String,
        confidence: Double?,
        latencyMs: Int?,
        source: JevDecisionSource,
        reason: String? = nil,
        model: String?
    ) {
        let clipped = String(preview.prefix(40))
        decisions.append(JevDecisionRecord(
            id: UUID(),
            date: now(),
            use: use,
            preview: clipped,
            result: result,
            confidence: confidence,
            latencyMs: latencyMs,
            source: source,
            reason: reason,
            resolvedModel: model
        ))
        if decisions.count > 50 {
            decisions.removeFirst(decisions.count - 50)
        }
    }

    private func scheduleWrite() {
        let current = now()
        if let lastWrite, current.timeIntervalSince(lastWrite) < 5 {
            pendingWrite?.cancel()
            pendingWrite = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.writeNow()
            }
            return
        }
        writeNow()
    }

    private func writeNow() {
        lastWrite = now()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: JevRouterSettings.statsKey)
    }
}
