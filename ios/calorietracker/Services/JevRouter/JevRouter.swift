import Foundation
import os

struct JevCallPolicy: Sendable {
    var budget: Duration
    var retryDelaysNs: [UInt64]
    var cacheTTL: TimeInterval

    var budgetSeconds: TimeInterval {
        let components = budget.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    static func standard(for use: JevUse) -> JevCallPolicy {
        switch use {
        case .mealMatch:
            JevCallPolicy(budget: .milliseconds(800), retryDelaysNs: [], cacheTTL: 24 * 60 * 60)
        case .tierRouting:
            JevCallPolicy(budget: .milliseconds(500), retryDelaysNs: [], cacheTTL: 60 * 60)
        case .coachIntent:
            JevCallPolicy(budget: .milliseconds(700), retryDelaysNs: [], cacheTTL: 60 * 60)
        case .exerciseMatch:
            JevCallPolicy(budget: .milliseconds(800), retryDelaysNs: [], cacheTTL: 24 * 60 * 60)
        case .plausibility:
            JevCallPolicy(budget: .milliseconds(600), retryDelaysNs: [], cacheTTL: 60 * 60)
        case .estimateCheck:
            JevCallPolicy(budget: .seconds(10), retryDelaysNs: [500_000_000], cacheTTL: 60 * 60)
        }
    }
}

enum JevSkipReason: String, Codable, Sendable {
    case killSwitch, noKey, useDisabled, circuitOpen, busy, timeout, keyRejected, rateLimited
    case overloaded, network, invalidRequest, invalidResponse, server, cancelled
}

enum JevOutcome: Sendable {
    case answered(TypeSafeResponse, fromCache: Bool, latencyMs: Int)
    case skipped(JevSkipReason)
}

enum JevDecision: Sendable {
    case accepted(label: String, confidence: Double?, llmCallsAvoided: Int)
    case localShortcut(label: String, llmCallsAvoided: Int)
    case fellBack(JevFallback)
    case userOverride
    /// Precision proxy: the user logged a meal that was filled from a saved match.
    case loggedAfterMatch
}

private struct JevBudgetExceeded: Error {}

actor JevRouter {
    static let shared = JevRouter()

    private let credentials: @Sendable () -> JevCredentials?
    private let isActive: @Sendable (JevUse) -> Bool
    private let killSwitch: @Sendable () -> Bool
    private let session: URLSession
    private let cache: JevDecisionCache
    nonisolated(unsafe) private let telemetry: JevRouterTelemetry
    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "calorietracker", category: "JevRouter")

    private var inFlight = 0
    private var transientFailures = 0
    private var circuitOpenUntil: Date?
    private var circuitReason: JevSkipReason?
    private var rejectedFingerprint: String?

    init(
        credentials: @escaping @Sendable () -> JevCredentials? = { JevCredentials.current },
        isActive: @escaping @Sendable (JevUse) -> Bool = { JevRouterSettings.isActive($0) },
        killSwitch: @escaping @Sendable () -> Bool = { JevRouterSettings.killSwitch },
        session: URLSession = .shared,
        cache: JevDecisionCache = JevDecisionCache(capacity: 256),
        telemetry: JevRouterTelemetry = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.isActive = isActive
        self.killSwitch = killSwitch
        self.session = session
        self.cache = cache
        self.telemetry = telemetry
        self.now = now
    }

    func ask(
        _ use: JevUse,
        cacheKey: String?,
        preview: String,
        policy: JevCallPolicy? = nil,
        build: @Sendable (String) -> TypeSafeRequest
    ) async -> JevOutcome {
        if killSwitch() {
            await noteSkip(use, .killSwitch, preview: preview)
            return .skipped(.killSwitch)
        }
        guard let creds = credentials() else {
            await noteSkip(use, .noKey, preview: preview)
            return .skipped(.noKey)
        }
        guard isActive(use) else {
            await noteSkip(use, .useDisabled, preview: preview)
            return .skipped(.useDisabled)
        }

        let fingerprint = credentialFingerprint(creds)
        if rejectedFingerprint != nil, rejectedFingerprint != fingerprint {
            rejectedFingerprint = nil
            circuitOpenUntil = nil
            circuitReason = nil
        }
        let clock = now()
        if let openUntil = circuitOpenUntil, openUntil > clock {
            await noteSkip(use, .circuitOpen, preview: preview)
            return .skipped(.circuitOpen)
        }
        if circuitOpenUntil != nil {
            circuitOpenUntil = nil
            circuitReason = nil
            transientFailures = 0
        }

        let resolvedPolicy = policy ?? JevCallPolicy.standard(for: use)
        let storageKey = cacheStorageKey(use: use, credentials: creds, cacheKey: cacheKey)
        if let storageKey, let cached = cache.value(for: storageKey, now: clock) {
            await recordCacheHit(use)
            log.debug("use=\(use.rawValue, privacy: .public) cache hit")
            return .answered(cached, fromCache: true, latencyMs: 0)
        }

        if inFlight >= 2 {
            await noteSkip(use, .busy, preview: preview)
            return .skipped(.busy)
        }
        inFlight += 1
        defer { inFlight -= 1 }

        let client = TypeSafeClient(
            baseURL: creds.endpoint.baseURL,
            apiKey: creds.apiKey,
            session: session,
            timeout: resolvedPolicy.budgetSeconds + 0.25,
            retryDelaysNs: resolvedPolicy.retryDelaysNs
        )
        let started = clock
        let request = build(creds.model)
        do {
            let response = try await race(client: client, request: request, budget: resolvedPolicy.budget)
            let latency = max(0, Int(now().timeIntervalSince(started) * 1000))
            transientFailures = 0
            if let storageKey {
                cache.store(response, for: storageKey, ttl: resolvedPolicy.cacheTTL, now: now())
            }
            await recordNetwork(use, latencyMs: latency, tokens: response.usage?.inputTokens ?? 0)
            log.debug("use=\(use.rawValue, privacy: .public) answered latencyMs=\(latency, privacy: .public)")
            return .answered(response, fromCache: false, latencyMs: latency)
        } catch is JevBudgetExceeded {
            noteTransient(.timeout)
            await noteSkip(use, .timeout, preview: preview)
            return .skipped(.timeout)
        } catch is CancellationError {
            await noteSkip(use, .cancelled, preview: preview)
            return .skipped(.cancelled)
        } catch let error as TypeSafeError {
            let reason = map(error)
            noteFailure(reason, credentials: creds)
            await noteSkip(use, reason, preview: preview)
            return .skipped(reason)
        } catch {
            noteTransient(.network)
            await noteSkip(use, .network, preview: preview)
            return .skipped(.network)
        }
    }

    func report(_ use: JevUse, _ decision: JevDecision, preview: String = "", latencyMs: Int? = nil, model: String? = nil) async {
        let telemetry = telemetry
        await MainActor.run {
            telemetry.record(use, decision, preview: preview, latencyMs: latencyMs, model: model)
        }
    }

    private func recordNetwork(_ use: JevUse, latencyMs: Int, tokens: Int) async {
        let telemetry = telemetry
        await MainActor.run {
            telemetry.recordNetwork(use: use, latencyMs: latencyMs, inputTokens: tokens)
        }
    }

    private func recordCacheHit(_ use: JevUse) async {
        let telemetry = telemetry
        await MainActor.run { telemetry.recordCacheHit(use: use) }
    }

    private func recordSkip(_ use: JevUse, _ reason: JevSkipReason) async {
        let telemetry = telemetry
        await MainActor.run { telemetry.recordSkip(use: use, reason: reason) }
    }

    func reset() async {
        cache.removeAll()
        inFlight = 0
        transientFailures = 0
        circuitOpenUntil = nil
        circuitReason = nil
        rejectedFingerprint = nil
        let telemetry = telemetry
        await MainActor.run { telemetry.reset() }
    }

    private func race(client: TypeSafeClient, request: TypeSafeRequest, budget: Duration) async throws -> TypeSafeResponse {
        try await withThrowingTaskGroup(of: TypeSafeResponse.self) { group in
            group.addTask { try await client.systemOne(request) }
            group.addTask {
                try await Task.sleep(for: budget)
                throw JevBudgetExceeded()
            }
            guard let first = try await group.next() else { throw JevBudgetExceeded() }
            group.cancelAll()
            return first
        }
    }

    private func cacheStorageKey(use: JevUse, credentials: JevCredentials, cacheKey: String?) -> String? {
        guard let cacheKey, !cacheKey.isEmpty else { return nil }
        let raw = "\(use.rawValue)|\(credentials.endpoint.rawValue)|\(credentials.model)|\(cacheKey)"
        return JevText.sha256(raw)
    }

    private func credentialFingerprint(_ credentials: JevCredentials) -> String {
        JevText.sha256("\(credentials.endpoint.rawValue)|\(credentials.model)|\(credentials.apiKey)")
    }

    private func map(_ error: TypeSafeError) -> JevSkipReason {
        switch error {
        case .missingKey, .keyRejected: .keyRejected
        case .invalidRequest: .invalidRequest
        case .rateLimited: .rateLimited
        case .overloaded: .overloaded
        case .server: .server
        case .network: .network
        case .timeout: .timeout
        case .invalidResponse: .invalidResponse
        }
    }

    private func noteFailure(_ reason: JevSkipReason, credentials: JevCredentials) {
        switch reason {
        case .keyRejected:
            rejectedFingerprint = credentialFingerprint(credentials)
            circuitOpenUntil = Date.distantFuture
            circuitReason = .keyRejected
        case .rateLimited:
            circuitOpenUntil = now().addingTimeInterval(30)
            circuitReason = .rateLimited
        case .timeout, .network, .overloaded, .server:
            noteTransient(reason)
        default:
            break
        }
    }

    private func noteTransient(_ reason: JevSkipReason) {
        transientFailures += 1
        if transientFailures >= 3 {
            circuitOpenUntil = now().addingTimeInterval(5 * 60)
            circuitReason = reason
        }
    }

    private func noteSkip(_ use: JevUse, _ reason: JevSkipReason, preview: String) async {
        await recordSkip(use, reason)
        log.debug("use=\(use.rawValue, privacy: .public) skipped=\(reason.rawValue, privacy: .public)")
        _ = preview
    }
}
