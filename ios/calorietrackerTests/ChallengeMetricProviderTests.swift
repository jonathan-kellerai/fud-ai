import Foundation
import Testing
@testable import calorietracker

/// The providers hand the engine the owners' own daily totals, never a second calculation.
@MainActor
struct ChallengeMetricProviderTests {
    private let calendar = Calendar.current
    private let now = Date()

    private func freshDefaults() -> UserDefaults {
        let suite = "challenge-providers-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func noon(daysAgo: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func challenge(_ metric: ChallengeMetric, kind: ChallengeKind = .total(10_000)) -> Challenge {
        Challenge(
            id: UUID(),
            title: "Provider",
            kind: kind,
            metric: metric,
            startDay: ChallengeDay(noon(daysAgo: 3), calendar: calendar),
            durationDays: 30,
            graceDays: 2,
            rewards: [],
            stake: nil,
            reminder: .standard,
            quickAddChips: [],
            createdAt: now,
            endedEarlyAt: nil
        )
    }

    private func seededStores() -> (FoodStore, WaterStore) {
        let defaults = freshDefaults()
        let food = FoodStore(observesExternalChanges: false, defaults: defaults)
        let water = WaterStore(defaults: defaults)
        let meals: [(Int, Int, Double)] = [(3, 520, 41), (3, 300, 12.5), (1, 880, 63), (0, 410, 35)]
        for (daysAgo, calories, protein) in meals {
            _ = food.addEntry(FoodEntry(
                name: "Meal", calories: calories, protein: protein, carbs: 10, fat: 5,
                timestamp: noon(daysAgo: daysAgo), emoji: "🍽️", source: .manual, mealType: .lunch
            ))
        }
        _ = water.add(milliliters: 750, on: noon(daysAgo: 2))
        _ = water.add(milliliters: 1_250, on: noon(daysAgo: 2))
        _ = water.add(milliliters: 500, on: noon(daysAgo: 0))
        return (food, water)
    }

    @Test func caloriesEqualFoodStoreForEachDay() {
        let (food, water) = seededStores()
        let values = ChallengeMetricProviders.loggedValues(
            for: challenge(.calories), foodStore: food, waterStore: water, now: now, calendar: calendar
        )
        for daysAgo in 0...3 {
            let date = noon(daysAgo: daysAgo)
            let expected = Double(food.calories(for: date))
            #expect(values[ChallengeDay(date, calendar: calendar)] == (expected > 0 ? expected : nil))
        }
        #expect(values.count == 3)
    }

    @Test func proteinEqualsFoodStoreForEachDay() {
        let (food, water) = seededStores()
        let values = ChallengeMetricProviders.loggedValues(
            for: challenge(.protein), foodStore: food, waterStore: water, now: now, calendar: calendar
        )
        for daysAgo in [0, 1, 3] {
            let date = noon(daysAgo: daysAgo)
            #expect(values[ChallengeDay(date, calendar: calendar)] == food.protein(for: date))
        }
        #expect(values[ChallengeDay(noon(daysAgo: 2), calendar: calendar)] == nil)
    }

    @Test func waterEqualsWaterStoreForEachDay() {
        let (food, water) = seededStores()
        let values = ChallengeMetricProviders.loggedValues(
            for: challenge(.waterAppLog), foodStore: food, waterStore: water, now: now, calendar: calendar
        )
        #expect(values[ChallengeDay(noon(daysAgo: 2), calendar: calendar)] == Double(water.total(on: noon(daysAgo: 2))))
        #expect(values[ChallengeDay(noon(daysAgo: 2), calendar: calendar)] == 2_000)
        #expect(values[ChallengeDay(noon(daysAgo: 0), calendar: calendar)] == 500)
        #expect(values.count == 2)
    }

    @Test func manualAndStepMetricsAreNotReadFromTheLogs() {
        let (food, water) = seededStores()
        let custom = ChallengeMetricProviders.loggedValues(
            for: challenge(.custom(name: "Swings", unit: "reps")), foodStore: food, waterStore: water, now: now, calendar: calendar
        )
        let steps = ChallengeMetricProviders.loggedValues(
            for: challenge(.steps), foodStore: food, waterStore: water, now: now, calendar: calendar
        )
        #expect(custom.isEmpty)
        #expect(steps.isEmpty)
    }

    @Test func creatingOverExistingLogsScoresThemAtOnce() throws {
        let (food, water) = seededStores()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("challenge-providers-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("challenges.v1.json")
        let store = ChallengeStore(fileURL: url)
        let hydrate = challenge(.waterAppLog, kind: .dailyHabit(.atLeast(2_000)))
        let eat = challenge(.calories, kind: .total(50_000))

        try ChallengeMetricProviders.create(hydrate, in: store, foodStore: food, waterStore: water, now: now)
        try ChallengeMetricProviders.create(eat, in: store, foodStore: food, waterStore: water, now: now)

        let hydrateProgress = try #require(store.progress(for: hydrate.id))
        #expect(hydrateProgress.status != .noData)
        #expect(hydrateProgress.hitDays == 1)
        #expect(store.autoAvailability[eat.id] == .available)
        #expect(store.dailyValues(for: eat).values.reduce(0, +) == 2_110)
    }

    @Test func creatingAnInvalidChallengeStillThrows() {
        let (food, water) = seededStores()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("challenge-providers-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("challenges.v1.json")
        let store = ChallengeStore(fileURL: url)
        var blank = challenge(.waterAppLog, kind: .dailyHabit(.atLeast(2_000)))
        blank.title = "   "
        let at = now
        #expect(throws: ChallengeStoreError.invalidChallenge) {
            try ChallengeMetricProviders.create(blank, in: store, foodStore: food, waterStore: water, now: at)
        }
        #expect(store.challenges.isEmpty)
    }

    @Test func noReadableStepsMeansUnavailableNotZero() {
        // Denied Health access returns no samples, never a zero.
        #expect(ChallengeMetricProviders.stepDays([:], calendar: calendar) == nil)
    }

    @Test func readableStepDaysMapToChallengeDays() throws {
        let byDate = [
            calendar.startOfDay(for: noon(daysAgo: 2)): 8_400,
            calendar.startOfDay(for: noon(daysAgo: 0)): 1_250,
        ]
        let values = try #require(ChallengeMetricProviders.stepDays(byDate, calendar: calendar))
        #expect(values[ChallengeDay(noon(daysAgo: 2), calendar: calendar)] == 8_400)
        #expect(values[ChallengeDay(noon(daysAgo: 0), calendar: calendar)] == 1_250)
        #expect(values[ChallengeDay(noon(daysAgo: 1), calendar: calendar)] == nil)
        #expect(values.count == 2)
    }

    @Test func unreadableStepsLeaveAtMostChallengesUnscored() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("challenge-providers-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("challenges.v1.json")
        let store = ChallengeStore(fileURL: url)
        let sitLess = challenge(.steps, kind: .dailyHabit(.atMost(20_000)))
        try store.create(sitLess, now: now)

        ChallengeMetricProviders.setSteps(
            ChallengeMetricProviders.stepDays([:], calendar: calendar), for: sitLess.id, in: store, now: now
        )
        #expect(store.autoAvailability[sitLess.id] == .unavailable)
        #expect(store.progress(for: sitLess.id)?.status == .noData)
        #expect(store.rewards(for: sitLess.id).isEmpty)

        let readable = [calendar.startOfDay(for: noon(daysAgo: 0)): 4_000]
        ChallengeMetricProviders.setSteps(
            ChallengeMetricProviders.stepDays(readable, calendar: calendar), for: sitLess.id, in: store, now: now
        )
        #expect(store.autoAvailability[sitLess.id] == .available)
        #expect(store.dailyValues(for: sitLess)[ChallengeDay(now, calendar: calendar)] == 4_000)
    }

    @Test func refreshLoggedFeedsTheStore() throws {
        let (food, water) = seededStores()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("challenge-providers-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("challenges.v1.json")
        let store = ChallengeStore(fileURL: url)
        let water3L = challenge(.waterAppLog, kind: .dailyHabit(.atLeast(2_000)))
        try store.create(water3L, now: now)
        #expect(store.progress(for: water3L.id)?.status == .noData)
        ChallengeMetricProviders.refreshLogged(store, foodStore: food, waterStore: water, now: now)
        let progress = try #require(store.progress(for: water3L.id))
        #expect(progress.status == .onTrack)
        #expect(progress.hitDays == 1)
    }
}
