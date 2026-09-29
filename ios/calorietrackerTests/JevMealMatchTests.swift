import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct JevMealMatchTests {
    private let credentials = JevCredentials(endpoint: .direct, apiKey: "test-key", model: "jev-latest")

    init() {
        TypeSafeStub.reset()
    }

    @Test func prefilterRanksAndCapsAtEight() {
        let names = [
            "Chicken burrito bowl",
            "Chicken burrito",
            "Chicken bowl",
            "Burrito bowl",
            "Chicken rice bowl",
            "Steak burrito bowl",
            "Chicken salad bowl",
            "Veggie burrito bowl",
            "Grilled chicken",
            "Yogurt 1", "Yogurt 2", "Yogurt 3", "Yogurt 4", "Yogurt 5",
            "Yogurt 6", "Yogurt 7", "Yogurt 8", "Yogurt 9", "Yogurt 10", "Yogurt 11"
        ]
        let pool = names.enumerated().map { index, name in
            item(name, 400 + index)
        }
        let ranked = SavedMealMatcher.prefilter("chicken burrito bowl", pool: pool)
        #expect(ranked.count == 8)
        #expect(ranked.first?.name == "Chicken burrito bowl")
        #expect(!ranked.contains { $0.name == "Grilled chicken" })
        #expect(!ranked.contains { $0.name.hasPrefix("Yogurt") })
    }

    @Test func fillerWordsIgnored() {
        let pool = [item("Oatmeal", 300), item("Pizza", 700)]
        let ranked = SavedMealMatcher.prefilter("i had my usual oatmeal", pool: pool)
        #expect(ranked.first?.name == "Oatmeal")
    }

    @Test func quantityGuardDropsMismatch() async {
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "2 bowls of chili",
            pool: [item("Chili", 280)],
            router: router,
            isEnabled: { true }
        )
        #expect(match == nil)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func multiItemGuard() async {
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "salad and a coke",
            pool: [item("Caesar salad", 320)],
            router: router,
            isEnabled: { true }
        )
        #expect(match == nil)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func exactMatchMakesZeroRequests() async {
        let saved = item("Oatmeal", 300)
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "Oatmeal",
            pool: [saved],
            router: router,
            isEnabled: { true }
        )
        #expect(match?.id == saved.entry.id)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func requestShape() async throws {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "m1", confidence: 0.9, probabilities: ["m1": 0.91, "m2": 0.04, "none": 0.05])) }
        let router = makeRouter()
        _ = await SavedMealMatcher.match(
            "chicken bowl",
            pool: [
                item("Chicken burrito bowl", 640, unit: "bowl", quantity: 1, age: 10),
                item("Chicken rice bowl", 510, unit: "bowl", quantity: 1, age: 20)
            ],
            router: router,
            isEnabled: { true }
        )
        let recorded = try #require(TypeSafeStub.requests.first)
        let body = try #require(recorded.1)
        let raw = String(decoding: body, as: UTF8.self)
        #expect(!raw.contains("640"))
        #expect(!raw.contains("510"))
        #expect(!raw.lowercased().contains("kcal"))
        #expect(!raw.contains("calories"))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        let meal = try #require(questions["meal"] as? [String: Any])
        #expect(meal["type"] as? String == "choice")
        let criteria = try #require(meal["criteria"] as? [String: Any])
        #expect(Set(criteria.keys) == ["m1", "m2", "none"])
        let state = try #require(json["state"] as? [String: Any])
        #expect(state["typed_meal"] as? String == "chicken bowl")
    }

    @Test func confidentAnswerReturnsEntry() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "m1", confidence: 0.91, probabilities: ["m1": 0.9, "m2": 0.05, "none": 0.05])) }
        let first = item("Chicken burrito bowl", 640)
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "chicken bowl",
            pool: [first, item("Chicken rice bowl", 510, age: 50)],
            router: router,
            isEnabled: { true }
        )
        #expect(match?.id == first.entry.id)
    }

    @Test func lowMarginFallsBack() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "m1", confidence: 0.9, probabilities: ["m1": 0.55, "m2": 0.40, "none": 0.05])) }
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "chicken bowl",
            pool: [item("Chicken burrito bowl", 640, age: 10), item("Chicken rice bowl", 510, age: 40)],
            router: router,
            isEnabled: { true }
        )
        #expect(match == nil)
    }

    @Test func noneFallsBack() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "none", confidence: 0.92, probabilities: ["none": 0.9, "m1": 0.06, "m2": 0.04])) }
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "chicken bowl",
            pool: [item("Chicken burrito bowl", 640, age: 10), item("Chicken rice bowl", 510, age: 40)],
            router: router,
            isEnabled: { true }
        )
        #expect(match == nil)
    }

    @Test func sentinelFallsBack() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "m1", confidence: 0, probabilities: [:])) }
        let router = makeRouter()
        let match = await SavedMealMatcher.match(
            "chicken bowl",
            pool: [item("Chicken burrito bowl", 640, age: 10), item("Chicken rice bowl", 510, age: 40)],
            router: router,
            isEnabled: { true }
        )
        #expect(match == nil)
    }

    @Test func timeoutFallsBackWithinBudget() async {
        TypeSafeStub.delay = 2
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "m1", confidence: 0.9, probabilities: ["m1": 0.95, "none": 0.05])) }
        let router = makeRouter()
        let started = Date()
        let match = await SavedMealMatcher.match(
            "chicken bowl",
            pool: [item("Chicken burrito bowl", 640, age: 10), item("Chicken rice bowl", 510, age: 40)],
            router: router,
            isEnabled: { true }
        )
        #expect(match == nil)
        #expect(Date().timeIntervalSince(started) < 1.2)
    }

    @Test func secondIdenticalCallUsesCache() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(choice: "m1", confidence: 0.9, probabilities: ["m1": 0.92, "m2": 0.04, "none": 0.04])) }
        let router = makeRouter()
        let pool = [item("Chicken burrito bowl", 640, age: 5), item("Chicken rice bowl", 510, age: 40)]
        let first = await SavedMealMatcher.match("chicken bowl", pool: pool, router: router, isEnabled: { true })
        let second = await SavedMealMatcher.match("chicken bowl", pool: pool, router: router, isEnabled: { true })
        #expect(first?.name == "Chicken burrito bowl")
        #expect(second?.name == first?.name)
        #expect(TypeSafeStub.requests.count == 1)
    }

    @Test func killSwitchAndNoKeyMakeZeroRequests() async {
        let pool = [item("Chicken burrito bowl", 640), item("Chicken rice bowl", 510)]
        let killed = makeRouter(killSwitch: true)
        let fromKill = await SavedMealMatcher.match("chicken bowl", pool: pool, router: killed, isEnabled: { true })
        let missing = makeRouter(includeCredentials: false)
        let fromMissing = await SavedMealMatcher.match("chicken bowl", pool: pool, router: missing, isEnabled: { true })
        let disabled = await SavedMealMatcher.match("Oatmeal", pool: [item("Oatmeal", 300)], router: killed, isEnabled: { false })
        #expect(fromKill == nil)
        #expect(fromMissing == nil)
        #expect(disabled == nil)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func savedEntryMappingMatchesRecentsReview() {
        let option = ServingUnitOption(unit: "bowl", gramsPerUnit: 240, quantity: 1)
        let entry = FoodEntry(
            name: "Chicken burrito bowl",
            calories: 640,
            protein: 42,
            carbs: 58,
            fat: 22,
            emoji: "🌯",
            source: .textInput,
            sugar: 4,
            fiber: 8,
            supplementalNutrients: ["creatine": 5.0],
            sodium: 900,
            servingSizeGrams: 450,
            servingUnitOptions: [option],
            selectedServingUnit: "bowl",
            selectedServingQuantity: 1
        )
        let analysis = GeminiService.FoodAnalysis(savedEntry: entry)
        #expect(analysis.name == entry.name)
        #expect(analysis.calories == entry.calories)
        #expect(analysis.protein == entry.protein)
        #expect(analysis.carbs == entry.carbs)
        #expect(analysis.fat == entry.fat)
        #expect(analysis.sugar == entry.sugar)
        #expect(analysis.fiber == entry.fiber)
        #expect(analysis.sodium == entry.sodium)
        #expect(analysis.supplementalNutrients == entry.supplementalNutrients)
        #expect(analysis.servingSizeGrams == entry.reviewServingReference)
        #expect(analysis.servingUnitOptions == entry.reviewServingUnitOptions)
        #expect(analysis.selectedServingUnit == entry.reviewSelectedServingUnit)
        #expect(analysis.selectedServingQuantity == entry.reviewSelectedServingQuantity)
        #expect(analysis.emoji == entry.emoji)
        #expect(analysis.progressiveMeal == entry.progressiveMeal)
        #expect(analysis.ingredients == entry.ingredients)
    }

    private func item(
        _ name: String,
        _ calories: Int,
        favorite: Bool = false,
        frequency: Int = 1,
        unit: String? = nil,
        quantity: Double? = nil,
        age: TimeInterval = 0
    ) -> SavedMealPoolItem {
        SavedMealPoolItem(
            entry: FoodEntry(
                name: name,
                calories: calories,
                protein: 20,
                carbs: 30,
                fat: 10,
                timestamp: Date().addingTimeInterval(-age),
                source: .textInput,
                selectedServingUnit: unit,
                selectedServingQuantity: quantity
            ),
            isFavorite: favorite,
            frequency: frequency
        )
    }

    private func makeRouter(includeCredentials: Bool = true, killSwitch: Bool = false) -> JevRouter {
        let resolved: JevCredentials? = includeCredentials ? credentials : nil
        return JevRouter(
            credentials: { resolved },
            isActive: { _ in true },
            killSwitch: { killSwitch },
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
        let defaults = UserDefaults(suiteName: "jev.meal.tests.\(name)")!
        defaults.removePersistentDomain(forName: "jev.meal.tests.\(name)")
        return defaults
    }

    private static func choiceJSON(choice: String, confidence: Double, probabilities: [String: Double]) -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": [
                "meal": [
                    "type": "choice",
                    "choice": choice,
                    "confidence": confidence,
                    "probabilities": probabilities
                ]
            ],
            "usage": ["input_tokens": 24, "output_tokens": 3]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }
}
