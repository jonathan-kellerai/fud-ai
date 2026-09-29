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
}

enum JevTierRequest: Sendable {
    case textFood(String)
    case coachChat(String)

    var text: String {
        switch self {
        case .textFood(let text), .coachChat(let text): text
        }
    }

    var isChat: Bool {
        if case .coachChat = self { return true }
        return false
    }

    var requestType: String { isChat ? "coach_chat" : "food_text" }
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

    static func routes(hasImage: Bool, hosted: Bool) -> Bool {
        !hasImage && !hosted
    }

    static func plan(
        _ request: JevTierRequest,
        base: AIProviderSettings.RequestConfig,
        router: JevRouter = .shared,
        eligibility: (() -> JevTierEligibility)? = nil,
        isEnabled: (() -> Bool)? = nil
    ) async -> JevTierPlan {
        let eligibility = eligibility ?? {
            JevTierEligibility(
                gemma: JevRouterSettings.allowOnDevice && Gemma4LocalModelManager.isCurrentDeviceSelectable,
                appleIntelligence: OnDeviceAIService.isAvailable,
                cheapModel: JevRouterSettings.cheapTextModel
            )
        }
        let isEnabled = isEnabled ?? { JevRouterSettings.isActive(.tierRouting) }
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

    private static func questions(for request: JevTierRequest) -> [String: TypeSafeQuestion] {
        var questions: [String: TypeSafeQuestion] = [
            "complexity": .score(
                instructions: .string("How much reasoning does answering `text` need?"),
                levels: [
                    "Trivial: one common food, a greeting, or a one-line fact",
                    "Simple: a few common foods with clear amounts, or a short general question",
                    "Moderate: mixed or restaurant dishes, brands, or a question needing some reasoning",
                    "Complex: many items, vague amounts, recipes, plans, or advice that depends on the person's history"
                ]
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
