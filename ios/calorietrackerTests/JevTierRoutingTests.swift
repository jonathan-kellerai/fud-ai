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
        #expect(JevTierRequest.allergenReport.requestType == "allergen_report")
        #expect(JevTierRequest.servingUnitsPhoto("x").requestType == "serving_units_photo")
        #expect(JevTierRequest.servingUnits("x").requestType == "serving_units")
        #expect(JevTierRequest.mealWhatIf("x").requestType == "meal_what_if")
        #expect(JevTierRequest.nutrientGoals.requestType == "nutrient_goals")
        #expect(JevTierRequest.goalCalculation.requestType == "goal_calculation")
        #expect(JevTierRequest.allergenReport.hasImage)
        #expect(JevTierRequest.servingUnitsPhoto("x").hasImage)
        #expect(!JevTierRequest.servingUnits("x").hasImage)
        #expect(!JevTierRequest.goalCalculation.hasImage)
        // Only names or nothing reach the classifier and telemetry, never profile data.
        #expect(JevTierRequest.nutrientGoals.text.isEmpty)
        #expect(JevTierRequest.goalCalculation.preview == "goal_calculation")
        #expect(JevTierRequest.mealWhatIf("Pizza").preview == "Pizza")
        let policies = [
            JevTierRequest.textFood("x"), .coachChat("x"), .workoutParse("x"), .foodPhoto(caption: ""), .coachPhoto("x"),
            .allergenReport, .servingUnitsPhoto("x"), .servingUnits("x"), .mealWhatIf("x"), .nutrientGoals, .goalCalculation
        ].map(\.onDevicePolicy)
        #expect(policies == [.scored, .scored, .scored, .baseOnly, .baseOnly,
                             .baseOnly, .baseOnly, .pickerOnly, .pickerOnly, .pickerOnly, .baseOnly])
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
            #expect(OnDeviceModelSelector.select(Self.state(choice), request: .foodPhoto(caption: "")) == .baseOnly)
            #expect(OnDeviceModelSelector.select(Self.state(choice), request: .coachPhoto("x")) == .baseOnly)
            #expect(OnDeviceModelSelector.select(Self.state(choice), request: .allergenReport) == .baseOnly)
            #expect(OnDeviceModelSelector.select(Self.state(choice), request: .goalCalculation) == .baseOnly)
        }
        #expect(OnDeviceModelSelector.select(Self.state(.off), request: .mealWhatIf("x")) == .router)
        #expect(OnDeviceModelSelector.select(Self.state(.gemma4), request: .nutrientGoals) == .onDevice(.onDevice))
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
        #expect(log.planned == ["nutrient_goals"])
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

    @Test func seamPickedEscalationSkipsDuplicateFallback() async {
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
        } catch let error as AnalysisFallbackError {
            #expect(error.fallbackName == AIProvider.openai.displayName)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        // The escalation already tried the configured fallback, so it isn't sent a second time.
        #expect(log.sent == ["System Language Model", "cloud-text"])
        #expect(log.notices.count == 1)
    }

    @Test func fallbackDifferentFromStrongStillRuns() async {
        let log = RouteLog()
        let apple = Self.config(.appleIntelligence, "System Language Model")
        let cloud = Self.config(.openai, "cloud-text")
        let environment = routeEnvironment(
            log,
            base: apple,
            plan: { _, _ in JevTierPlan(primary: apple, strong: cloud, tier: .appleIntelligence, pickedOnDevice: true) },
            textFallback: Self.config(.anthropic, "other-fallback")
        ) { _ in throw StubError.failed }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.analyzeWorkout(description: Self.workoutText, date: Date(), unit: .kg, library: [])
            }
            Issue.record("Expected every provider to fail")
        } catch {
            #expect(error is AnalysisFallbackError)
        }
        #expect(log.sent == ["System Language Model", "cloud-text", "other-fallback"])
    }

    @Test func cheapTierSkipsFallbackEqualToBase() async {
        let log = RouteLog()
        let cheap = AIProviderSettings.RequestConfig(provider: base.provider, model: "gemini-cheap", baseURL: base.baseURL, apiKey: base.apiKey)
        let strong = base
        let environment = routeEnvironment(
            log,
            plan: { _, _ in JevTierPlan(primary: cheap, strong: strong, tier: .cheap) },
            textFallback: base
        ) { _ in throw StubError.failed }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.analyzeTextInput(description: "burrito", skipHostedMetering: true)
            }
            Issue.record("Expected both tiers to fail")
        } catch {
            #expect(error is AnalysisFallbackError)
        }
        #expect(log.sent == ["gemini-cheap", "gemini-strong"])
    }

    @Test func strongPlanFallbackUnchanged() async {
        // A strong plan only tries the primary, so the configured fallback always runs, even one
        // that matches the primary (the live settings already exclude that case).
        for fallback in [Self.config(.openai, "text-fallback"), base] {
            let log = RouteLog()
            let environment = routeEnvironment(log, textFallback: fallback) { _ in throw StubError.failed }
            do {
                _ = try await withRoute(environment) {
                    try await GeminiService.analyzeTextInput(description: "rice", skipHostedMetering: true)
                }
                Issue.record("Expected both providers to fail")
            } catch {
                #expect(error is AnalysisFallbackError)
            }
            #expect(log.sent == ["gemini-strong", fallback.model])
        }
    }

    @Test func skippedFallbackKeepsWorkoutTerminalError() async {
        let log = RouteLog()
        let apple = Self.config(.appleIntelligence, "System Language Model")
        let cloud = Self.config(.openai, "cloud-text")
        let environment = routeEnvironment(
            log,
            base: apple,
            plan: { _, _ in JevTierPlan(primary: apple, strong: cloud, tier: .appleIntelligence, pickedOnDevice: true) },
            textFallback: cloud
        ) { config in
            if config.provider == .appleIntelligence { throw StubError.failed }
            return "not a workout"
        }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.analyzeWorkout(description: Self.workoutText, date: Date(), unit: .kg, library: [])
            }
            Issue.record("Expected the unreadable draft")
        } catch {
            // As before: the unreadable cloud draft surfaces directly, never wrapped as "both failed".
            #expect(error is WorkoutTextError)
        }
        // Apple fails on the search prompt; the escalation reads both prompts; no third try.
        #expect(log.sent == ["System Language Model", "cloud-text", "cloud-text"])
    }

    @Test func alreadyTriedTable() {
        let apple = Self.config(.appleIntelligence, "System Language Model")
        let picked = JevTierPlan(primary: apple, strong: base, tier: .appleIntelligence, pickedOnDevice: true)
        #expect(picked.attempted.map(\.model) == ["System Language Model", "gemini-strong"])
        #expect(picked.alreadyTried(provider: base.provider, model: base.model, baseURL: base.baseURL))
        #expect(!picked.alreadyTried(provider: base.provider, model: base.model, baseURL: "https://other.test"))
        #expect(!picked.alreadyTried(provider: base.provider, model: "gemini-cheap", baseURL: base.baseURL))
        #expect(!picked.alreadyTried(provider: .openai, model: base.model, baseURL: base.baseURL))

        let strong = JevTierPlan(primary: base, strong: base, tier: .strong)
        #expect(strong.attempted.map(\.model) == ["gemini-strong"])
        #expect(strong.alreadyTried(provider: base.provider, model: base.model, baseURL: base.baseURL))
    }

    // MARK: - Every GeminiService path asks the router

    @Test func routeMealWhatIf() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in "  Fits well.  " }
        let entry = FoodEntry(name: "Pizza", calories: 800, protein: 30, carbs: 90, fat: 35, timestamp: Date(), source: .manual, mealType: .dinner)
        let advice = try await withRoute(environment) {
            try await GeminiService.suggestMealWhatIf(entry: entry, dayEntries: [], profile: Self.profile(), weightMetric: true)
        }
        #expect(advice == "Fits well.")
        #expect(log.planned == ["meal_what_if"])
        #expect(log.plannedHasImage == [false])
    }

    @Test func routeGoalCalculation() async {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in throw StubError.failed }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.calculateGoals(profile: Self.profile(), heightMetric: true, weightMetric: true, countTowardHostedQuota: false)
            }
            Issue.record("Expected the provider error")
        } catch {
            #expect(error is StubError)
        }
        #expect(log.planned == ["goal_calculation"])
        #expect(log.sent == [base.model])
    }

    @Test func routeAllergenReport() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in #"{"allergens":["milk"]}"# }
        let allergens = try await withRoute(environment) {
            try await GeminiService.extractAllergensFromLabReport(images: [Self.image()])
        }
        #expect(allergens == ["milk"])
        #expect(log.planned == ["allergen_report"])
        #expect(log.plannedHasImage == [true])
        #expect(log.sentImageCounts == [1])
    }

    @Test func routeTextFood() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in Self.foodJSON }
        _ = try await withRoute(environment) {
            try await GeminiService.analyzeTextInput(description: "oatmeal", skipHostedMetering: true)
        }
        #expect(log.planned == ["food_text"])
        #expect(log.plannedHasImage == [false])
    }

    @Test func routeTextFoodServingRepair() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in
            log.sent.count == 1 ? Self.zeroMacroJSON : #"{"unit_options":[]}"#
        }
        _ = try await withRoute(environment) {
            try await GeminiService.analyzeTextInput(description: "glass of water", skipHostedMetering: true)
        }
        #expect(log.planned == ["food_text", "serving_units"])
        #expect(log.plannedHasImage == [false, false])
    }

    @Test func routePhotoFood() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in Self.foodJSON }
        try await withRoute(environment) {
            _ = try await GeminiService.analyzeFood(image: Self.image(), description: "lunch", skipHostedMetering: true)
            _ = try await GeminiService.autoAnalyze(image: Self.image())
            _ = try await GeminiService.analyzeFood(images: [Self.image(), Self.image()], skipHostedMetering: true)
        }
        #expect(log.planned == ["food_photo", "food_photo", "food_photo"])
        #expect(log.plannedHasImage == [true, true, true])
        #expect(log.sentImageCounts == [1, 1, 2])
    }

    @Test func routePhotoServingRepair() async throws {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in
            log.sent.count == 1 ? Self.zeroMacroJSON : #"{"unit_options":[]}"#
        }
        _ = try await withRoute(environment) {
            try await GeminiService.analyzeFood(image: Self.image(), skipHostedMetering: true)
        }
        #expect(log.planned == ["food_photo", "serving_units_photo"])
        #expect(log.plannedHasImage == [true, true])
    }

    @Test func routeWorkoutParse() async {
        let log = RouteLog()
        let environment = routeEnvironment(log) { _ in throw StubError.failed }
        do {
            _ = try await withRoute(environment) {
                try await GeminiService.analyzeWorkout(description: Self.workoutText, date: Date(), unit: .kg, library: [])
            }
            Issue.record("Expected the provider error")
        } catch {
            #expect(error is StubError)
        }
        #expect(log.planned == ["workout_parse"])
    }

    // MARK: - Tier policies

    @Test func pickerOnlySkipsClassifier() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.1, confidence: 0.95)) }
        let telemetry = JevRouterTelemetry(defaults: suite(UUID().uuidString))
        let router = makeRouter(telemetry: telemetry)
        for request in [JevTierRequest.mealWhatIf("pizza"), .nutrientGoals, .servingUnits("toast")] {
            let plan = await JevTierRouter.plan(
                request,
                base: base,
                router: router,
                eligibility: { JevTierEligibility(gemma: true, appleIntelligence: true, cheapModel: "gemini-cheap") },
                isEnabled: { true },
                onDevice: { Self.state(.off) },
                recordFallback: { _ in Issue.record("Picker Off never notes a fallback") }
            )
            #expect(plan.tier == .strong)
            #expect(!plan.pickedOnDevice)
            #expect(plan.primary.model == base.model)
        }
        #expect(TypeSafeStub.requests.isEmpty)
        #expect(telemetry.decisions.count == 3)
        #expect(telemetry.decisions.last?.result == "fixed → your model")
    }

    @Test func pickerOnlyHonorsPickedApple() async {
        for request in [JevTierRequest.mealWhatIf("pizza"), .nutrientGoals, .servingUnits("toast")] {
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
            #expect(plan.strong.model == base.model)
        }
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func pickerOnlyRouterOffPickerOffRecordsNothing() async {
        let telemetry = JevRouterTelemetry(defaults: suite(UUID().uuidString))
        for request in [JevTierRequest.mealWhatIf("pizza"), .nutrientGoals, .servingUnits("toast")] {
            let plan = await JevTierRouter.plan(
                request,
                base: base,
                router: makeRouter(telemetry: telemetry),
                eligibility: { JevTierEligibility(gemma: true, appleIntelligence: true, cheapModel: "gemini-cheap") },
                isEnabled: { false },
                onDevice: { Self.state(.off) },
                cloudFallback: {
                    Issue.record("Picker Off needs no cloud lookup")
                    return nil
                },
                recordFallback: { _ in Issue.record("Picker Off never notes a fallback") }
            )
            // Byte-identical to before: the same provider, model, server and key.
            #expect(plan.tier == .strong)
            #expect(plan.primary.provider == base.provider)
            #expect(plan.primary.model == base.model)
            #expect(plan.primary.baseURL == base.baseURL)
            #expect(plan.primary.apiKey == base.apiKey)
        }
        #expect(TypeSafeStub.requests.isEmpty)
        #expect(telemetry.decisions.isEmpty)
    }

    @Test func goalCalculationNeverOnDevice() async {
        await expectBaseOnly(.goalCalculation)
    }

    @Test func baseOnlyImagePathsKeepBase() async {
        await expectBaseOnly(.allergenReport)
        await expectBaseOnly(.servingUnitsPhoto("toast"))
    }

    /// `.baseOnly`: the user's own base comes back unchanged for cloud, Apple and Gemma bases,
    /// whatever the picker says, with no classifier call, no cloud lookup and no escalation.
    private func expectBaseOnly(_ request: JevTierRequest) async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.scoreJSON(0.1, confidence: 0.95)) }
        let bases = [
            base,
            Self.config(.appleIntelligence, "System Language Model"),
            Self.config(.gemma4Local, "gemma-local")
        ]
        for userBase in bases {
            for choice in OnDeviceModelChoice.allCases {
                let plan = await JevTierRouter.plan(
                    request,
                    base: userBase,
                    router: makeRouter(),
                    eligibility: { JevTierEligibility(gemma: true, appleIntelligence: true, cheapModel: "gemini-cheap") },
                    isEnabled: { true },
                    onDevice: { Self.state(choice) },
                    cloudFallback: {
                        Issue.record("A base-only request never looks up a cloud config")
                        return nil
                    },
                    recordFallback: { _ in Issue.record("A base-only request never notes a fallback") }
                )
                #expect(plan.tier == .strong)
                #expect(!plan.pickedOnDevice)
                #expect(plan.primary.provider == userBase.provider)
                #expect(plan.primary.model == userBase.model)
                #expect(plan.primary.baseURL == userBase.baseURL)
                #expect(plan.strong.provider == userBase.provider)
                #expect(plan.strong.model == userBase.model)
            }
        }
        #expect(TypeSafeStub.requests.isEmpty)
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

    /// Zero macros and malformed unit_options: the one shape that triggers the serving-unit repair.
    private static let zeroMacroJSON = #"{"name":"Water","calories":0,"protein":0,"carbs":0,"fat":0,"serving_size_grams":250,"ingredients":[],"unit_options":"cup"}"#

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
