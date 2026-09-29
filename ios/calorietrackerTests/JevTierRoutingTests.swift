import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct JevTierRoutingTests {
    private let credentials = JevCredentials(endpoint: .direct, apiKey: "test-key", model: "jev-latest")
    private let base = AIProviderSettings.RequestConfig(provider: .gemini, model: "gemini-strong", baseURL: "https://example.test", apiKey: "user-key")

    init() { TypeSafeStub.reset() }

    @Test func decideTable() {
        let gemma = JevTierEligibility(gemma: true, appleIntelligence: false, cheapModel: "gemini-cheap")
        #expect(JevTierRouter.decide(score: 0.2, needsUserData: 0.1, eligibility: gemma, isChat: true) == .onDevice)
        #expect(JevTierRouter.decide(score: 0.2, needsUserData: 0.8, eligibility: gemma, isChat: true) == .cheap)
        #expect(JevTierRouter.decide(score: 1.0, needsUserData: nil, eligibility: gemma, isChat: false) == .cheap)
        #expect(JevTierRouter.decide(score: 2.0, needsUserData: nil, eligibility: gemma, isChat: false) == .strong)
        #expect(JevTierRouter.decide(score: nil, needsUserData: nil, eligibility: gemma, isChat: false) == .strong)
        let apple = JevTierEligibility(gemma: false, appleIntelligence: true, cheapModel: "")
        #expect(JevTierRouter.decide(score: 0.4, needsUserData: 0.1, eligibility: apple, isChat: true) == .appleIntelligence)
    }

    @Test func noCheaperTierMakesZeroRequests() async {
        let plan = await JevTierRouter.plan(
            .textFood("oatmeal"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility() },
            isEnabled: { true }
        )
        #expect(plan.tier == .strong)
        #expect(plan.primary.model == base.model)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func gemmaNotSelectableFallsToCheap() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.2, confidence: 0.9)) }
        let plan = await JevTierRouter.plan(
            .textFood("apple"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(gemma: false, appleIntelligence: false, cheapModel: "gemini-cheap") },
            isEnabled: { true }
        )
        #expect(plan.tier == .cheap)
        #expect(plan.primary.model == "gemini-cheap")
    }

    @Test func chatNeedingDataNeverOnDevice() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.chatJSON(score: 0.2, noul: 0.8)) }
        let plan = await JevTierRouter.plan(
            .coachChat("how much did I eat"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(gemma: true, appleIntelligence: true, cheapModel: "") },
            isEnabled: { true }
        )
        #expect(plan.tier == .strong)
        #expect(plan.primary.provider == .gemini)
    }

    @Test func lowConfidenceKeepsStrong() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.2, confidence: 0.1)) }
        let plan = await JevTierRouter.plan(
            .textFood("rice"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(gemma: true, cheapModel: "gemini-cheap") },
            isEnabled: { true }
        )
        #expect(plan.tier == .strong)
    }

    @Test func timeoutKeepsStrong() async {
        TypeSafeStub.delay = 2
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.2, confidence: 0.9)) }
        let started = Date()
        let plan = await JevTierRouter.plan(
            .textFood("rice"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(gemma: true, cheapModel: "gemini-cheap") },
            isEnabled: { true }
        )
        #expect(plan.tier == .strong)
        #expect(Date().timeIntervalSince(started) < 1.2)
    }

    @Test func planNeverChangesProviderOrKey() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(1.0, confidence: 0.9)) }
        let plan = await JevTierRouter.plan(
            .textFood("rice"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(cheapModel: "gemini-cheap") },
            isEnabled: { true }
        )
        #expect(plan.primary.provider == base.provider)
        #expect(plan.primary.baseURL == base.baseURL)
        #expect(plan.primary.apiKey == base.apiKey)
        #expect(plan.primary.model == "gemini-cheap")
    }

    @Test func imageRequestNotRouted() {
        #expect(JevTierRouter.routes(hasImage: true, hosted: false) == false)
        #expect(JevTierRouter.routes(hasImage: false, hosted: true) == false)
        #expect(JevTierRouter.routes(hasImage: false, hosted: false) == true)
    }

    private func makeRouter() -> JevRouter {
        JevRouter(
            credentials: { credentials },
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
        let defaults = UserDefaults(suiteName: "jev.tier.\(name)")!
        defaults.removePersistentDomain(forName: "jev.tier.\(name)")
        return defaults
    }

    private static func scoreJSON(_ score: Double, confidence: Double) -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": ["complexity": ["type": "score", "score": score, "confidence": confidence, "probabilities": ["0": 0.2, "1": 0.8]]],
            "usage": ["input_tokens": 12, "output_tokens": 2]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }

    private static func chatJSON(score: Double, noul: Double) -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": [
                "complexity": ["type": "score", "score": score, "confidence": 0.9, "probabilities": ["0": 0.9]],
                "needs_user_data": ["type": "noul", "noul": noul]
            ],
            "usage": ["input_tokens": 12, "output_tokens": 2]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }
}
