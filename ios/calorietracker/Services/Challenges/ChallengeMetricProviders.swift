import Foundation

/// MainActor adapters from the owning stores to plain per-day values for the
/// challenge engine. No nutrition, water or step maths lives here: each value
/// is the owner's own daily total (`FoodStore.calories(for:)`,
/// `protein(for:)`, `WaterStore.total(on:)`, `HealthKitManager.fetchReadableStepsByDay`).
///
/// Time zones: days are bucketed in `Calendar.current` at evaluation time, the
/// same as Progress and Home, so travelling re-buckets every source the same
/// way. Per-challenge zones would need calendar-aware owner queries (deferred).
/// Steps have no change observer; they refresh when the app becomes active and
/// when Challenges screens open.
enum ChallengeMetricProviders {
    /// Food and water values for one challenge, from its start through today.
    /// Days with nothing logged are left out, so `.atMost` never scores them as hits.
    static func loggedValues(
        for challenge: Challenge,
        foodStore: FoodStore,
        waterStore: WaterStore,
        now: Date,
        calendar: Calendar = .current
    ) -> [ChallengeDay: Double] {
        var values: [ChallengeDay: Double] = [:]
        for day in days(of: challenge, through: now, calendar: calendar) {
            guard let date = noon(of: day, calendar: calendar) else { continue }
            let value: Double
            switch challenge.metric {
            case .calories:
                value = Double(foodStore.calories(for: date))
            case .protein:
                value = foodStore.protein(for: date)
            case .waterAppLog:
                value = Double(waterStore.total(on: date))
            case .steps, .custom:
                continue
            }
            if value > 0 { values[day] = value }
        }
        return values
    }

    /// Daily steps for one challenge, or nil when Health can't be read.
    static func stepValues(
        for challenge: Challenge,
        healthKit: HealthKitManager,
        now: Date,
        calendar: Calendar = .current
    ) async -> [ChallengeDay: Double]? {
        guard UserDefaults.standard.bool(forKey: "healthKitEnabled") else { return nil }
        let window = days(of: challenge, through: now, calendar: calendar)
        guard let first = window.first, let last = window.last,
              let start = noon(of: first, calendar: calendar),
              let end = noon(of: last, calendar: calendar),
              let byDate = await healthKit.fetchReadableStepsByDay(from: start, through: end) else {
            return nil
        }
        return stepDays(byDate, calendar: calendar)
    }

    /// Readable daily steps keyed by challenge day. Nil when no day has samples:
    /// denied access looks exactly like that, and must never score as zero steps.
    static func stepDays(_ byDate: [Date: Int], calendar: Calendar = .current) -> [ChallengeDay: Double]? {
        guard !byDate.isEmpty else { return nil }
        var values: [ChallengeDay: Double] = [:]
        for (date, steps) in byDate {
            values[ChallengeDay(date, calendar: calendar)] = Double(steps)
        }
        return values
    }

    /// Hands step values to the store; nil (unreadable) becomes `.unavailable`.
    static func setSteps(_ values: [ChallengeDay: Double]?, for challengeID: UUID, in store: ChallengeStore, now: Date) {
        store.setAutoValues(
            values ?? [:],
            availability: values == nil ? .unavailable : .available,
            for: challengeID,
            now: now
        )
    }

    /// Creates a challenge and fills food and water values at once, so a new
    /// challenge never shows "No data" over logs that already exist. Steps
    /// follow through `refreshSteps`.
    static func create(
        _ challenge: Challenge,
        in store: ChallengeStore,
        foodStore: FoodStore,
        waterStore: WaterStore,
        now: Date = Date()
    ) throws {
        try store.create(challenge, now: now)
        refreshLogged(store, foodStore: foodStore, waterStore: waterStore, now: now)
    }

    /// Food and water refresh for every logged-metric challenge. Synchronous so it
    /// can run inside the stores' existing change callbacks.
    static func refreshLogged(_ store: ChallengeStore, foodStore: FoodStore, waterStore: WaterStore, now: Date = Date()) {
        for challenge in store.challenges where isLogged(challenge.metric) {
            let values = loggedValues(for: challenge, foodStore: foodStore, waterStore: waterStore, now: now)
            store.setAutoValues(values, availability: .available, for: challenge.id, now: now)
        }
    }

    /// Steps refresh for every steps challenge.
    static func refreshSteps(_ store: ChallengeStore, healthKit: HealthKitManager, now: Date = Date()) async {
        for challenge in store.challenges where challenge.metric == .steps {
            let values = await stepValues(for: challenge, healthKit: healthKit, now: now)
            setSteps(values, for: challenge.id, in: store, now: now)
        }
    }

    /// Everything: logged metrics, then steps.
    static func refreshAll(
        _ store: ChallengeStore,
        foodStore: FoodStore,
        waterStore: WaterStore,
        healthKit: HealthKitManager
    ) async {
        refreshLogged(store, foodStore: foodStore, waterStore: waterStore)
        await refreshSteps(store, healthKit: healthKit)
        // Manual challenges also roll over at midnight.
        store.reconcile()
    }

    private static func isLogged(_ metric: ChallengeMetric) -> Bool {
        switch metric {
        case .calories, .protein, .waterAppLog: true
        case .steps, .custom: false
        }
    }

    /// Window days from the start through today (or the end, if earlier).
    private static func days(of challenge: Challenge, through now: Date, calendar: Calendar) -> [ChallengeDay] {
        let today = ChallengeDay(now, calendar: calendar)
        let last = min(today, challenge.endDay)
        let count = ChallengeDay.days(from: challenge.startDay, to: last) + 1
        guard count > 0 else { return [] }
        return (0..<count).map { challenge.startDay.adding(days: $0) }
    }

    /// Noon keeps owner queries that bucket with `Calendar.current` on the right day across DST.
    private static func noon(of day: ChallengeDay, calendar: Calendar) -> Date? {
        day.startDate(in: calendar).flatMap { calendar.date(byAdding: .hour, value: 12, to: $0) }
    }
}
