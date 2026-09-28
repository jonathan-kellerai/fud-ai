import Foundation

struct EstimateCheckItem: Equatable, Sendable {
    var name: String
    var grams: Double
}

struct EstimateCheckInput: Equatable, Sendable {
    var name: String
    var calories: Int
    var servingSizeGrams: Double
    var servingSizeIsKnown: Bool
    var items: [EstimateCheckItem]
    var userNote: String?

    init(
        name: String,
        calories: Int,
        servingSizeGrams: Double,
        servingSizeIsKnown: Bool,
        items: [EstimateCheckItem],
        userNote: String?
    ) {
        self.name = name
        self.calories = calories
        self.servingSizeGrams = servingSizeGrams
        self.servingSizeIsKnown = servingSizeIsKnown
        self.items = items
        self.userNote = userNote
    }

    init(analysis: GeminiService.FoodAnalysis, userNote: String?) {
        self.init(
            name: analysis.name,
            calories: analysis.calories,
            servingSizeGrams: analysis.servingSizeGrams,
            servingSizeIsKnown: analysis.servingSizeIsKnown,
            items: analysis.ingredients.prefix(20).map { EstimateCheckItem(name: $0.name, grams: $0.grams) },
            userNote: userNote
        )
    }
}

enum EstimateDirection: Equatable, Sendable {
    case tooLow
    case tooHigh

    var phrase: String { self == .tooLow ? "low" : "high" }
}

enum EstimateCheckOutcome: Equatable, Sendable {
    case ok(model: String)
    case looksOff(direction: EstimateDirection, expectedBandLabel: String, model: String)
    case unavailable(TypeSafeError)
}

enum EstimateCheckMode: Equatable, Sendable {
    case off
    case live(EstimateCheckInput)
    case preview(EstimateCheckOutcome)
}

enum TypeSafeEstimateChecker {
    enum Thresholds {
        static let plausibleCutoff = 0.30
        static let neighborProbabilityCeiling = 0.25
        static let confidenceFloor = 0.5
        static let mismatchDistance = 2
        static let maxItems = 20
        static let maxNoteLength = 500
    }

    static let calorieBandKeys = ["band_0", "band_1", "band_2", "band_3", "band_4", "band_5"]
    static let densityKeys = ["very_light", "light", "moderate", "rich", "very_rich"]

    static let calorieBandCriteria: [(key: String, description: String)] = [
        ("band_0", "Under 150 kcal: a drink, a piece of fruit, or a small snack"),
        ("band_1", "150 to 400 kcal: a large snack or a light meal"),
        ("band_2", "400 to 700 kcal: a typical single-person meal"),
        ("band_3", "700 to 1,000 kcal: a hearty or large meal"),
        ("band_4", "1,000 to 1,500 kcal: a very large or restaurant-size meal"),
        ("band_5", "Over 1,500 kcal: a feast, a shared platter, or several meals' worth"),
    ]

    static let calorieBandLabels = [
        "Under 150 kcal (a drink, a piece of fruit, or a small snack)",
        "150–400 kcal (a large snack or a light meal)",
        "400–700 kcal (a typical single-person meal)",
        "700–1,000 kcal (a hearty or large meal)",
        "1,000–1,500 kcal (a very large or restaurant-size meal)",
        "Over 1,500 kcal (a feast, a shared platter, or several meals' worth)",
    ]

    static let densityCriteria: [(key: String, description: String)] = [
        ("very_light", "Mostly water or vegetables: salad, broth, fruit, plain vegetables"),
        ("light", "Lean and moist: grilled lean meat or fish, cooked grains, yogurt, soup"),
        ("moderate", "Mixed dishes: sandwiches, pasta with sauce, rice bowls, pizza"),
        ("rich", "Fried foods, pastries, creamy or cheese-heavy dishes, sweets"),
        ("very_rich", "Mostly fat or sugar: nuts, oils, butter, chocolate, chips"),
    ]

    static func calorieBand(for kcal: Int) -> Int {
        if kcal < 150 { return 0 }
        if kcal < 400 { return 1 }
        if kcal < 700 { return 2 }
        if kcal < 1_000 { return 3 }
        if kcal < 1_500 { return 4 }
        return 5
    }

    /// Index 0...4 for kcal per 100 g. Grams must be greater than zero.
    static func densityBand(kcal: Int, grams: Double) -> Int {
        let perHundred = Double(kcal) / grams * 100
        if perHundred < 60 { return 0 }
        if perHundred < 150 { return 1 }
        if perHundred < 250 { return 2 }
        if perHundred < 400 { return 3 }
        return 4
    }

    static func makeRequest(for input: EstimateCheckInput, model: String) -> TypeSafeRequest {
        var meal: [String: TypeSafeJSON] = [
            "name": .string(input.name),
            "items": .array(itemObjects(for: input)),
            "total_portion": .string(portionPhrase(for: input)),
        ]
        if let note = trimmedNote(input.userNote) {
            meal["user_note"] = .string(note)
        }

        var questions: [String: TypeSafeQuestion] = [
            "plausible": .noul(
                instructions: .object([
                    "estimate": .string("about \(input.calories) kcal"),
                    "question": .string("Is `estimate` a believable calorie total for everything in the meal, at the portion sizes given?"),
                ]),
                criteria: (
                    true: "The calorie total is in the right ballpark for this food and amount",
                    false: "The calorie total is clearly too high or too low for this food and amount"
                )
            ),
            "calorie_band": .choice(
                instructions: .string("Roughly how many calories does the whole meal contain, at the portion sizes given?"),
                criteria: calorieBandCriteria.map { (key: $0.key, description: Optional($0.description)) }
            ),
        ]
        if includesDensity(input) {
            questions["density"] = .choice(
                instructions: .string("How calorie-dense is this food, bite for bite?"),
                criteria: densityCriteria.map { (key: $0.key, description: Optional($0.description)) }
            )
        }

        return TypeSafeRequest(
            state: .object(["meal": .object(meal)]),
            model: model,
            questions: questions
        )
    }

    static func verdict(for input: EstimateCheckInput, response: TypeSafeResponse) -> EstimateCheckOutcome {
        guard case .noul(let plausible) = response.answers["plausible"] else {
            return .unavailable(.invalidResponse)
        }
        guard case .choice(let bandChoice, let bandConfidence, let bandProbabilities) = response.answers["calorie_band"],
              let bandIndex = calorieBandKeys.firstIndex(of: bandChoice) else {
            return .unavailable(.invalidResponse)
        }

        let estimateBand = calorieBand(for: input.calories)
        let neighbor = neighborProbability(around: estimateBand, probabilities: bandProbabilities)
        let bandMismatch = abs(bandIndex - estimateBand) >= Thresholds.mismatchDistance
            && neighbor < Thresholds.neighborProbabilityCeiling
            && bandConfidence >= Thresholds.confidenceFloor

        var densityMismatch = false
        var densityDirection: EstimateDirection = .tooHigh
        if includesDensity(input) {
            guard case .choice(let densityChoice, let densityConfidence, _) = response.answers["density"],
                  let densityIndex = densityKeys.firstIndex(of: densityChoice) else {
                return .unavailable(.invalidResponse)
            }
            let estimateDensity = densityBand(kcal: input.calories, grams: input.servingSizeGrams)
            densityMismatch = abs(densityIndex - estimateDensity) >= Thresholds.mismatchDistance
                && densityConfidence >= Thresholds.confidenceFloor
            densityDirection = densityIndex > estimateDensity ? .tooLow : .tooHigh
        }

        guard plausible < Thresholds.plausibleCutoff, bandMismatch || densityMismatch else {
            return .ok(model: response.model)
        }
        let direction: EstimateDirection
        if bandMismatch {
            direction = bandIndex > estimateBand ? .tooLow : .tooHigh
        } else {
            direction = densityDirection
        }
        let label = calorieBandLabels[bandIndex]
        return .looksOff(direction: direction, expectedBandLabel: label, model: response.model)
    }

    static func check(
        _ input: EstimateCheckInput,
        client: TypeSafeClient,
        model: String
    ) async -> EstimateCheckOutcome {
        do {
            let response = try await client.systemOne(makeRequest(for: input, model: model))
            return verdict(for: input, response: response)
        } catch is CancellationError {
            return .unavailable(.network)
        } catch let error as TypeSafeError {
            return .unavailable(error)
        } catch {
            return .unavailable(.network)
        }
    }

    static func liveCheck(_ input: EstimateCheckInput) async -> EstimateCheckOutcome? {
        guard TypeSafeSettings.isConfigured || JevRouterSettings.killSwitch else { return nil }
        let outcome = await JevRouter.shared.ask(
            .estimateCheck,
            cacheKey: cacheKey(for: input),
            preview: input.name,
            policy: JevCallPolicy.standard(for: .estimateCheck)
        ) { model in
            makeRequest(for: input, model: model)
        }
        switch outcome {
        case .answered(let response, _, let latency):
            let verdict = verdict(for: input, response: response)
            let label: String
            switch verdict {
            case .ok: label = "ok"
            case .looksOff(_, let band, _): label = "looksOff:\(band)"
            case .unavailable: label = "unavailable"
            }
            await JevRouter.shared.report(
                .estimateCheck,
                .accepted(label: label, confidence: nil, llmCallsAvoided: 0),
                preview: input.name,
                latencyMs: latency,
                model: response.model
            )
            return verdict
        case .skipped:
            return nil
        }
    }

    static func cacheKey(for input: EstimateCheckInput) -> String {
        let items = input.items.map { "\($0.name)|\($0.grams)" }.joined(separator: ",")
        return JevText.normalize("\(input.name)|\(input.calories)|\(input.servingSizeGrams)|\(items)")
    }

    static func includesDensity(_ input: EstimateCheckInput) -> Bool {
        input.servingSizeIsKnown && input.servingSizeGrams > 0
    }

    private static func itemObjects(for input: EstimateCheckInput) -> [TypeSafeJSON] {
        let source: [EstimateCheckItem]
        if input.items.isEmpty {
            source = [EstimateCheckItem(name: input.name, grams: input.servingSizeGrams)]
        } else {
            source = Array(input.items.prefix(Thresholds.maxItems))
        }
        return source.map { item in
            .object([
                "name": .string(item.name),
                "portion": .string(gramPhrase(item.grams)),
            ])
        }
    }

    private static func portionPhrase(for input: EstimateCheckInput) -> String {
        guard input.servingSizeIsKnown else { return "one serving (weight unknown)" }
        let grams = input.servingSizeGrams
        let size: String
        if grams < 100 {
            size = "a small snack-size amount"
        } else if grams < 250 {
            size = "a small plate or bowl"
        } else if grams < 450 {
            size = "a regular plate"
        } else if grams < 700 {
            size = "a large plate"
        } else {
            size = "a very large or shared portion"
        }
        return "about \(gramAmount(grams)) g (\(size))"
    }

    private static func gramPhrase(_ grams: Double) -> String {
        "\(gramAmount(grams)) g"
    }

    private static func gramAmount(_ grams: Double) -> String {
        if abs(grams.rounded() - grams) < 0.05 {
            return String(Int(grams.rounded()))
        }
        return String(format: "%.1f", grams)
    }

    private static func trimmedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Thresholds.maxNoteLength))
    }

    private static func neighborProbability(around band: Int, probabilities: [String: Double]) -> Double {
        (band - 1...band + 1).reduce(0) { sum, index in
            guard calorieBandKeys.indices.contains(index) else { return sum }
            return sum + (probabilities[calorieBandKeys[index]] ?? 0)
        }
    }
}
