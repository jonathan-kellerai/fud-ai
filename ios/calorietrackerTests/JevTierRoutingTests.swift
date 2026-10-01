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

    // MARK: - Every path through the router

    @Test func requestTypes() {
        #expect(JevTierRequest.textFood("x").requestType == "food_text")
        #expect(JevTierRequest.coachChat("x").requestType == "coach_chat")
        #expect(JevTierRequest.workoutParse("x").requestType == "workout_parse")
        #expect(JevTierRequest.foodPhoto(caption: "x").requestType == "food_photo")
        #expect(JevTierRequest.coachPhoto("x").requestType == "coach_photo")
        #expect(JevTierRequest.foodPhoto(caption: "").hasImage)
        #expect(JevTierRequest.coachPhoto("x").hasImage)
        #expect(!JevTierRequest.workoutParse("x").hasImage)
        #expect(!JevTierRequest.workoutParse("x").isChat)
        #expect(JevTierRequest.coachPhoto("x").isChat)
    }

    @Test func imageRequestAlwaysCloudTier() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.1, confidence: 0.95)) }
        let telemetry = JevRouterTelemetry(defaults: suite(UUID().uuidString))
        let router = makeRouter(telemetry: telemetry)
        for request in [JevTierRequest.foodPhoto(caption: "salad"), .coachPhoto("what is this?")] {
            let plan = await JevTierRouter.plan(
                request,
                base: base,
                router: router,
                eligibility: { JevTierEligibility(gemma: true, appleIntelligence: true, cheapModel: "gemini-cheap") },
                isEnabled: { true },
                onDevice: { Self.state(.appleFoundationModels) },
                recordFallback: { _ in Issue.record("Image requests never note an on-device fallback") }
            )
            #expect(plan.tier == .strong)
            #expect(!plan.pickedOnDevice)
            #expect(plan.primary.provider == base.provider)
            #expect(plan.primary.model == base.model)
            #expect(plan.primary.apiKey == base.apiKey)
        }
        #expect(TypeSafeStub.requests.isEmpty)
        let stats = telemetry.snapshot.uses[JevUse.tierRouting.rawValue]
        #expect(stats?.localShortcuts == 2)
        #expect(telemetry.decisions.last?.result == "image → cloud")
    }

    @Test func imageRequestWithRouterOffRecordsNothing() async {
        let telemetry = JevRouterTelemetry(defaults: suite(UUID().uuidString))
        let plan = await JevTierRouter.plan(
            .foodPhoto(caption: ""),
            base: base,
            router: makeRouter(telemetry: telemetry),
            eligibility: { JevTierEligibility() },
            isEnabled: { false },
            onDevice: { Self.state(.off) }
        )
        #expect(plan.tier == .strong)
        #expect(plan.primary.model == base.model)
        #expect(telemetry.decisions.isEmpty)
    }

    @Test func workoutParseEligibleForOnDevice() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.2, confidence: 0.9)) }
        let plan = await JevTierRouter.plan(
            .workoutParse("bench 3x10 at 60kg"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(gemma: true, appleIntelligence: false, cheapModel: "gemini-cheap") },
            isEnabled: { true },
            onDevice: { Self.state(.off) }
        )
        #expect(plan.tier == .onDevice)
        #expect(plan.primary.provider == .gemma4Local)
        #expect(plan.strong.provider == base.provider)
        #expect(!plan.pickedOnDevice)
        let body = TypeSafeStub.requests.first?.1.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(body.contains("workout_parse"))
    }

    @Test func disabledRouterReturnsBase() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.1, confidence: 0.95)) }
        for request in [JevTierRequest.textFood("apple"), .workoutParse("squat 5x5"), .coachChat("hi")] {
            let plan = await JevTierRouter.plan(
                request,
                base: base,
                router: makeRouter(),
                eligibility: { JevTierEligibility(gemma: true, appleIntelligence: true, cheapModel: "gemini-cheap") },
                isEnabled: { false },
                onDevice: { Self.state(.off) }
            )
            #expect(plan.tier == .strong)
            #expect(plan.primary.provider == base.provider)
            #expect(plan.primary.model == base.model)
            #expect(!plan.pickedOnDevice)
        }
        #expect(TypeSafeStub.requests.isEmpty)
    }

    // MARK: - On-device model picker

    @Test func selectorTable() {
        let text = JevTierRequest.textFood("eggs")
        #expect(OnDeviceModelSelector.select(Self.state(.off), request: text) == .router)
        #expect(OnDeviceModelSelector.select(Self.state(.appleFoundationModels), request: text) == .onDevice(.appleIntelligence))
        #expect(OnDeviceModelSelector.select(Self.state(.gemma4), request: .workoutParse("run 5k")) == .onDevice(.onDevice))
        #expect(OnDeviceModelSelector.select(Self.state(.gemma4), request: .coachChat("hi")) == .onDevice(.onDevice))
        #expect(OnDeviceModelSelector.select(
            Self.state(.appleFoundationModels, apple: .unavailable("Enable Apple Intelligence in iPhone Settings")),
            request: text
        ) == .fallBack(reason: "Enable Apple Intelligence in iPhone Settings"))
        #expect(OnDeviceModelSelector.select(
            Self.state(.gemma4, gemma: .unavailable("not downloaded")),
            request: .coachChat("hi")
        ) == .fallBack(reason: "not downloaded"))
        // Apple unavailable does not matter when Gemma is picked, and vice versa.
        #expect(OnDeviceModelSelector.select(
            Self.state(.gemma4, apple: .unavailable("off")),
            request: text
        ) == .onDevice(.onDevice))
        for choice in OnDeviceModelChoice.allCases {
            #expect(OnDeviceModelSelector.select(Self.state(choice), request: .foodPhoto(caption: "")) == .cloudForImage)
            #expect(OnDeviceModelSelector.select(Self.state(choice), request: .coachPhoto("x")) == .cloudForImage)
        }
    }

    @Test func pickedAppleBypassesComplexityScore() async {
        for request in [JevTierRequest.textFood("big burrito with extra guac"), .workoutParse("bench 3x10"), .coachChat("how much did I eat")] {
            let plan = await JevTierRouter.plan(
                request,
                base: base,
                router: makeRouter(),
                eligibility: { JevTierEligibility() },
                isEnabled: { false },
                onDevice: { Self.state(.appleFoundationModels) },
                recordFallback: { _ in Issue.record("Available model never notes a fallback") }
            )
            #expect(plan.tier == .appleIntelligence)
            #expect(plan.pickedOnDevice)
            #expect(plan.primary.provider == .appleIntelligence)
            #expect(plan.primary.apiKey == nil)
            #expect(plan.strong.provider == base.provider)
            #expect(plan.strong.model == base.model)
        }
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func pickedGemmaUsesLocalProvider() async {
        let plan = await JevTierRouter.plan(
            .coachChat("hi"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility() },
            isEnabled: { true },
            onDevice: { Self.state(.gemma4) }
        )
        #expect(plan.tier == .onDevice)
        #expect(plan.primary.provider == .gemma4Local)
        #expect(plan.pickedOnDevice)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func pickedButUnavailableFallsBackToCloudWithNotice() async {
        var notices: [OnDeviceFallbackNotice?] = []
        let plan = await JevTierRouter.plan(
            .textFood("toast"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility(gemma: true, cheapModel: "gemini-cheap") },
            isEnabled: { true },
            onDevice: { Self.state(.gemma4, gemma: .unavailable("Gemma 4 isn't downloaded and prepared yet")) },
            recordFallback: { notices.append($0) }
        )
        #expect(plan.tier == .strong)
        #expect(!plan.pickedOnDevice)
        #expect(plan.primary.provider == base.provider)
        #expect(plan.primary.model == base.model)
        #expect(notices.count == 1)
        #expect(notices.first??.provider == AIProvider.gemini.displayName)
        #expect(notices.first??.line == "Fell back to \(AIProvider.gemini.displayName) last time: Gemma 4 isn't downloaded and prepared yet")
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func pickedFallbackReachesCloudWhenTextProviderIsOnDevice() async throws {
        let appleBase = AIProviderSettings.RequestConfig(provider: .appleIntelligence, model: "System Language Model", baseURL: "", apiKey: nil)
        let cloud = base

        // Picked Apple on an Apple text provider: escalates to the cloud text fallback.
        let picked = await JevTierRouter.plan(
            .textFood("toast"),
            base: appleBase,
            router: makeRouter(),
            eligibility: { JevTierEligibility() },
            isEnabled: { false },
            onDevice: { Self.state(.appleFoundationModels) },
            cloudFallback: { cloud },
            recordFallback: { _ in Issue.record("Available model never notes a fallback") }
        )
        #expect(picked.tier == .appleIntelligence)
        #expect(picked.primary.provider == .appleIntelligence)
        #expect(picked.strong.provider == .gemini)
        #expect(picked.strong.model == cloud.model)

        // Picked Gemma unavailable on an Apple text provider: the cloud fallback answers.
        var notices: [OnDeviceFallbackNotice?] = []
        let unavailable = await JevTierRouter.plan(
            .textFood("toast"),
            base: appleBase,
            router: makeRouter(),
            eligibility: { JevTierEligibility() },
            isEnabled: { false },
            onDevice: { Self.state(.gemma4, gemma: .unavailable("Gemma 4 isn't downloaded and prepared yet")) },
            cloudFallback: { cloud },
            recordFallback: { notices.append($0) }
        )
        #expect(unavailable.tier == .strong)
        #expect(unavailable.primary.provider == .gemini)
        #expect(notices.first??.provider == AIProvider.gemini.displayName)
        #expect(notices.first??.reason == "Gemma 4 isn't downloaded and prepared yet")

        // No cloud fallback configured: keeps base and says so.
        notices = []
        let noCloud = await JevTierRouter.plan(
            .textFood("toast"),
            base: appleBase,
            router: makeRouter(),
            eligibility: { JevTierEligibility() },
            isEnabled: { false },
            onDevice: { Self.state(.appleFoundationModels) },
            cloudFallback: { nil }
        )
        #expect(noCloud.tier == .strong)
        #expect(noCloud.strong.provider == .appleIntelligence)
        do {
            _ = try await JevTierRouter.run(noCloud, recordFallback: { notices.append($0) }) { _ -> String in
                throw Self.StubError.failed
            }
            Issue.record("Expected the primary error")
        } catch {
            #expect(error is Self.StubError)
        }
        #expect(notices.count == 1)
        #expect(notices.first??.reason == "on-device failed; \(JevTierRouter.noCloudProviderReason)")

        // Cloud base: the cloud fallback is never consulted.
        let cloudBase = await JevTierRouter.plan(
            .textFood("toast"),
            base: base,
            router: makeRouter(),
            eligibility: { JevTierEligibility() },
            isEnabled: { false },
            onDevice: { Self.state(.gemma4) },
            cloudFallback: {
                Issue.record("Cloud base needs no fallback lookup")
                return nil
            }
        )
        #expect(cloudBase.tier == .onDevice)
        #expect(cloudBase.strong.provider == base.provider)
        #expect(cloudBase.strong.model == base.model)
    }

    @Test func pickedOnDeviceFailureEscalatesToCloudAndNotes() async throws {
        let plan = JevTierPlan(
            primary: AIProviderSettings.RequestConfig(provider: .appleIntelligence, model: "System Language Model", baseURL: "", apiKey: nil),
            strong: base,
            tier: .appleIntelligence,
            pickedOnDevice: true
        )
        var notices: [OnDeviceFallbackNotice?] = []
        var tried: [AIProvider] = []
        let answer = try await JevTierRouter.run(plan, recordFallback: { notices.append($0) }) { config in
            tried.append(config.provider)
            if config.provider == .appleIntelligence { throw Self.StubError.failed }
            return "cloud answer"
        }
        #expect(answer == "cloud answer")
        #expect(tried == [.appleIntelligence, .gemini])
        #expect(notices.count == 1)
        #expect(notices.first??.provider == AIProvider.gemini.displayName)
        #expect(notices.first??.reason == "on-device failed")

        notices = []
        let local = try await JevTierRouter.run(plan, recordFallback: { notices.append($0) }) { _ in "local answer" }
        #expect(local == "local answer")
        #expect(notices.count == 1)
        #expect(notices.first! == nil)
    }

    @Test func strongPlanFailureRethrowsWithoutRetry() async {
        let plan = JevTierPlan(primary: base, strong: base, tier: .strong)
        var calls = 0
        do {
            _ = try await JevTierRouter.run(plan, recordFallback: { _ in Issue.record("No notice for the strong tier") }) { _ -> String in
                calls += 1
                throw Self.StubError.failed
            }
            Issue.record("Expected the primary error")
        } catch {
            #expect(error is Self.StubError)
        }
        #expect(calls == 1)
    }

    @Test func pickerDefaultsToOff() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: OnDeviceModelSettings.choiceKey)
        defer { defaults.set(saved, forKey: OnDeviceModelSettings.choiceKey) }
        defaults.removeObject(forKey: OnDeviceModelSettings.choiceKey)
        #expect(OnDeviceModelSettings.choice == .off)
        defaults.set("unknown-model", forKey: OnDeviceModelSettings.choiceKey)
        #expect(OnDeviceModelSettings.choice == .off)
        OnDeviceModelSettings.choice = .gemma4
        #expect(OnDeviceModelSettings.choice == .gemma4)
    }

    private enum StubError: LocalizedError {
        case failed
        var errorDescription: String? { "on-device failed" }
    }

    private static func state(
        _ choice: OnDeviceModelChoice,
        apple: OnDeviceModelAvailability = .available,
        gemma: OnDeviceModelAvailability = .available
    ) -> OnDeviceModelState {
        OnDeviceModelState(choice: choice, apple: apple, gemma: gemma)
    }

    private func makeRouter(telemetry: JevRouterTelemetry? = nil) -> JevRouter {
        JevRouter(
            credentials: { credentials },
            isActive: { _ in true },
            killSwitch: { false },
            session: stubSession(),
            telemetry: telemetry ?? JevRouterTelemetry(defaults: suite(UUID().uuidString))
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
