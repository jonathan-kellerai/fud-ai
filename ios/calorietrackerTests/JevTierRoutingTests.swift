import Foundation
import Testing
import UIKit
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

    // MARK: - GeminiService seam (AIRouteEnvironment)

    @Test func seamHostedNeverPlans() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log, hosted: true, plan: { _, _ in
            Issue.record("Hosted mode never asks the router")
            return nil
        }) { _ in Self.foodJSON }
        try await withRoute(environment) {
            let text = try await GeminiService.analyzeTextInput(description: "oatmeal", skipHostedMetering: true)
            #expect(text.name == "Oatmeal")
            let images = (0..<4).map { _ in Self.image() }
            _ = try await GeminiService.analyzeFood(images: images, skipHostedMetering: true)
        }
        #expect(log.planned.isEmpty)
        #expect(log.sent.isEmpty)
        // Hosted caps photos before encoding, exactly as before.
        #expect(log.hostedImageCounts == [0, HostedAIConstants.maxHostedImages])
    }

    @Test func seamNutrientGoalsSendsBase() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in #"{"fiber":31}"# }
        let goals = try await withRoute(environment) {
            try await GeminiService.suggestOptionalNutrientGoals(
                profile: Self.profile(),
                currentGoals: .defaults,
                heightMetric: true,
                weightMetric: true
            )
        }
        #expect(goals.goal(for: .fiber) == 31)
        #expect(log.planned.isEmpty)
        #expect(log.sent == [base.model])
    }

    @Test func seamTextFoodPlansFoodText() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in Self.foodJSON }
        let food = try await withRoute(environment) {
            try await GeminiService.analyzeTextInput(description: "two eggs", skipHostedMetering: true)
        }
        #expect(food.calories == 150)
        #expect(log.planned == ["food_text"])
        #expect(log.sent == [base.model])
        #expect(log.sentImageCounts == [0])
    }

    @Test func seamImageFallbackForImages() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(
            log,
            textFallback: Self.config(.openai, "text-fallback"),
            imageFallback: Self.config(.anthropic, "vision-fallback")
        ) { config in
            if config.model == "gemini-strong" { throw StubError.failed }
            return Self.foodJSON
        }
        _ = try await withRoute(environment) {
            try await GeminiService.analyzeFood(image: Self.image(), skipHostedMetering: true)
        }
        #expect(log.planned == ["food_photo"])
        #expect(log.plannedHasImage == [true])
        #expect(log.sent == ["gemini-strong", "vision-fallback"])
        #expect(log.sentImageCounts == [1, 1])
    }

    @Test func seamTerminalErrorSkipsFallback() async {
        let log = RouteLog()
        let environment = routeEnvironment(log, imageFallback: Self.config(.anthropic, "vision-fallback")) { _ in
            throw GeminiService.AnalysisError.imageConversionFailed
        }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.analyzeFood(image: Self.image(), skipHostedMetering: true)
            }
            Issue.record("Expected imageConversionFailed")
        } catch GeminiService.AnalysisError.imageConversionFailed {
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        #expect(log.sent == ["gemini-strong"])
    }

    @Test func seamWorkoutClarificationNeverFallsBack() async {
        for (reply, isClarification) in [(#"{"question":"Which day?"}"#, true), ("not a workout", false)] {
            let log = RouteLog()
            let environment = routeEnvironment(log, textFallback: Self.config(.openai, "text-fallback")) { _ in reply }
            do {
                _ = try await withRoute(environment) {
                    try await GeminiService.analyzeWorkout(description: Self.workoutText, date: Date(), unit: .kg, library: [])
                }
                Issue.record("Expected the draft error")
            } catch {
                #expect((error is WorkoutClarification) == isClarification)
                #expect((error is WorkoutTextError) == !isClarification)
            }
            #expect(log.planned == ["workout_parse"])
            // Search prompt, then draft prompt, both on the primary. The fallback never runs.
            #expect(log.sent == ["gemini-strong", "gemini-strong"])
        }
    }

    @Test func seamPickedEscalationThenFallback_currentBehavior() async {
        let log = RouteLog()
        let apple = Self.config(.appleIntelligence, "System Language Model")
        let cloud = Self.config(.openai, "cloud-text")
        let environment = routeEnvironment(
            log,
            base: apple,
            plan: { _, _ in JevTierPlan(primary: apple, strong: cloud, tier: .appleIntelligence, pickedOnDevice: true) },
            textFallback: cloud
        ) { _ in throw StubError.failed }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.analyzeWorkout(description: Self.workoutText, date: Date(), unit: .kg, library: [])
            }
            Issue.record("Expected both providers to fail")
        } catch {
            #expect(error is AnalysisFallbackError)
        }
        // Today the escalation target runs a second time as the configured fallback.
        #expect(log.sent == ["System Language Model", "cloud-text", "cloud-text"])
        #expect(log.notices.count == 1)
    }

    @Test func runWithFallbackSurfacesBothErrors() async {
        let fallback = Self.config(.openai, "text-fallback")
        var tried: [String] = []
        var surfaced: (String, String)?
        do {
            _ = try await JevTierRouter.runWithFallback(
                JevTierPlan(primary: base, strong: base, tier: .strong),
                fallback: { _ in fallback },
                surface: { primaryError, config, fallbackError in
                    surfaced = (config.model, fallbackError.localizedDescription)
                    return primaryError
                },
                recordFallback: { _ in Issue.record("No notice for the strong tier") }
            ) { config -> String in
                tried.append(config.model)
                throw StubError.failed
            }
            Issue.record("Expected the surfaced error")
        } catch {
            #expect(error is StubError)
        }
        #expect(tried == [base.model, "text-fallback"])
        #expect(surfaced?.0 == "text-fallback")
    }

    /// What the seam asked the environment for, in order.
    private final class RouteLog {
        var planned: [String] = []
        var plannedHasImage: [Bool] = []
        var sent: [String] = []
        var sentImageCounts: [Int] = []
        var hostedImageCounts: [Int] = []
        var notices: [OnDeviceFallbackNotice?] = []
    }

    /// `plan` returning nil keeps `base`, like a disabled router.
    private func routeEnvironment(
        _ log: RouteLog,
        hosted: Bool = false,
        base baseOverride: AIProviderSettings.RequestConfig? = nil,
        plan: ((JevTierRequest, AIProviderSettings.RequestConfig) -> JevTierPlan?)? = nil,
        textFallback: AIProviderSettings.RequestConfig? = nil,
        imageFallback: AIProviderSettings.RequestConfig? = nil,
        reply: @escaping (AIProviderSettings.RequestConfig) throws -> String
    ) -> AIRouteEnvironment {
        let baseConfig = baseOverride ?? base
        return AIRouteEnvironment(
            isHosted: { hosted },
            base: { _ in baseConfig },
            plan: { request, requestBase in
                log.planned.append(request.requestType)
                log.plannedHasImage.append(request.hasImage)
                return plan?(request, requestBase) ?? JevTierPlan(primary: requestBase, strong: requestBase, tier: .strong)
            },
            textFallback: { _ in textFallback },
            imageFallback: { _ in imageFallback },
            recordFallback: { log.notices.append($0) },
            dispatch: { config, _, imageDataList, _ in
                log.sent.append(config.model)
                log.sentImageCounts.append(imageDataList.count)
                return try reply(config)
            },
            hosted: { _, imageDataList in
                log.hostedImageCounts.append(imageDataList.count)
                return try reply(Self.config(.gemini, "hosted"))
            }
        )
    }

    private func withRoute<T>(_ environment: AIRouteEnvironment, _ body: () async throws -> T) async rethrows -> T {
        let saved = AIRouteEnvironment.current
        AIRouteEnvironment.current = environment
        defer { AIRouteEnvironment.current = saved }
        return try await body()
    }

    private static func config(_ provider: AIProvider, _ model: String) -> AIProviderSettings.RequestConfig {
        AIProviderSettings.RequestConfig(
            provider: provider,
            model: model,
            baseURL: "https://\(model).test",
            apiKey: provider.requiresAPIKey ? "key" : nil
        )
    }

    private static let foodJSON = #"{"name":"Oatmeal","calories":150,"protein":5,"carbs":27,"fat":3,"serving_size_grams":40,"ingredients":[],"unit_options":[]}"#

    /// Starts with "{" so the on-device fast path steps aside and the AI path runs.
    private static let workoutText = #"{"answer":"bench 3x10 at 60kg"}"#

    private static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static func profile() -> UserProfile {
        UserProfile(
            name: "Router",
            gender: .male,
            birthday: Date(timeIntervalSince1970: 0),
            heightCm: 180,
            weightKg: 80,
            activityLevel: .moderate,
            goal: .maintain
        )
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
