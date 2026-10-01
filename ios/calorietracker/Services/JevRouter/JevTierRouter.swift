import Foundation

enum JevTier: String, Sendable {
    case onDevice
    case appleIntelligence
    case cheap
    case strong
}

struct JevTierEligibility: Sendable {
    var gemma = false
    var appleIntelligence = false
    var cheapModel = ""
}

struct JevTierPlan: Sendable {
    var primary: AIProviderSettings.RequestConfig
    var strong: AIProviderSettings.RequestConfig
    var tier: JevTier
    /// The primary came from Settings → On-device model, not the complexity score.
    var pickedOnDevice = false
}

enum JevTierRequest: Sendable {
    case textFood(String)
    case coachChat(String)
    case workoutParse(String)
    /// Photo food logging. The caption is the optional user note.
    case foodPhoto(caption: String)
    /// Coach message with an attached image.
    case coachPhoto(String)

    var text: String {
        switch self {
        case .textFood(let text), .coachChat(let text), .workoutParse(let text), .coachPhoto(let text): text
        case .foodPhoto(let caption): caption
        }
    }

    var isChat: Bool {
        switch self {
        case .coachChat, .coachPhoto: true
        case .textFood, .workoutParse, .foodPhoto: false
        }
    }

    /// On-device image input isn't available on iOS 26. These always stay on the cloud config.
    var hasImage: Bool {
        switch self {
        case .foodPhoto, .coachPhoto: true
        case .textFood, .coachChat, .workoutParse: false
        }
    }

    var requestType: String {
        switch self {
        case .textFood: "food_text"
        case .coachChat: "coach_chat"
        case .workoutParse: "workout_parse"
        case .foodPhoto: "food_photo"
        case .coachPhoto: "coach_photo"
        }
    }

    var isWorkout: Bool {
        if case .workoutParse = self { return true }
        return false
    }
}

enum JevTierRouter {
    static func decide(
        score: Double?,
        needsUserData: Double?,
        eligibility: JevTierEligibility,
        isChat: Bool
    ) -> JevTier {
        guard let score else { return .strong }
        let chatAllowsOnDevice = !isChat || (needsUserData ?? 1) < 0.20
        if score <= 0.6 {
            if eligibility.gemma && chatAllowsOnDevice { return .onDevice }
            if eligibility.appleIntelligence && chatAllowsOnDevice { return .appleIntelligence }
            if !eligibility.cheapModel.isEmpty { return .cheap }
            return .strong
        }
        if score <= 1.4 {
            if eligibility.appleIntelligence && chatAllowsOnDevice { return .appleIntelligence }
            if !eligibility.cheapModel.isEmpty { return .cheap }
            return .strong
        }
        return .strong
    }

    /// Device support only. The user still has to turn the tier on.
    static var appleIntelligenceDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceAIService.isAvailable
        }
        #endif
        return false
    }

    private static var appleIntelligenceEligible: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return JevRouterSettings.allowAppleIntelligence && OnDeviceAIService.isAvailable
        }
        #endif
        return false
    }

    /// Every cloud-mode AI request that can change model goes through here: text food, workout
    /// parse, Coach (text and image) and photo food. Hosted mode branches off before this.
    ///
    /// Order: images always keep `base` (cloud). A picked on-device model answers the text
    /// requests directly, without the complexity score; when it can't run, `base` answers and
    /// the picker screen shows why. With the picker Off, Jev tier routing decides as before,
    /// and returns `base` when tier routing is disabled.
    static func plan(
        _ request: JevTierRequest,
        base: AIProviderSettings.RequestConfig,
        router: JevRouter = .shared,
        eligibility: (() -> JevTierEligibility)? = nil,
        isEnabled: (() -> Bool)? = nil,
        onDevice: (() -> OnDeviceModelState)? = nil,
        recordFallback: ((OnDeviceFallbackNotice?) -> Void)? = nil
    ) async -> JevTierPlan {
        let isEnabled = isEnabled ?? { JevRouterSettings.isActive(.tierRouting) }
        let onDeviceState = (onDevice ?? { OnDeviceModelState.current })()
        let recordFallback = recordFallback ?? { OnDeviceModelSettings.lastFallback = $0 }
        let basePlan = JevTierPlan(primary: base, strong: base, tier: .strong)

        switch OnDeviceModelSelector.select(onDeviceState, request: request) {
        case .cloudForImage:
            if onDeviceState.choice != .off || isEnabled() {
                let preview = request.text.isEmpty ? request.requestType : request.text
                await router.report(.tierRouting, .localShortcut(label: "image → cloud", llmCallsAvoided: 0), preview: preview)
            }
            return basePlan
        case .onDevice(let tier):
            let primary = config(for: tier, base: base, cheapModel: "")
            await router.report(.tierRouting, .localShortcut(label: "\(tierLabel(tier)) (picked)", llmCallsAvoided: 0), preview: request.text)
            // Base already on the same on-device provider: nothing cheaper to escalate from.
            let routedTier: JevTier = primary.provider == base.provider ? .strong : tier
            return JevTierPlan(primary: primary, strong: base, tier: routedTier, pickedOnDevice: true)
        case .fallBack(let reason):
            recordFallback(OnDeviceFallbackNotice(provider: base.provider.displayName, reason: reason, date: Date()))
            await router.report(.tierRouting, .fellBack(.skipped), preview: request.text)
            return basePlan
        case .router:
            break
        }

        let eligibility = eligibility ?? {
            JevTierEligibility(
                gemma: JevRouterSettings.allowOnDevice && Gemma4LocalModelManager.isCurrentDeviceSelectable,
                appleIntelligence: appleIntelligenceEligible,
                cheapModel: JevRouterSettings.cheapTextModel
            )
        }
        let strong = base
        let flags = eligibility()
        let cheapModel = flags.cheapModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cheapIsDifferent = !cheapModel.isEmpty && cheapModel != base.model && base.provider != .gemma4Local && base.provider != .appleIntelligence
        let cheaperExists = flags.gemma || flags.appleIntelligence || cheapIsDifferent
        guard isEnabled(), cheaperExists else {
            return JevTierPlan(primary: strong, strong: strong, tier: .strong)
        }
        let usable = JevTierEligibility(
            gemma: flags.gemma,
            appleIntelligence: flags.appleIntelligence,
            cheapModel: cheapIsDifferent ? cheapModel : ""
        )
        let outcome = await router.ask(
            .tierRouting,
            cacheKey: "\(request.requestType)|\(JevText.normalize(request.text))",
            preview: request.text
        ) { model in
            TypeSafeRequest(state: .object([
                "request_type": .string(request.requestType),
                "text": .string(request.text)
            ]), model: model, questions: questions(for: request))
        }
        guard case .answered(let response, _, _) = outcome else {
            return JevTierPlan(primary: strong, strong: strong, tier: .strong)
        }
        let score = JevGates.scoreIfConfident(response.answers["complexity"], minConfidence: 0.60)
        let needs = noulValue(response.answers["needs_user_data"])
        let tier = decide(score: score, needsUserData: needs, eligibility: usable, isChat: request.isChat)
        return JevTierPlan(primary: config(for: tier, base: base, cheapModel: usable.cheapModel), strong: strong, tier: tier)
    }

    /// Runs `plan.primary`. When a cheaper or picked on-device tier fails, retries once on
    /// `plan.strong`. If that fails too, rethrows the primary error so the caller's existing
    /// text/image fallback chain runs exactly as before.
    static func run<T>(
        _ plan: JevTierPlan,
        recordFallback: ((OnDeviceFallbackNotice?) -> Void)? = nil,
        _ perform: (AIProviderSettings.RequestConfig) async throws -> T
    ) async throws -> T {
        let recordFallback = recordFallback ?? { OnDeviceModelSettings.lastFallback = $0 }
        do {
            let value = try await perform(plan.primary)
            if plan.pickedOnDevice { recordFallback(nil) }
            return value
        } catch {
            if error is CancellationError { throw error }
            guard plan.tier != .strong else { throw error }
            if plan.pickedOnDevice {
                recordFallback(OnDeviceFallbackNotice(
                    provider: plan.strong.provider.displayName,
                    reason: OnDeviceFallbackNotice.reason(for: error),
                    date: Date()
                ))
            }
            do {
                return try await perform(plan.strong)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The strong retry failed too. The caller's fallback chain starts from the primary error.
            }
            throw error
        }
    }

    private static func tierLabel(_ tier: JevTier) -> String {
        switch tier {
        case .onDevice: "Gemma on-device"
        case .appleIntelligence: "Apple on-device"
        case .cheap: "cheaper model"
        case .strong: "your model"
        }
    }

    private static func questions(for request: JevTierRequest) -> [String: TypeSafeQuestion] {
        let levels = request.isWorkout
            ? [
                "Trivial: one exercise with clear sets and reps",
                "Simple: a few common exercises with clear sets, reps and weights",
                "Moderate: several exercises, abbreviations, misspellings, or a timed activity",
                "Complex: many exercises, vague details, follow-up answers, or corrections"
            ]
            : [
                "Trivial: one common food, a greeting, or a one-line fact",
                "Simple: a few common foods with clear amounts, or a short general question",
                "Moderate: mixed or restaurant dishes, brands, or a question needing some reasoning",
                "Complex: many items, vague amounts, recipes, plans, or advice that depends on the person's history"
            ]
        var questions: [String: TypeSafeQuestion] = [
            "complexity": .score(
                instructions: .string("How much reasoning does answering `text` need?"),
                levels: levels
            )
        ]
        if request.isChat {
            questions["needs_user_data"] = .noul(
                instructions: .string("Answering needs the person's own logged data (weights, food log, workouts, program)."),
                criteria: ("Needs their data", "General knowledge is enough")
            )
        }
        return questions
    }

    private static func noulValue(_ answer: TypeSafeAnswer?) -> Double? {
        guard case .noul(let value) = answer else { return nil }
        return value
    }

    private static func config(
        for tier: JevTier,
        base: AIProviderSettings.RequestConfig,
        cheapModel: String
    ) -> AIProviderSettings.RequestConfig {
        switch tier {
        case .onDevice:
            AIProviderSettings.RequestConfig(
                provider: .gemma4Local,
                model: AIProvider.gemma4Local.textModels.first ?? Gemma4LocalModelManager.modelID,
                baseURL: AIProvider.gemma4Local.baseURL,
                apiKey: nil
            )
        case .appleIntelligence:
            AIProviderSettings.RequestConfig(
                provider: .appleIntelligence,
                model: "System Language Model",
                baseURL: AIProvider.appleIntelligence.baseURL,
                apiKey: nil
            )
        case .cheap:
            AIProviderSettings.RequestConfig(
                provider: base.provider,
                model: cheapModel,
                baseURL: base.baseURL,
                apiKey: base.apiKey
            )
        case .strong:
            base
        }
    }
}
