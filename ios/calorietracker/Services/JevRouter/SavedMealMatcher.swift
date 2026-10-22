import Foundation

struct SavedMatchBanner: Equatable, Sendable {
    var entryName: String
}

struct SavedMatchContext: Equatable {
    var entryName: String
    var originalDescription: String
}

struct SavedMealPoolItem {
    var entry: FoodEntry
    var isFavorite: Bool
    var frequency: Int
}

enum SavedMealMatcher {
    private static let fillers: Set<String> = [
        "i", "had", "ate", "just", "my", "usual", "the", "a", "an", "some", "for",
        "today", "breakfast", "lunch", "dinner", "snack", "log", "please"
    ]
    private static let quantityWords: Set<String> = [
        "half", "double", "two", "three", "couple", "large", "small", "extra", "x2", "2x"
    ]
    private static let connectors = [" and ", ",", "+", "&", " with "]
    private static let scoreFloor = 0.35
    private static let maxCandidates = 8

    static func match(_ description: String, store: FoodStore, now: Date = .now) async -> FoodEntry? {
        await match(
            description,
            pool: pool(from: store, now: now),
            router: .shared,
            isEnabled: { JevRouterSettings.isActive(.mealMatch) }
        )
    }

    static func pool(from store: FoodStore, now: Date = .now) -> [SavedMealPoolItem] {
        let frequent = store.frequentGroups(days: 90, now: now)
        var frequency: [String: Int] = [:]
        for group in frequent {
            frequency[dedupeKey(group.template)] = group.count
        }
        var merged: [String: SavedMealPoolItem] = [:]
        func consider(_ entry: FoodEntry, favorite: Bool) {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, entry.calories > 0 else { return }
            let key = "\(name.lowercased())|\(entry.calories)"
            let item = SavedMealPoolItem(
                entry: entry,
                isFavorite: favorite,
                frequency: frequency[key] ?? 0
            )
            if let existing = merged[key] {
                merged[key] = preferred(existing, item)
            } else {
                merged[key] = item
            }
        }
        for entry in store.favorites {
            consider(entry, favorite: true)
        }
        for group in frequent {
            consider(group.template, favorite: false)
        }
        for entry in store.recentEntries(days: 30, now: now) {
            consider(entry, favorite: false)
        }
        return Array(merged.values)
    }

    /// Top matches before quantity and multi-item guards. Empty when the input itself is rejected.
    static func prefilter(_ description: String, pool: [SavedMealPoolItem]) -> [FoodEntry] {
        guard let matchingText = matchingText(for: description) else { return [] }
        return scored(matchingText, pool: pool).prefix(maxCandidates).map(\.entry)
    }

    static func match(
        _ description: String,
        pool: [SavedMealPoolItem],
        router: JevRouter,
        isEnabled: () -> Bool
    ) async -> FoodEntry? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled() else { return nil }
        guard let matchingText = matchingText(for: trimmed) else {
            await router.report(.mealMatch, .fellBack(.guardRejected), preview: trimmed)
            return nil
        }
        let ranked = scored(matchingText, pool: pool)
        guard !ranked.isEmpty else {
            await router.report(.mealMatch, .fellBack(.noCandidates), preview: trimmed)
            return nil
        }
        let top = Array(ranked.prefix(maxCandidates))
        let survivors = top.filter { item in
            !quantityMismatch(input: matchingText, name: item.entry.name)
                && !connectorMismatch(input: trimmed, name: item.entry.name)
        }
        guard !survivors.isEmpty else {
            await router.report(.mealMatch, .fellBack(.guardRejected), preview: trimmed)
            return nil
        }
        if survivors.count == 1, JevText.normalize(survivors[0].entry.name) == matchingText {
            let entry = survivors[0].entry
            await router.report(
                .mealMatch,
                .localShortcut(label: entry.name, llmCallsAvoided: 1),
                preview: trimmed
            )
            return entry
        }

        let entries = survivors.map(\.entry)
        var criteria: [(key: String, description: String?)] = []
        var keys: [String: FoodEntry] = [:]
        for (index, entry) in entries.enumerated() {
            let key = "m\(index + 1)"
            keys[key] = entry
            criteria.append((key, criterion(for: entry)))
        }
        criteria.append(("none", "None of these saved meals is the same food"))
        let fingerprint = entries.enumerated().map { index, entry in
            "m\(index + 1)|\(entry.name)|\(entry.calories)"
        }.joined(separator: ";")
        let cacheKey = matchingText + "|" + JevText.sha256(fingerprint)
        let state = TypeSafeJSON.object(["typed_meal": .string(trimmed)])
        let questions: [String: TypeSafeQuestion] = [
            "meal": .choice(
                instructions: .object([
                    "task": .string("Which saved meal is the same food as `typed_meal`? Choose none if it is a different food, a different variety or brand, several foods, or clearly a different amount."),
                    "typed_meal": .string(trimmed)
                ]),
                criteria: criteria
            )
        ]
        let outcome = await router.ask(.mealMatch, cacheKey: cacheKey, preview: trimmed) { model in
            TypeSafeRequest(state: state, model: model, questions: questions)
        }
        guard case .answered(let response, _, let latency) = outcome else {
            await router.report(.mealMatch, .fellBack(.skipped), preview: trimmed)
            return nil
        }
        guard let key = JevGates.acceptChoice(
            response.answers["meal"],
            minP: 0.80,
            minConfidence: 0.60,
            minMargin: 0.30
        ), let entry = keys[key] else {
            await router.report(
                .mealMatch,
                .fellBack(fallbackReason(response.answers["meal"])),
                preview: trimmed,
                latencyMs: latency,
                model: response.model
            )
            return nil
        }
        let confidence = choiceConfidence(response.answers["meal"])
        await router.report(
            .mealMatch,
            .accepted(label: entry.name, confidence: confidence, llmCallsAvoided: 1),
            preview: trimmed,
            latencyMs: latency,
            model: response.model
        )
        return entry
    }

    private static func matchingText(for description: String) -> String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = JevText.normalize(trimmed)
        if normalized.isEmpty || trimmed.count > 200 || JevText.tokens(trimmed).count > 12 {
            return nil
        }
        let stripped = stripFillers(normalized)
        return stripped.isEmpty ? nil : stripped
    }

    private static func stripFillers(_ normalized: String) -> String {
        normalized
            .split(separator: " ")
            .map(String.init)
            .filter { !fillers.contains($0) }
            .joined(separator: " ")
    }

    private static func scored(_ matchingText: String, pool: [SavedMealPoolItem]) -> [SavedMealPoolItem] {
        var rows: [(item: SavedMealPoolItem, score: Double)] = []
        for item in pool {
            let name = item.entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.entry.calories > 0 else { continue }
            let score = max(JevText.tokenDice(matchingText, name), JevText.trigramJaccard(matchingText, name))
            if score >= scoreFloor {
                rows.append((item, score))
            }
        }
        rows.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.isFavorite != rhs.item.isFavorite { return lhs.item.isFavorite }
            if lhs.item.frequency != rhs.item.frequency { return lhs.item.frequency > rhs.item.frequency }
            if lhs.item.entry.timestamp != rhs.item.entry.timestamp {
                return lhs.item.entry.timestamp > rhs.item.entry.timestamp
            }
            return lhs.item.entry.name < rhs.item.entry.name
        }
        return rows.map(\.item)
    }

    private static func quantityMismatch(input: String, name: String) -> Bool {
        let inputTokens = Set(JevText.tokens(input))
        let nameTokens = Set(JevText.tokens(name))
        for token in inputTokens where !nameTokens.contains(token) {
            if quantityWords.contains(token) { return true }
            if token.contains(where: \.isNumber) { return true }
        }
        return false
    }

    private static func connectorMismatch(input: String, name: String) -> Bool {
        let input = input.lowercased()
        let name = name.lowercased()
        for connector in connectors where input.contains(connector) && !name.contains(connector) {
            return true
        }
        return false
    }

    private static func criterion(for entry: FoodEntry) -> String {
        guard let quantity = entry.selectedServingQuantity,
              let unit = entry.selectedServingUnit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !unit.isEmpty else {
            return entry.name
        }
        return "\(entry.name) (\(quantityText(quantity)) \(unit))"
    }

    private static func quantityText(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%g", value)
    }

    private static func dedupeKey(_ entry: FoodEntry) -> String {
        "\(entry.name.lowercased())|\(entry.calories)"
    }

    private static func preferred(_ current: SavedMealPoolItem, _ incoming: SavedMealPoolItem) -> SavedMealPoolItem {
        if current.isFavorite != incoming.isFavorite { return current.isFavorite ? current : incoming }
        if current.frequency != incoming.frequency { return current.frequency >= incoming.frequency ? current : incoming }
        if incoming.entry.timestamp > current.entry.timestamp && !current.isFavorite {
            var kept = incoming
            kept.isFavorite = current.isFavorite
            kept.frequency = max(current.frequency, incoming.frequency)
            return kept
        }
        var kept = current
        kept.frequency = max(current.frequency, incoming.frequency)
        kept.isFavorite = current.isFavorite || incoming.isFavorite
        return kept
    }

    private static func fallbackReason(_ answer: TypeSafeAnswer?) -> JevFallback {
        guard case .choice(let choice, let confidence, let probabilities) = answer else { return .lowConfidence }
        if choice == "none" || probabilities.isEmpty || confidence == 0 { return .none }
        return .lowConfidence
    }

    private static func choiceConfidence(_ answer: TypeSafeAnswer?) -> Double? {
        guard case .choice(_, let confidence, _) = answer else { return nil }
        return confidence
    }
}

extension GeminiService.FoodAnalysis {
    init(savedEntry entry: FoodEntry) {
        self.init(
            name: entry.name,
            calories: entry.calories,
            protein: entry.protein,
            carbs: entry.carbs,
            fat: entry.fat,
            servingSizeGrams: entry.reviewServingReference,
            emoji: entry.emoji,
            sugar: entry.sugar,
            addedSugar: entry.addedSugar,
            fiber: entry.fiber,
            saturatedFat: entry.saturatedFat,
            monounsaturatedFat: entry.monounsaturatedFat,
            polyunsaturatedFat: entry.polyunsaturatedFat,
            cholesterol: entry.cholesterol,
            caffeine: entry.caffeine,
            supplementalNutrients: entry.supplementalNutrients,
            sodium: entry.sodium,
            potassium: entry.potassium,
            transFat: entry.transFat,
            calcium: entry.calcium,
            iron: entry.iron,
            magnesium: entry.magnesium,
            zinc: entry.zinc,
            vitaminA: entry.vitaminA,
            vitaminC: entry.vitaminC,
            vitaminD: entry.vitaminD,
            vitaminB12: entry.vitaminB12,
            vitaminE: entry.vitaminE,
            vitaminK: entry.vitaminK,
            folate: entry.folate,
            omega3: entry.omega3,
            servingUnitOptions: entry.reviewServingUnitOptions,
            selectedServingUnit: entry.reviewSelectedServingUnit,
            selectedServingQuantity: entry.reviewSelectedServingQuantity,
            servingSizeIsKnown: entry.hasKnownServingSize,
            progressiveMeal: entry.progressiveMeal,
            ingredients: entry.ingredients,
            productMetadata: entry.productMetadata
        )
    }
}
