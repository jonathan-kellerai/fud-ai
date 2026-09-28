import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct JevRouterCoreTests {
    private let credentials = JevCredentials(endpoint: .direct, apiKey: "test-key", model: "jev-latest")

    init() {
        TypeSafeStub.reset()
    }

    @Test func killSwitchMakesZeroRequests() async {
        let router = makeRouter(killSwitch: true)
        let outcome = await router.ask(.estimateCheck, cacheKey: "meal", preview: "bowl") { model in
            sampleRequest(model)
        }
        #expect(outcome == .skipped(.killSwitch) || isSkip(outcome, .killSwitch))
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func noCredentialsMakesZeroRequests() async {
        let router = makeRouter(includeCredentials: false)
        for use in JevUse.allCases {
            let outcome = await router.ask(use, cacheKey: "x", preview: "x") { sampleRequest($0) }
            #expect(isSkip(outcome, .noKey))
        }
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func budgetExceededReturnsTimeoutQuickly() async {
        TypeSafeStub.delay = 2
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let telemetry = JevRouterTelemetry(defaults: suite("budget"), now: { Date() })
        let router = makeRouter(telemetry: telemetry)
        let started = Date()
        let outcome = await router.ask(
            .mealMatch,
            cacheKey: "slow",
            preview: "chili",
            policy: JevCallPolicy(budget: .milliseconds(300), retryDelaysNs: [], cacheTTL: 60)
        ) { sampleRequest($0) }
        #expect(isSkip(outcome, .timeout))
        #expect(Date().timeIntervalSince(started) < 1)
        #expect(telemetry.snapshot.uses[JevUse.mealMatch.rawValue]?.skipped["timeout"] == 1)
    }

    @Test func cacheHitAvoidsSecondRequest() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let telemetry = JevRouterTelemetry(defaults: suite("cache"))
        let router = makeRouter(telemetry: telemetry)
        _ = await router.ask(.coachIntent, cacheKey: "same", preview: "steps") { sampleRequest($0) }
        _ = await router.ask(.coachIntent, cacheKey: "same", preview: "steps") { sampleRequest($0) }
        #expect(TypeSafeStub.requests.count == 1)
        #expect(telemetry.snapshot.uses[JevUse.coachIntent.rawValue]?.cacheHits == 1)
    }

    @Test func circuitOpensAfterThreeFailures() async {
        TypeSafeStub.handler = { _, _ in (529, [:], Data("{}".utf8)) }
        let clock = TestClock()
        let router = makeRouter(now: { clock.date })
        let policy = JevCallPolicy(budget: .seconds(2), retryDelaysNs: [], cacheTTL: 60)
        for _ in 0..<3 {
            _ = await router.ask(.plausibility, cacheKey: nil, preview: "set", policy: policy) { sampleRequest($0) }
        }
        let blocked = await router.ask(.plausibility, cacheKey: nil, preview: "set", policy: policy) { sampleRequest($0) }
        #expect(isSkip(blocked, .circuitOpen))
        #expect(TypeSafeStub.requests.count == 3)
        clock.date = clock.date.addingTimeInterval(5 * 60 + 1)
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let reopened = await router.ask(.plausibility, cacheKey: "after", preview: "set", policy: policy) { sampleRequest($0) }
        #expect(isAnswer(reopened))
        #expect(TypeSafeStub.requests.count == 4)
    }

    @Test func keyRejectedOpensCircuitUntilCredentialsChange() async {
        let box = CredentialBox(credentials)
        TypeSafeStub.handler = { _, _ in (401, [:], Data(#"{"detail":{"error_type":"authentication_error","message":"no"}}"#.utf8)) }
        let router = makeRouter(credentials: { box.value })
        let policy = JevCallPolicy(budget: .seconds(2), retryDelaysNs: [], cacheTTL: 60)
        _ = await router.ask(.mealMatch, cacheKey: nil, preview: "a", policy: policy) { sampleRequest($0) }
        let blocked = await router.ask(.mealMatch, cacheKey: nil, preview: "b", policy: policy) { sampleRequest($0) }
        #expect(isSkip(blocked, .circuitOpen))
        #expect(TypeSafeStub.requests.count == 1)
        box.value = JevCredentials(endpoint: .direct, apiKey: "other-key", model: "jev-latest")
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let again = await router.ask(.mealMatch, cacheKey: "fresh", preview: "c", policy: policy) { sampleRequest($0) }
        #expect(isAnswer(again))
    }

    @Test func requestShapeIsDocumented() async throws {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let direct = makeRouter()
        _ = await direct.ask(.estimateCheck, cacheKey: nil, preview: "bowl") { sampleRequest($0) }
        let first = try #require(TypeSafeStub.requests.first)
        #expect(first.0.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(first.0.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let body = try #require(first.1)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["state"] != nil)
        #expect(json["model"] as? String == "jev-latest")
        #expect(json["questions"] is [String: Any])

        TypeSafeStub.reset()
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let gatewayCreds = JevCredentials(endpoint: .vercelGateway, apiKey: "test-key", model: "typesafe-ai/jev")
        let gateway = makeRouter(credentials: gatewayCreds)
        _ = await gateway.ask(.estimateCheck, cacheKey: nil, preview: "bowl") { model in
            TypeSafeRequest(state: .string("meal"), model: model, questions: ["ok": .noul(instructions: .string("yes?"), criteria: nil)])
        }
        let second = try #require(TypeSafeStub.requests.first)
        #expect(second.0.url?.absoluteString == "https://ai-gateway.vercel.sh/typesafe/v1/systemone")
        let gatewayJSON = try #require(JSONSerialization.jsonObject(with: try #require(second.1)) as? [String: Any])
        #expect(gatewayJSON["model"] as? String == "typesafe-ai/jev")
    }

    @Test func gatesRejectGatewaySentinels() {
        let answer = TypeSafeAnswer.choice(choice: "m1", confidence: 0, probabilities: [:])
        #expect(JevGates.acceptChoice(answer, minP: 0.8, minConfidence: 0.6, minMargin: 0.3) == nil)
    }

    @Test func telemetryPersistsAndResets() {
        let defaults = suite("persist")
        let telemetry = JevRouterTelemetry(defaults: defaults)
        telemetry.record(.mealMatch, .accepted(label: "oatmeal", confidence: 0.9, llmCallsAvoided: 1), preview: "secret preview", latencyMs: 120, model: "jev-1.13.0")
        telemetry.flush()
        let stored = defaults.data(forKey: JevRouterSettings.statsKey) ?? Data()
        let text = String(decoding: stored, as: UTF8.self)
        #expect(text.contains("test-key") == false)
        #expect(text.contains("secret preview") == false)
        #expect(telemetry.decisions.count == 1)
        telemetry.reset()
        #expect(telemetry.decisions.isEmpty)
        #expect(defaults.data(forKey: JevRouterSettings.statsKey) == nil)
    }

    @Test func decisionLogKeepsLast50() {
        let telemetry = JevRouterTelemetry(defaults: suite("log"))
        for index in 0..<60 {
            telemetry.record(.coachIntent, .localShortcut(label: "steps", llmCallsAvoided: 1), preview: "message \(index)", latencyMs: nil, model: nil)
        }
        #expect(telemetry.decisions.count == 50)
        #expect(telemetry.decisions.first?.preview == "message 10")
    }

    @Test func backupPolicyExcludesRouterStats() {
        #expect(CloudBackupPolicy.include("jevRouter.stats.v1") == false)
        #expect(CloudBackupPolicy.include("jevRouter.exerciseAliases.v1") == false)
        #expect(CloudBackupPolicy.include(JevRouterSettings.enabledKey) == true)
    }

    @Test func estimateCheckHonorsKillSwitch() async {
        let router = makeRouter(killSwitch: true)
        let outcome = await router.ask(.estimateCheck, cacheKey: "bowl", preview: "Chicken rice bowl") { sampleRequest($0) }
        #expect(isSkip(outcome, .killSwitch))
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func estimateCheckRecordsTelemetry() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.okJSON()) }
        let telemetry = JevRouterTelemetry(defaults: suite("estimate"))
        let router = makeRouter(telemetry: telemetry, active: true)
        let outcome = await router.ask(.estimateCheck, cacheKey: "bowl", preview: "Chicken rice bowl") { sampleRequest($0) }
        #expect(isAnswer(outcome))
        await router.report(.estimateCheck, .accepted(label: "ok", confidence: nil, llmCallsAvoided: 0), preview: "Chicken rice bowl")
        #expect(telemetry.snapshot.uses[JevUse.estimateCheck.rawValue]?.accepted == 1)
        telemetry.flush()
    }

    private func makeRouter(
        includeCredentials: Bool = true,
        killSwitch: Bool = false,
        telemetry: JevRouterTelemetry? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        active: Bool = true
    ) -> JevRouter {
        let resolved: JevCredentials? = includeCredentials ? credentials : nil
        return JevRouter(
            credentials: { resolved },
            isActive: { _ in active },
            killSwitch: { killSwitch },
            session: stubSession(),
            telemetry: telemetry ?? JevRouterTelemetry(defaults: suite(UUID().uuidString)),
            now: now
        )
    }

    private func makeRouter(credentials provider: @escaping @Sendable () -> JevCredentials?) -> JevRouter {
        JevRouter(
            credentials: provider,
            isActive: { _ in true },
            killSwitch: { false },
            session: stubSession(),
            telemetry: JevRouterTelemetry(defaults: suite(UUID().uuidString))
        )
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TypeSafeStub.self]
        return URLSession(configuration: configuration)
    }

    private func suite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "jev.router.tests.\(name)")!
        defaults.removePersistentDomain(forName: "jev.router.tests.\(name)")
        return defaults
    }

    private func sampleRequest(_ model: String) -> TypeSafeRequest {
        TypeSafeRequest(
            state: .object(["meal": .string("bowl")]),
            model: model,
            questions: ["ok": .noul(instructions: .string("Is it fine?"), criteria: nil)]
        )
    }

    private func isSkip(_ outcome: JevOutcome, _ reason: JevSkipReason) -> Bool {
        if case .skipped(let actual) = outcome { return actual == reason }
        return false
    }

    private func isAnswer(_ outcome: JevOutcome) -> Bool {
        if case .answered = outcome { return true }
        return false
    }

    private static func okJSON() -> Data {
        Data(#"{"model":"jev-1.13.0","answers":{"ok":{"type":"noul","noul":0.9}},"usage":{"input_tokens":20,"output_tokens":2}}"#.utf8)
    }
}

private final class TestClock: @unchecked Sendable {
    var date = Date()
}

private final class CredentialBox: @unchecked Sendable {
    var value: JevCredentials
    init(_ value: JevCredentials) { self.value = value }
}
