import Foundation
import Testing
@testable import calorietracker

/// Progress tab math: ranges, daily means, 7-day trend, weekly rate,
/// downsampling, derived fat mass, lean mass rows, steps and training weeks.
/// Every function takes `now` and a calendar so results do not depend on the
/// simulator clock or time zone.
///
/// Xcode 26:
/// xcodebuild test -project ios/calorietracker.xcodeproj -scheme calorietracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:calorietrackerTests/ProgressV2MathTests CODE_SIGNING_ALLOWED=NO
@MainActor
struct ProgressV2MathTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private var calendar: Calendar { Self.calendar }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func dayPoints(_ values: [Double], start: Date) -> [ProgressPoint] {
        let first = Self.calendar.startOfDay(for: start)
        return values.enumerated().map { offset, value in
            ProgressPoint(date: Self.calendar.date(byAdding: .day, value: offset, to: first)!, value: value)
        }
    }

    private func point(dayOffset: Int, value: Double, from start: Date) -> ProgressPoint {
        let first = Self.calendar.startOfDay(for: start)
        return ProgressPoint(date: Self.calendar.date(byAdding: .day, value: dayOffset, to: first)!, value: value)
    }

    private func close(_ lhs: Double?, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance
    }

    // MARK: - Moving average

    @Test func movingAverageSinglePointIsItself() {
        let start = date(2026, 9, 1)
        let result = ProgressV2Math.movingAverage([point(dayOffset: 0, value: 190.4, from: start)], calendar: calendar)
        #expect(result.count == 1)
        #expect(close(result.first?.value, 190.4))
    }

    @Test func movingAverageUsesSevenCalendarDayWindow() {
        let start = date(2026, 9, 1)
        let result = ProgressV2Math.movingAverage(dayPoints((0..<10).map(Double.init), start: start), calendar: calendar)
        #expect(result.count == 10)
        #expect(close(result[0].value, 0))
        #expect(close(result[1].value, 0.5))
        // Day 6 still includes day 0 (D-6 ... D).
        #expect(close(result[6].value, 3))
        // Day 7 drops day 0.
        #expect(close(result[7].value, 4))
        #expect(close(result[9].value, 6))
    }

    @Test func movingAverageSkipsGapsInsteadOfCountingPoints() {
        let start = date(2026, 9, 1)
        let points = [
            point(dayOffset: 0, value: 10, from: start),
            point(dayOffset: 3, value: 20, from: start),
            point(dayOffset: 6, value: 30, from: start),
            point(dayOffset: 7, value: 40, from: start),
            point(dayOffset: 20, value: 50, from: start),
        ]
        let result = ProgressV2Math.movingAverage(points, calendar: calendar)
        #expect(result.map(\.date) == points.map(\.date))
        #expect(close(result[1].value, 15))
        #expect(close(result[2].value, 20)) // days 0, 3, 6
        #expect(close(result[3].value, 30)) // days 3, 6, 7 — day 0 fell out
        // A 13-day gap: the last 3 points are the "last 3 points" but not in the window.
        #expect(close(result[4].value, 50))
    }

    @Test func dailyMeansAverageSameDayReadings() {
        let samples = [
            ProgressSample(date: date(2026, 9, 2, hour: 7), value: 190),
            ProgressSample(date: date(2026, 9, 2, hour: 21), value: 192),
            ProgressSample(date: date(2026, 9, 1, hour: 7), value: 191),
        ]
        let daily = ProgressV2Math.dailyMeans(samples, calendar: calendar)
        #expect(daily.count == 2)
        #expect(daily[0].date == calendar.startOfDay(for: date(2026, 9, 1)))
        #expect(close(daily[0].value, 191))
        #expect(close(daily[1].value, 191))
    }

    // MARK: - Rate

    @Test func weeklyRateMatchesKnownSlope() {
        let start = date(2026, 9, 1)
        let trend = dayPoints((0..<14).map { 190 - 0.1 * Double($0) }, start: start)
        #expect(close(ProgressV2Math.weeklyRate(trend, calendar: calendar), -0.7, tolerance: 1e-9))
    }

    @Test func weeklyRateUsesCalendarDaysForGaps() {
        let start = date(2026, 9, 1)
        let trend = [
            point(dayOffset: 0, value: 100, from: start),
            point(dayOffset: 7, value: 101, from: start),
            point(dayOffset: 14, value: 102, from: start),
        ]
        #expect(close(ProgressV2Math.weeklyRate(trend, calendar: calendar), 1))
    }

    @Test func weeklyRateNeedsThreePointsAndFiveDays() {
        let start = date(2026, 9, 1)
        let two = [point(dayOffset: 0, value: 1, from: start), point(dayOffset: 10, value: 2, from: start)]
        #expect(ProgressV2Math.weeklyRate(two, calendar: calendar) == nil)

        // Three points spanning four calendar days.
        let short = [
            point(dayOffset: 0, value: 1, from: start),
            point(dayOffset: 1, value: 2, from: start),
            point(dayOffset: 3, value: 3, from: start),
        ]
        #expect(ProgressV2Math.weeklyRate(short, calendar: calendar) == nil)

        // Three points spanning exactly five calendar days.
        let enough = [
            point(dayOffset: 0, value: 1, from: start),
            point(dayOffset: 2, value: 2, from: start),
            point(dayOffset: 4, value: 3, from: start),
        ]
        #expect(close(ProgressV2Math.weeklyRate(enough, calendar: calendar), 3.5))
        #expect(ProgressV2Math.weeklyRate([], calendar: calendar) == nil)
    }

    @Test func weeklyRateScalesWithUnit() throws {
        let now = date(2026, 9, 30, hour: 18)
        let kgSamples = (0..<30).map { offset -> ProgressSample in
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            return ProgressSample(date: day, value: 86 - 0.02 * Double(29 - offset) + (offset.isMultiple(of: 3) ? 0.3 : 0))
        }
        let lbSamples = kgSamples.map { ProgressSample(date: $0.date, value: $0.value * ProgressV2Math.poundsPerKilogram) }
        let window = ProgressV2Math.window(for: .month, now: now, calendar: calendar, earliestData: nil)
        let kg = ProgressV2Math.series(samples: kgSamples, window: window, calendar: calendar)
        let lb = ProgressV2Math.series(samples: lbSamples, window: window, calendar: calendar)
        let kgRate = try #require(kg.stats.weeklyRate)
        let lbRate = try #require(lb.stats.weeklyRate)
        #expect(kgRate < 0)
        #expect(abs(lbRate - kgRate * ProgressV2Math.poundsPerKilogram) < 1e-9)
    }

    @Test func seriesStatsUseFullResolutionDailyMeans() {
        let now = date(2026, 9, 30, hour: 18)
        let samples = [
            ProgressSample(date: date(2026, 9, 20, hour: 7), value: 190),
            ProgressSample(date: date(2026, 9, 20, hour: 20), value: 192),
            ProgressSample(date: date(2026, 9, 29, hour: 7), value: 188),
            ProgressSample(date: date(2026, 9, 29, hour: 22), value: 188.6),
        ]
        let window = ProgressV2Math.window(for: .month, now: now, calendar: calendar, earliestData: nil)
        let series = ProgressV2Math.series(samples: samples, window: window, calendar: calendar)
        #expect(series.readingCount == 4)
        #expect(series.daily.count == 2)
        #expect(close(series.stats.current, 188.6))
        #expect(close(series.stats.netChange, 188.3 - 191, tolerance: 1e-9))
        #expect(close(series.stats.average, (191 + 188.3) / 2, tolerance: 1e-9))
        // Two daily points: not enough for a rate.
        #expect(series.stats.weeklyRate == nil)
        #expect(ProgressV2Math.series(samples: [], window: window, calendar: calendar).isEmpty)
    }

    // MARK: - Ranges

    @Test func everyBoundedRangeEndsAfterTodayAndStartsNDaysBack() {
        let now = date(2026, 9, 30, hour: 15)
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        for range in TimeRange.allCases where range != .allTime {
            let window = ProgressV2Math.window(for: range, now: now, calendar: calendar, earliestData: date(2001, 1, 1))
            let expectedStart = calendar.date(byAdding: .day, value: -(range.days - 1), to: startOfToday)!
            #expect(window.start == expectedStart, "\(range.rawValue)")
            #expect(window.endExclusive == tomorrow, "\(range.rawValue)")
            #expect(window.contains(now), "\(range.rawValue)")
            #expect(window.contains(tomorrow.addingTimeInterval(-0.5)), "\(range.rawValue) includes the last second of today")
            #expect(!window.contains(tomorrow), "\(range.rawValue)")
            #expect(window.contains(expectedStart), "\(range.rawValue)")
            #expect(!window.contains(expectedStart.addingTimeInterval(-1)), "\(range.rawValue)")
            #expect(window.dayCount(calendar: calendar) == range.days, "\(range.rawValue)")
        }
    }

    @Test func allRangeStartsAtEarliestDataEvenPastTenYears() {
        let now = date(2026, 9, 30, hour: 15)
        let ancient = date(2012, 3, 5, hour: 10)
        let window = ProgressV2Math.window(for: .allTime, now: now, calendar: calendar, earliestData: ancient)
        #expect(window.start == calendar.startOfDay(for: ancient))
        #expect(window.contains(ancient))
        #expect(window.contains(now))
        #expect(window.dayCount(calendar: calendar) > TimeRange.allTime.days)

        let empty = ProgressV2Math.window(for: .allTime, now: now, calendar: calendar, earliestData: nil)
        #expect(empty.start == calendar.startOfDay(for: now))
        #expect(empty.dayCount(calendar: calendar) == 1)
    }

    @Test func filterKeepsTodayAndDropsOutOfRangeSamples() {
        let now = date(2026, 9, 30, hour: 9)
        let window = ProgressV2Math.window(for: .week, now: now, calendar: calendar, earliestData: nil)
        let samples = [
            ProgressSample(date: date(2026, 9, 30, hour: 23, minute: 59), value: 3),
            ProgressSample(date: date(2026, 9, 24, hour: 0), value: 2),
            ProgressSample(date: date(2026, 9, 23, hour: 23, minute: 59), value: 1),
            ProgressSample(date: date(2026, 10, 1, hour: 0), value: 4),
        ]
        let kept = ProgressV2Math.filter(samples, in: window)
        #expect(kept.map(\.value) == [2, 3])
    }

    // MARK: - Downsampling

    @Test func downsampleIsNoOpForSmallInput() {
        let points = dayPoints((0..<90).map(Double.init), start: date(2026, 1, 1))
        #expect(ProgressV2Math.downsample(points, maxPoints: 120, calendar: calendar) == points)
        #expect(ProgressV2Math.downsample([], calendar: calendar).isEmpty)
    }

    @Test func downsampleStaysUnderLimitAndKeepsEnds() {
        for count in [121, 400, 1_500] {
            let points = dayPoints((0..<count).map { 190 + sin(Double($0) / 9) }, start: date(2022, 1, 1))
            let result = ProgressV2Math.downsample(points, maxPoints: 120, calendar: calendar)
            #expect(result.count <= 120, "\(count)")
            #expect(result.count >= 3, "\(count)")
            #expect(result.first == points.first, "\(count)")
            #expect(result.last == points.last, "\(count)")
            #expect(zip(result, result.dropFirst()).allSatisfy { $0.date < $1.date }, "\(count) stays sorted")
        }
        let tight = dayPoints((0..<1_500).map(Double.init), start: date(2020, 1, 1))
        #expect(ProgressV2Math.downsample(tight, maxPoints: 20, calendar: calendar).count <= 20)
    }

    @Test func downsampleAveragesWeekBuckets() {
        // Mon 2026-01-05 ... Sun 2026-01-18, values 0...13.
        let points = dayPoints((0..<14).map(Double.init), start: date(2026, 1, 5))
        let result = ProgressV2Math.downsample(points, maxPoints: 4, calendar: calendar)
        #expect(result.count == 4)
        #expect(result[0] == points[0])
        #expect(result[3] == points[13])
        // Tue–Sun of the first week (1...6), Mon–Sat of the second (7...12).
        #expect(close(result[1].value, 3.5))
        #expect(close(result[2].value, 9.5))
    }

    // MARK: - Derived fat mass

    @Test func derivedFatMassNeedsSameDayPair() throws {
        let weights = [ProgressSample(date: date(2026, 9, 28, hour: 7), value: 90)]
        let fats = [ProgressSample(date: date(2026, 9, 28, hour: 7, minute: 5), value: 0.2)]
        let derived = try #require(ProgressV2Math.derivedFatMass(weightsKg: weights, bodyFatFractions: fats, calendar: calendar))
        #expect(derived.day == calendar.startOfDay(for: date(2026, 9, 28)))
        #expect(close(derived.fatMassKg, 18))

        let otherDay = [ProgressSample(date: date(2026, 9, 27, hour: 7), value: 0.2)]
        #expect(ProgressV2Math.derivedFatMass(weightsKg: weights, bodyFatFractions: otherDay, calendar: calendar) == nil)
        #expect(ProgressV2Math.derivedFatMass(weightsKg: [], bodyFatFractions: fats, calendar: calendar) == nil)
    }

    @Test func derivedFatMassPicksMostRecentPairAndLatestReadings() throws {
        let weights = [
            ProgressSample(date: date(2026, 9, 20, hour: 7), value: 92),
            ProgressSample(date: date(2026, 9, 27, hour: 7), value: 91),
            ProgressSample(date: date(2026, 9, 27, hour: 19), value: 91.5),
            ProgressSample(date: date(2026, 9, 29, hour: 7), value: 90), // no body fat that day
        ]
        let fats = [
            ProgressSample(date: date(2026, 9, 20, hour: 7), value: 0.22),
            ProgressSample(date: date(2026, 9, 27, hour: 7), value: 0.21),
            ProgressSample(date: date(2026, 9, 30, hour: 7), value: 0.19), // no weight that day
        ]
        let derived = try #require(ProgressV2Math.derivedFatMass(weightsKg: weights, bodyFatFractions: fats, calendar: calendar))
        #expect(derived.day == calendar.startOfDay(for: date(2026, 9, 27)))
        #expect(close(derived.weightKg, 91.5))
        #expect(close(derived.bodyFatFraction, 0.21))
        #expect(close(derived.fatMassKg, 91.5 * 0.21))
    }

    // MARK: - Lean mass rows

    @Test func leanMassComesFromLeanRowsOnly() throws {
        let suite = "progress-v2-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WeightStore(observesExternalChanges: false, defaults: defaults)
        let rows = [
            WeightEntry(date: date(2026, 9, 10, hour: 7), weightKg: 86.5),
            WeightEntry(date: date(2026, 9, 10, hour: 7), weightKg: 68.2, healthSourceName: "Withings", leanBodyMass: true),
            WeightEntry(date: date(2026, 9, 25, hour: 7), weightKg: 86.0, leanBodyMass: false),
            WeightEntry(date: date(2026, 9, 25, hour: 7), weightKg: 68.4, healthSourceName: "Withings", leanBodyMass: true),
            WeightEntry(date: date(2026, 8, 1, hour: 7), weightKg: 68.0, leanBodyMass: true),
        ]
        store.replaceAllEntries(rows)

        #expect(store.leanMassEntries.map(\.weightKg) == [68.0, 68.2, 68.4])
        #expect(store.bodyWeightEntries.count == 2)
        #expect(store.latestLeanMassEntry?.weightKg == 68.4)
        let september = date(2026, 9, 1, hour: 0)...date(2026, 9, 30, hour: 23)
        #expect(store.leanMassEntries(in: september).map(\.weightKg) == [68.2, 68.4])
        #expect(store.entries(in: september).allSatisfy { !$0.isLeanBodyMass })

        let snapshot = ProgressCompositionBuilder.build(
            weightRows: store.entries,
            bodyFatRows: [],
            range: .month,
            useMetric: false,
            now: date(2026, 9, 30, hour: 18),
            calendar: calendar
        )
        #expect(snapshot.hasAnyLeanMass)
        #expect(snapshot.leanMass.readingCount == 2)
        #expect(snapshot.weight.readingCount == 2)
        #expect(close(snapshot.latestLeanMass?.value, 68.4 * ProgressV2Math.poundsPerKilogram))
        #expect(snapshot.latestLeanMassSource == "Withings")
        #expect(close(snapshot.weight.stats.current, 86.0 * ProgressV2Math.poundsPerKilogram))
        // No body fat readings, so nothing may be derived.
        #expect(snapshot.derivedFatMass == nil)
    }

    @Test func leanMassEmptyRangeStillKnowsOlderReadings() {
        let rows = [WeightEntry(date: date(2026, 5, 1, hour: 7), weightKg: 68, leanBodyMass: true)]
        let snapshot = ProgressCompositionBuilder.build(
            weightRows: rows,
            bodyFatRows: [],
            range: .month,
            useMetric: true,
            now: date(2026, 9, 30, hour: 18),
            calendar: calendar
        )
        #expect(snapshot.leanMass.isEmpty)
        #expect(snapshot.hasAnyLeanMass)
        #expect(close(snapshot.latestLeanMass?.value, 68))
        #expect(!snapshot.hasAnyWeight)
    }

    @Test func compositionFingerprintCoversEveryRow() {
        let firstID = UUID()
        let fatID = UUID()
        let base = [
            WeightEntry(id: firstID, date: date(2026, 6, 1, hour: 7), weightKg: 86.5),
            WeightEntry(date: date(2026, 9, 29, hour: 7), weightKg: 86.0),
        ]
        let fats = [BodyFatEntry(id: fatID, date: date(2026, 6, 1, hour: 7), bodyFatFraction: 0.21)]
        let reference = ProgressCompositionBuilder.fingerprint(weightRows: base, bodyFatRows: fats)
        #expect(reference == ProgressCompositionBuilder.fingerprint(weightRows: base, bodyFatRows: fats))

        // Same counts and same last row, but an older value changed.
        var edited = base
        edited[0] = WeightEntry(id: firstID, date: base[0].date, weightKg: 85.9)
        #expect(ProgressCompositionBuilder.fingerprint(weightRows: edited, bodyFatRows: fats) != reference)

        // Lean-mass flag flipped on an older row.
        var flagged = base
        flagged[0] = WeightEntry(id: firstID, date: base[0].date, weightKg: 86.5, leanBodyMass: true)
        #expect(ProgressCompositionBuilder.fingerprint(weightRows: flagged, bodyFatRows: fats) != reference)

        // Older reading moved to another day.
        var moved = base
        moved[0] = WeightEntry(id: firstID, date: date(2026, 6, 2, hour: 7), weightKg: 86.5)
        #expect(ProgressCompositionBuilder.fingerprint(weightRows: moved, bodyFatRows: fats) != reference)

        // Body fat edited in place.
        let fatEdited = [BodyFatEntry(id: fatID, date: fats[0].date, bodyFatFraction: 0.2)]
        #expect(ProgressCompositionBuilder.fingerprint(weightRows: base, bodyFatRows: fatEdited) != reference)

        // Only the Health source changed (it feeds the lean mass caption).
        var sourced = base
        sourced[0] = WeightEntry(id: firstID, date: base[0].date, weightKg: 86.5, healthSourceName: "Withings")
        #expect(ProgressCompositionBuilder.fingerprint(weightRows: sourced, bodyFatRows: fats) != reference)

        // Scales to a full history in one pass.
        let many = (0..<700).map { WeightEntry(date: date(2024, 1, 1).addingTimeInterval(Double($0) * 86_400), weightKg: 80 + Double($0 % 9) * 0.1) }
        #expect(ProgressCompositionBuilder.fingerprint(weightRows: many, bodyFatRows: []) != reference)
    }

    // MARK: - Steps

    @Test func stepsSummaryCountsDaysMetFromDailyTotals() {
        let now = date(2026, 9, 30, hour: 18)
        let window = ProgressV2Math.window(for: .week, now: now, calendar: calendar, earliestData: nil)
        var byDay: [Date: Int] = [:]
        let values = [12_000, 0, 9_999, 10_000, 4_000, 15_500, 7_000] // Sep 24 ... Sep 30
        for (offset, steps) in values.enumerated() {
            byDay[calendar.date(byAdding: .day, value: offset, to: window.start)!] = steps
        }
        byDay[calendar.date(byAdding: .day, value: -1, to: window.start)!] = 30_000 // outside the window

        let summary = ProgressV2Math.stepsSummary(byDay: byDay, window: window, goal: 10_000, weekly: false, calendar: calendar)
        #expect(summary.trackedDays == 6)
        #expect(summary.daysMet == 3)
        // 58,499 / 6 = 9,749.8 → 9,750.
        #expect(summary.dailyAverage == 9_750)
        #expect(summary.bars.count == 6)
        #expect(!summary.isWeekly)
        #expect(!summary.isEmpty)
    }

    @Test func stepsSummaryWeeklyBarsAverageTrackedDays() {
        let now = date(2026, 9, 30, hour: 18)
        let window = ProgressV2Math.window(for: .sixMonths, now: now, calendar: calendar, earliestData: nil)
        // Mon Sep 21 ... Sun Sep 27: 5 tracked days, 2 at zero.
        let week = [11_000, 9_000, 0, 10_000, 5_000, 0, 15_000]
        var byDay: [Date: Int] = [:]
        for (offset, steps) in week.enumerated() {
            byDay[date(2026, 9, 21 + offset, hour: 0)] = steps
        }
        byDay[date(2026, 9, 28, hour: 0)] = 20_000

        let summary = ProgressV2Math.stepsSummary(byDay: byDay, window: window, goal: 10_000, weekly: true, calendar: calendar)
        #expect(summary.isWeekly)
        #expect(summary.bars.count == 2)
        #expect(summary.bars[0].date == date(2026, 9, 21, hour: 0))
        #expect(summary.bars[0].steps == 10_000)
        #expect(summary.bars[1].steps == 20_000)
        #expect(summary.daysMet == 4)
        #expect(summary.trackedDays == 6)
    }

    @Test func stepsSummaryIsEmptyWithoutTrackedDays() {
        let now = date(2026, 9, 30, hour: 18)
        let window = ProgressV2Math.window(for: .month, now: now, calendar: calendar, earliestData: nil)
        let summary = ProgressV2Math.stepsSummary(byDay: [date(2026, 9, 29, hour: 0): 0], window: window, goal: 10_000, weekly: false, calendar: calendar)
        #expect(summary.isEmpty)
        #expect(summary.dailyAverage == nil)
    }

    @Test func stepsWindowIgnoresBodyDataAndBoundsAll() {
        let now = date(2026, 9, 30, hour: 18)
        let startOfToday = calendar.startOfDay(for: now)
        let all = ProgressV2Math.stepsWindow(for: .allTime, now: now, calendar: calendar)
        let twoYearsBack = calendar.date(byAdding: .day, value: -(ProgressV2Math.allStepsLookbackDays - 1), to: startOfToday)!
        #expect(all.start == twoYearsBack)
        #expect(all.dayCount(calendar: calendar) == 730)
        #expect(all.contains(now))
        // Steps from 2 years back count; older ones are outside the labeled window.
        let byDay = [twoYearsBack: 12_000, calendar.date(byAdding: .day, value: -1, to: twoYearsBack)!: 8_000]
        let summary = ProgressV2Math.stepsSummary(byDay: byDay, window: all, goal: 10_000, weekly: true, calendar: calendar)
        #expect(summary.trackedDays == 1)
        #expect(ProgressV2Math.stepsRangeDescription(.allTime) == "the last 2 years")

        for range in TimeRange.allCases where range != .allTime {
            let window = ProgressV2Math.stepsWindow(for: range, now: now, calendar: calendar)
            #expect(window == ProgressV2Math.window(for: range, now: now, calendar: calendar, earliestData: nil), "\(range.rawValue)")
            #expect(ProgressV2Math.stepsRangeDescription(range) == range.rangeDescription, "\(range.rawValue)")
        }
    }

    @Test func weeklyStepBarsOnlyPastThreeMonths() {
        #expect(!ProgressV2Math.usesWeeklyStepBars(.week))
        #expect(!ProgressV2Math.usesWeeklyStepBars(.month))
        #expect(!ProgressV2Math.usesWeeklyStepBars(.threeMonths))
        #expect(ProgressV2Math.usesWeeklyStepBars(.sixMonths))
        #expect(ProgressV2Math.usesWeeklyStepBars(.year))
        #expect(ProgressV2Math.usesWeeklyStepBars(.allTime))
    }

    // MARK: - Training weeks

    @Test func mondayWeekBucketing() {
        #expect(ProgressTrainingMath.mondayKey(for: "2026-09-28") == "2026-09-28")
        #expect(ProgressTrainingMath.mondayKey(for: "2026-10-04") == "2026-09-28")
        #expect(ProgressTrainingMath.mondayKey(for: "2026-09-27") == "2026-09-21")
        #expect(ProgressTrainingMath.mondayKey(for: "2027-01-01") == "2026-12-28")
        #expect(ProgressTrainingMath.mondayKey(for: "2026-02-30") == nil)
        #expect(ProgressTrainingMath.weekKeys(from: "2026-09-10", through: "2026-09-30")
            == ["2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28"])
        let capped = ProgressTrainingMath.displayedWeekKeys(from: "2025-12-01", through: "2026-09-30", limit: 26)
        #expect(capped.total == 44)
        #expect(capped.shown.count == 26)
        #expect(capped.shown.last == "2026-09-28")
    }

    @Test func workoutDayKeyPrefersSessionDate() {
        let isoMidnight = ProgressBridgeWorkout(id: "a", sessionDate: "2026-09-28T00:00:00.000Z")
        let plain = ProgressBridgeWorkout(id: "b", sessionDate: "2026-09-28")
        // 02:30 UTC on Sep 29 is 22:30 on Sep 28 in New York.
        let recordedOnly = ProgressBridgeWorkout(id: "c", sessionDate: nil, recordedAt: "2026-09-29T02:30:00Z")
        let fractional = ProgressBridgeWorkout(id: "d", sessionDate: "", recordedAt: "2026-09-29T15:00:00.123Z")
        #expect(ProgressTrainingMath.dayKey(for: isoMidnight) == "2026-09-28")
        #expect(ProgressTrainingMath.dayKey(for: plain) == "2026-09-28")
        #expect(ProgressTrainingMath.dayKey(for: recordedOnly) == "2026-09-28")
        #expect(ProgressTrainingMath.dayKey(for: fractional) == "2026-09-29")
        #expect(ProgressTrainingMath.dayKey(for: ProgressBridgeWorkout(id: "e", sessionDate: nil)) == nil)
    }

    @Test func recordedAtDayKeyUsesInjectedTimeZone() {
        let workout = ProgressBridgeWorkout(id: "tz", sessionDate: nil, recordedAt: "2026-09-29T02:30:00Z")
        #expect(ProgressTrainingMath.dayKey(for: workout, timeZone: .gmt) == "2026-09-29")
        #expect(ProgressTrainingMath.dayKey(for: workout, timeZone: TimeZone(identifier: "America/New_York")!) == "2026-09-28")
        // session_date wins regardless of time zone.
        let dated = ProgressBridgeWorkout(id: "d", sessionDate: "2026-09-30T00:00:00.000Z", recordedAt: "2026-09-30T12:04:47.384Z")
        #expect(ProgressTrainingMath.dayKey(for: dated, timeZone: TimeZone(identifier: "Pacific/Kiritimati")!) == "2026-09-30")
    }

    @Test func onlyCompletedNonSyntheticWorkoutsCount() {
        #expect(ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "1", kind: "COMPLETED", sessionDate: "2026-09-28")))
        #expect(ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "2", kind: "completed", sessionDate: "2026-09-28")))
        #expect(ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "3", kind: " Completed ", sessionDate: "2026-09-28", synthetic: false)))
        #expect(!ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "4", kind: "strength", sessionDate: "2026-09-28")))
        #expect(!ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "5", kind: "PLANNED", sessionDate: "2026-09-28")))
        #expect(!ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "6", kind: nil, sessionDate: "2026-09-28")))
        #expect(!ProgressTrainingMath.isCompleted(ProgressBridgeWorkout(id: "7", kind: "COMPLETED", sessionDate: "2026-09-28", synthetic: true)))
    }

    @Test func trainingSummaryBucketsSessionsSetsAndVolumeByWeek() {
        let workouts = [
            ProgressBridgeWorkout(id: "1", sessionDate: "2026-09-21"),
            ProgressBridgeWorkout(id: "2", sessionDate: "2026-09-23T00:00:00.000Z"),
            ProgressBridgeWorkout(id: "3", sessionDate: "2026-09-27"), // Sunday: same week as Sep 21
            ProgressBridgeWorkout(id: "4", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "5", kind: "strength", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "6", sessionDate: "2026-08-01"), // before the range
            ProgressBridgeWorkout(id: "7", sessionDate: "2026-09-30", synthetic: true),
            // 03:00 UTC Sep 28 is 23:00 Sunday Sep 27 in New York.
            ProgressBridgeWorkout(id: "8", sessionDate: nil, recordedAt: "2026-09-28T03:00:00Z"),
            ProgressBridgeWorkout(id: "9", sessionDate: "2026-10-01"), // after today
        ]
        let details = [
            "1": ProgressWorkoutTotals(sets: 10, volumeLb: 5_000),
            "2": ProgressWorkoutTotals(sets: 8, volumeLb: 3_000.5),
            "8": ProgressWorkoutTotals(sets: 6, volumeLb: 1_200),
            "5": ProgressWorkoutTotals(sets: 99, volumeLb: 99_999), // not completed: ignored
        ]
        #expect(ProgressTrainingMath.detailWorkoutIDs(workouts: workouts, startDayKey: "2026-09-16", todayKey: "2026-09-30")
            == ["4", "8", "3", "2", "1"])

        let summary = ProgressTrainingMath.summary(
            workouts: workouts,
            details: details,
            startDayKey: "2026-09-16",
            todayKey: "2026-09-30",
            failedDetails: 2
        )
        #expect(summary.weeks.map(\.weekStart) == ["2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(summary.weeks.map(\.sessions) == [0, 4, 1])
        // Wed Sep 16 – Sun Sep 20, a full week, then Mon Sep 28 – today.
        #expect(summary.weeks.map(\.days) == [5, 7, 3])
        #expect(summary.weeks[0].firstDay == "2026-09-16")
        #expect(summary.weeks[2].lastDay == "2026-09-30")
        #expect(summary.firstWeekIsPartial)
        #expect(summary.rangeStartDay == "2026-09-16")
        // 5 sessions over 15 days in range.
        #expect(close(summary.averageSessionsPerWeek, 5.0 / (15.0 / 7.0)))
        #expect(summary.weeks[0].sets == 0)
        #expect(summary.weeks[0].volumeLb == 0)
        #expect(summary.weeks[1].sets == 24)
        #expect(close(summary.weeks[1].volumeLb, 9_200.5))
        // Sessions without loaded sets: unknown, not zero.
        #expect(summary.weeks[2].sets == nil)
        #expect(summary.weeks[2].volumeLb == nil)
        #expect(summary.totalSessions == 5)
        #expect(summary.totalSets == 24)
        #expect(close(summary.totalVolumeLb, 9_200.5))
        #expect(summary.failedDetails == 2)
        #expect(summary.sessionsInRange == 5)
        #expect(summary.detailSessions == 5)
        #expect(!summary.isDetailLimited)
        #expect(!summary.isTruncated)
        #expect(!summary.listTruncated)
        #expect(summary.sessionListCutoff == nil)
        #expect(!summary.isEmpty)
    }

    @Test func trainingSummaryWithoutCompletedSessionsIsEmpty() {
        let workouts = [
            ProgressBridgeWorkout(id: "a", kind: "strength", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "b", sessionDate: "2026-09-29", synthetic: true),
        ]
        let summary = ProgressTrainingMath.summary(workouts: workouts, details: [:], startDayKey: "2026-09-24", todayKey: "2026-09-30")
        #expect(summary.isEmpty)
        #expect(summary.weeks.map(\.weekStart) == ["2026-09-21", "2026-09-28"])
        #expect(summary.totalSets == 0)
        #expect(ProgressTrainingMath.detailWorkoutIDs(workouts: workouts, startDayKey: "2026-09-24", todayKey: "2026-09-30").isEmpty)
    }

    private func shiftedDayKey(_ key: String, days: Int) -> String {
        let date = ProgressTrainingMath.parseDayKey(key)!
        return ProgressTrainingMath.dayKey(for: date.addingTimeInterval(Double(days) * 86_400), timeZone: .gmt)
    }

    @Test func detailRequestsCapAtMostRecentSessions() {
        // One session a day for 70 days, Sep 30 back to Jul 23.
        let workouts = (0..<70).map { offset in
            ProgressBridgeWorkout(id: "w\(offset)", sessionDate: shiftedDayKey("2026-09-30", days: -offset))
        }
        let ids = ProgressTrainingMath.detailWorkoutIDs(workouts: workouts, startDayKey: "2026-07-01", todayKey: "2026-09-30")
        #expect(ids.count == ProgressTrainingMath.maxDetailSessions)
        #expect(ids.first == "w0")
        #expect(ids.last == "w59")

        var details: [String: ProgressWorkoutTotals] = [:]
        for workout in workouts {
            details[workout.id] = ProgressWorkoutTotals(sets: 1, volumeLb: 100)
        }
        let summary = ProgressTrainingMath.summary(workouts: workouts, details: details, startDayKey: "2026-07-01", todayKey: "2026-09-30")
        #expect(summary.sessionsInRange == 70)
        #expect(summary.totalSessions == 70)
        #expect(summary.detailSessions == 60)
        #expect(summary.isDetailLimited)
        // Only the 60 requested sessions contribute, even if more are cached.
        #expect(summary.totalSets == 60)
        #expect(close(summary.totalVolumeLb, 6_000))
        // Jul 20 – 26 (sessions Jul 23 – 26) holds only sessions past the cap: unknown sets.
        let oldWeek = summary.weeks.first { $0.weekStart == "2026-07-20" }
        #expect(oldWeek?.sessions == 4)
        #expect(oldWeek?.sets == nil)
        // Jul 27 – Aug 2 includes Aug 2, the 60th most recent session.
        let partialWeek = summary.weeks.first { $0.weekStart == "2026-07-27" }
        #expect(partialWeek?.sessions == 7)
        #expect(partialWeek?.sets == 1)
    }

    @Test func detailOrderBreaksSameDayTiesByRecordedAt() {
        let workouts = [
            ProgressBridgeWorkout(id: "am", sessionDate: "2026-09-30T00:00:00.000Z", recordedAt: "2026-09-30T12:04:47.384Z"),
            ProgressBridgeWorkout(id: "pm", sessionDate: "2026-09-30T00:00:00.000Z", recordedAt: "2026-09-30T22:10:00.000Z"),
            ProgressBridgeWorkout(id: "old", sessionDate: "2026-09-29"),
        ]
        let ids = ProgressTrainingMath.detailWorkoutIDs(
            workouts: workouts,
            startDayKey: "2026-09-24",
            todayKey: "2026-09-30",
            detailLimit: 2
        )
        #expect(ids == ["pm", "am"])
        let summary = ProgressTrainingMath.summary(
            workouts: workouts,
            details: ["pm": ProgressWorkoutTotals(sets: 5, volumeLb: 500), "am": ProgressWorkoutTotals(sets: 4, volumeLb: 400)],
            startDayKey: "2026-09-24",
            todayKey: "2026-09-30",
            detailLimit: 2
        )
        #expect(summary.isDetailLimited)
        #expect(summary.detailSessions == 2)
        #expect(summary.totalSets == 9)
    }

    @Test func trainingSummaryFlagsListAndWeekTruncation() {
        let recent = (0..<200).map { index in
            ProgressBridgeWorkout(id: "w\(index)", sessionDate: index < 100 ? "2026-09-29" : "2026-09-15")
        }
        let summary = ProgressTrainingMath.summary(
            workouts: recent,
            details: [:],
            startDayKey: "2025-01-01",
            todayKey: "2026-09-30"
        )
        #expect(summary.isTruncated)
        #expect(summary.shownWeeks == ProgressTrainingMath.maxWeeks)
        #expect(summary.weeksInRange > ProgressTrainingMath.maxWeeks)
        #expect(summary.listTruncated)
        #expect(summary.sessionListCutoff == "2026-09-15")
        // Weeks before the list's oldest row are unknown, not zero.
        #expect(summary.weeks.map(\.weekStart) == ["2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(summary.unloadedWeeks == ProgressTrainingMath.maxWeeks - 3)
        #expect(summary.weeks.map(\.isIncomplete) == [true, false, false])
        #expect(!summary.firstWeekIsPartial)
        #expect(summary.isDetailLimited)
        #expect(summary.detailSessions == ProgressTrainingMath.maxDetailSessions)

        let short = ProgressTrainingMath.summary(
            workouts: Array(recent.prefix(199)),
            details: [:],
            startDayKey: "2025-01-01",
            todayKey: "2026-09-30"
        )
        #expect(!short.listTruncated)
        #expect(short.sessionListCutoff == nil)
        #expect(short.unloadedWeeks == 0)
        #expect(short.weeks.count == ProgressTrainingMath.maxWeeks)
    }

    @Test func trainingIgnoresSessionsBeforeRangeStartInFirstWeek() {
        // 1W on Wed Sep 30 is Thu Sep 24 – Wed Sep 30; Mon Sep 21 and Wed
        // Sep 23 share the first Monday week but are outside the range.
        let workouts = [
            ProgressBridgeWorkout(id: "mon21", sessionDate: "2026-09-21"),
            ProgressBridgeWorkout(id: "wed23", sessionDate: "2026-09-23"),
            ProgressBridgeWorkout(id: "thu24", sessionDate: "2026-09-24"),
            ProgressBridgeWorkout(id: "sun27", sessionDate: "2026-09-27"),
            ProgressBridgeWorkout(id: "tue29", sessionDate: "2026-09-29"),
        ]
        var details: [String: ProgressWorkoutTotals] = [:]
        for workout in workouts {
            details[workout.id] = ProgressWorkoutTotals(sets: 10, volumeLb: 1_000)
        }
        // Sets are only requested for sessions inside the range.
        #expect(ProgressTrainingMath.detailWorkoutIDs(workouts: workouts, startDayKey: "2026-09-24", todayKey: "2026-09-30")
            == ["tue29", "sun27", "thu24"])

        let summary = ProgressTrainingMath.summary(
            workouts: workouts,
            details: details,
            startDayKey: "2026-09-24",
            todayKey: "2026-09-30"
        )
        #expect(summary.weeks.map(\.weekStart) == ["2026-09-21", "2026-09-28"])
        #expect(summary.weeks.map(\.sessions) == [2, 1])
        #expect(summary.weeks.map(\.sets) == [20, 10])
        #expect(summary.weeks.map(\.days) == [4, 3])
        #expect(summary.weeks[0].firstDay == "2026-09-24")
        #expect(summary.weeks[0].lastDay == "2026-09-27")
        #expect(summary.weeks[0].isPartial)
        #expect(summary.firstWeekIsPartial)
        #expect(summary.totalSessions == 3)
        #expect(summary.sessionsInRange == 3)
        #expect(summary.totalSets == 30)
        #expect(close(summary.totalVolumeLb, 3_000))
        // 3 sessions over the 7 days in range.
        #expect(close(summary.averageSessionsPerWeek, 3))
    }

    @Test func truncatedListLeavesOlderWeeksUnknown() {
        // The list limit is hit and its oldest row is Wed Sep 16, inside 1M.
        let workouts = [
            ProgressBridgeWorkout(id: "a", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "b", sessionDate: "2026-09-24"),
            ProgressBridgeWorkout(id: "c", sessionDate: "2026-09-22"),
            ProgressBridgeWorkout(id: "d", sessionDate: "2026-09-17"),
            ProgressBridgeWorkout(id: "e", kind: "strength", sessionDate: "2026-09-16"),
        ]
        let summary = ProgressTrainingMath.summary(
            workouts: workouts,
            details: [:],
            startDayKey: "2026-09-01",
            todayKey: "2026-09-30",
            listLimit: 5
        )
        #expect(summary.listTruncated)
        #expect(summary.sessionListCutoff == "2026-09-16")
        // Aug 31 and Sep 7 weeks predate the list: not drawn as zero weeks.
        #expect(summary.unloadedWeeks == 2)
        #expect(summary.weeks.map(\.weekStart) == ["2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(summary.weeks.map(\.isIncomplete) == [true, false, false])
        #expect(summary.weeks.map(\.sessions) == [1, 2, 1])
        #expect(summary.totalSessions == 4)
        // The cutoff week is left out of the average: 3 sessions over 10 days.
        #expect(close(summary.averageSessionsPerWeek, 3.0 / (10.0 / 7.0)))
        #expect(!summary.firstWeekIsPartial)
        #expect(!summary.isTruncated)

        // The same rows under the limit cover the whole range.
        let complete = ProgressTrainingMath.summary(
            workouts: workouts,
            details: [:],
            startDayKey: "2026-09-01",
            todayKey: "2026-09-30"
        )
        #expect(complete.unloadedWeeks == 0)
        #expect(complete.weeks.count == 5)
        #expect(complete.weeks.allSatisfy { !$0.isIncomplete })
    }

    @Test func truncatedListEndingOnRangeStartKeepsThatWeekIncomplete() {
        // 1M on Wed Sep 30 starts Tue Sep 1; the full list's oldest row is
        // exactly Sep 1, so more Sep 1 rows may have been cut off.
        let workouts = [
            ProgressBridgeWorkout(id: "a", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "b", sessionDate: "2026-09-24"),
            ProgressBridgeWorkout(id: "c", sessionDate: "2026-09-17"),
            ProgressBridgeWorkout(id: "d", sessionDate: "2026-09-01"),
        ]
        let summary = ProgressTrainingMath.summary(
            workouts: workouts,
            details: [:],
            startDayKey: "2026-09-01",
            todayKey: "2026-09-30",
            listLimit: 4
        )
        #expect(summary.listTruncated)
        #expect(summary.sessionListCutoff == "2026-09-01")
        #expect(summary.unloadedWeeks == 0)
        #expect(summary.weeks.map(\.weekStart) == ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(summary.weeks.map(\.isIncomplete) == [true, false, false, false, false])
        #expect(summary.weeks.map(\.sessions) == [1, 0, 1, 1, 1])
        #expect(summary.totalSessions == 4)
        // The Sep 1 week is left out: 3 sessions over Sep 7 – Sep 30 (24 days).
        #expect(close(summary.averageSessionsPerWeek, 3.0 / (24.0 / 7.0)))

        // Under the limit the same rows are the whole range.
        let complete = ProgressTrainingMath.summary(
            workouts: workouts,
            details: [:],
            startDayKey: "2026-09-01",
            todayKey: "2026-09-30",
            listLimit: 5
        )
        #expect(complete.sessionListCutoff == nil)
        #expect(complete.weeks.allSatisfy { !$0.isIncomplete })
        #expect(close(complete.averageSessionsPerWeek, 4.0 / (30.0 / 7.0)))
    }

    @Test func truncatedListEndingOnAllStartKeepsThatWeekIncomplete() {
        // All starts at the oldest completed session, which is also the
        // oldest row of the full list.
        let workouts = [
            ProgressBridgeWorkout(id: "a", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "b", sessionDate: "2026-09-10"),
            ProgressBridgeWorkout(id: "c", sessionDate: "2026-09-09"),
        ]
        let now = ProgressTrainingMath.parseTimestamp("2026-09-30T16:00:00Z")!
        let all = ProgressTrainingMath.rangeDayKeys(for: .allTime, now: now, oldestWorkoutDay: "2026-09-09")
        #expect(all.start == "2026-09-09")
        #expect(all.today == "2026-09-30")

        let summary = ProgressTrainingMath.summary(
            workouts: workouts,
            details: [:],
            startDayKey: all.start,
            todayKey: all.today,
            listLimit: 3
        )
        #expect(summary.listTruncated)
        #expect(summary.sessionListCutoff == "2026-09-09")
        #expect(summary.unloadedWeeks == 0)
        #expect(summary.weeks.map(\.weekStart) == ["2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28"])
        #expect(summary.weeks.map(\.isIncomplete) == [true, false, false, false])
        #expect(summary.weeks.map(\.sessions) == [2, 0, 0, 1])
        // Sep 14 – Sep 30 (17 days) with 1 session; the cutoff week is not averaged.
        #expect(close(summary.averageSessionsPerWeek, 1.0 / (17.0 / 7.0)))
    }

    @Test func failedDetailsLeaveTotalsUnknownNotZero() {
        // Wed Sep 16 – Sep 30: two empty weeks, then two sessions whose
        // sets all failed to load.
        let workouts = [
            ProgressBridgeWorkout(id: "a", sessionDate: "2026-09-29"),
            ProgressBridgeWorkout(id: "b", sessionDate: "2026-09-30"),
        ]
        let failed = ProgressTrainingMath.summary(
            workouts: workouts,
            details: [:],
            startDayKey: "2026-09-16",
            todayKey: "2026-09-30",
            failedDetails: 2
        )
        #expect(failed.weeks.map(\.sessions) == [0, 0, 2])
        #expect(failed.weeks.map(\.sets) == [0, 0, nil])
        // The empty weeks' zeros don't make the total a known zero.
        #expect(failed.totalSets == nil)
        #expect(failed.totalVolumeLb == nil)
        #expect(!failed.hasPartialDetails)

        // One of two loaded: a partial total, flagged for the card's note.
        let partial = ProgressTrainingMath.summary(
            workouts: workouts,
            details: ["b": ProgressWorkoutTotals(sets: 5, volumeLb: 500)],
            startDayKey: "2026-09-16",
            todayKey: "2026-09-30",
            failedDetails: 1
        )
        #expect(partial.totalSets == 5)
        #expect(close(partial.totalVolumeLb, 500))
        #expect(partial.hasPartialDetails)

        // Everything loaded: a complete total.
        let loaded = ProgressTrainingMath.summary(
            workouts: workouts,
            details: ["a": ProgressWorkoutTotals(sets: 4, volumeLb: 400), "b": ProgressWorkoutTotals(sets: 5, volumeLb: 500)],
            startDayKey: "2026-09-16",
            todayKey: "2026-09-30"
        )
        #expect(loaded.totalSets == 9)
        #expect(close(loaded.totalVolumeLb, 900))
        #expect(!loaded.hasPartialDetails)

        // No sessions in range: a known zero.
        let none = ProgressTrainingMath.summary(
            workouts: [],
            details: [:],
            startDayKey: "2026-09-16",
            todayKey: "2026-09-30"
        )
        #expect(none.totalSets == 0)
        #expect(none.totalVolumeLb == 0)
    }

    // MARK: - Nutrition

    @Test func foodRangeStatsUseInjectedNowAndCalendar() {
        let now = date(2026, 6, 30, hour: 18)
        let entries = [
            FoodEntry(name: "Oats", calories: 500, protein: 20, carbs: 80, fat: 10, timestamp: date(2026, 6, 30, hour: 8), source: .manual),
            FoodEntry(name: "Rice", calories: 300, protein: 6, carbs: 60, fat: 2, timestamp: date(2026, 6, 24, hour: 12), source: .manual),
            FoodEntry(name: "Old", calories: 900, protein: 1, carbs: 1, fat: 1, timestamp: date(2026, 6, 23, hour: 12), source: .manual),
        ]
        let stats = ProgressFoodRangeStats.compute(
            entries: entries,
            dayCount: 7,
            profile: UserProfile.default,
            optionalGoals: OptionalNutrientGoals.defaults,
            now: now,
            calendar: calendar
        )
        // Jun 24 – Jun 30 in the injected calendar, not the device clock.
        #expect(stats.loggedDays == 2)
        #expect(stats.dailyCalories.map { $0.calories } == [300, 500])
        #expect(stats.dailyCalories.first.map { $0.date } == calendar.startOfDay(for: date(2026, 6, 24)))
        #expect(close(stats.avgProtein, 13))
    }

    @Test func trainingRangeKeysShareOneEasternCalendar() {
        // 02:30 UTC Oct 1 is 22:30 Sep 30 in New York.
        let now = ProgressTrainingMath.parseTimestamp("2026-10-01T02:30:00Z")!
        let week = ProgressTrainingMath.rangeDayKeys(for: .week, now: now, oldestWorkoutDay: "2025-01-01")
        #expect(week.start == "2026-09-24")
        #expect(week.today == "2026-09-30")
        let month = ProgressTrainingMath.rangeDayKeys(for: .month, now: now, oldestWorkoutDay: nil)
        #expect(month.start == "2026-09-01")
        // Crosses the Nov 1 DST change: still whole days.
        let late = ProgressTrainingMath.parseTimestamp("2026-11-05T04:30:00Z")! // Nov 4, 23:30 EST
        let lateWeek = ProgressTrainingMath.rangeDayKeys(for: .week, now: late, oldestWorkoutDay: nil)
        #expect(lateWeek.start == "2026-10-29")
        #expect(lateWeek.today == "2026-11-04")

        let all = ProgressTrainingMath.rangeDayKeys(for: .allTime, now: now, oldestWorkoutDay: "2026-03-02")
        #expect(all.start == "2026-03-02")
        #expect(all.today == "2026-09-30")
        let allEmpty = ProgressTrainingMath.rangeDayKeys(for: .allTime, now: now, oldestWorkoutDay: nil)
        #expect(allEmpty.start == "2026-09-30")
    }

    @Test func detailCacheInvalidationForcesRefetch() {
        var cache = ProgressWorkoutDetailCache()
        let bridge = "https://bridge.example"
        let other = "https://other.example"
        cache.store(ProgressWorkoutTotals(sets: 10, volumeLb: 1_000), id: "w1", baseURL: bridge)
        cache.store(ProgressWorkoutTotals(sets: 5, volumeLb: 500), id: "w2", baseURL: bridge)
        cache.store(ProgressWorkoutTotals(sets: 3, volumeLb: 300), id: "w1", baseURL: other)

        let before = cache.lookup(ids: ["w1", "w2", "w3"], baseURL: bridge)
        #expect(before.found["w1"] == ProgressWorkoutTotals(sets: 10, volumeLb: 1_000))
        #expect(before.missing == ["w3"])

        // Retry / pull to refresh: every workout from this bridge is refetched.
        cache.invalidate(baseURL: bridge)
        let after = cache.lookup(ids: ["w1", "w2"], baseURL: bridge)
        #expect(after.found.isEmpty)
        #expect(after.missing == ["w1", "w2"])
        #expect(cache.lookup(ids: ["w1"], baseURL: other).found["w1"]?.sets == 3)

        // Fetched totals (an edited workout) replace the old ones.
        cache.store(ProgressWorkoutTotals(sets: 12, volumeLb: 1_400), id: "w1", baseURL: bridge)
        cache.store(ProgressWorkoutTotals(sets: 14, volumeLb: 1_600), id: "w1", baseURL: bridge)
        #expect(cache.lookup(ids: ["w1"], baseURL: bridge).found["w1"] == ProgressWorkoutTotals(sets: 14, volumeLb: 1_600))
    }

    // MARK: - Bridge JSON

    @Test func decodesWorkoutListTolerantly() throws {
        let json = """
        {"workouts":[
          {"id":"w1","kind":"COMPLETED","program_day":"3-wed","title":"Pull / Hinge","session_date":"2026-09-30T00:00:00.000Z","recorded_at":"2026-09-30T12:04:47.384Z","units":"lb","notes":[],"synthetic":false},
          {"id":42,"kind":"completed","session_date":"2026-09-27"},
          {"kind":"COMPLETED","session_date":"2026-09-26"},
          {"id":"w4","kind":"COMPLETED","session_date":null,"recorded_at":"2026-09-25T12:00:00Z","synthetic":true},
          {"id":"w5","kind":"strength","session_date":"2026-09-24","synthetic":null}
        ]}
        """
        let workouts = try ProgressTrainingMath.decodeWorkouts(Data(json.utf8))
        #expect(workouts.map(\.id) == ["w1", "42", "w4", "w5"])
        #expect(workouts[0].programDay == "3-wed")
        #expect(workouts[0].title == "Pull / Hinge")
        #expect(ProgressTrainingMath.dayKey(for: workouts[0]) == "2026-09-30")
        #expect(workouts.map(ProgressTrainingMath.isCompleted) == [true, true, false, false])
        #expect(workouts[2].synthetic == true)
        #expect(workouts[3].synthetic == nil)
        #expect(throws: (any Error).self) {
            try ProgressTrainingMath.decodeWorkouts(Data(#"{"error":"unauthorized"}"#.utf8))
        }
    }

    @Test func decodesWorkoutDetailWithStringNumbersAndNulls() throws {
        let json = """
        {"workout":{"id":"w1","kind":"COMPLETED","program_day":"3-wed","title":"Pull / Hinge","session_date":"2026-09-30T00:00:00.000Z"},
         "sets":[
           {"id":"97","workout_id":"w1","set_order":0,"exercise":"Cable pull-through","load_lb":35,"reps":12,"rir":3,"rpe":null,"logged_at":"2026-09-30T12:10:00.000Z"},
           {"id":98,"workout_id":"w1","set_order":"1","exercise":"RDL","load_lb":"135.5","reps":"8","rir":null},
           {"id":"99","exercise":"Pull-up","load_lb":null,"reps":10},
           {"id":"100","exercise":"Row","load_lb":"n/a","reps":8},
           "garbage"
         ]}
        """
        let detail = try ProgressTrainingMath.decodeWorkoutDetail(Data(json.utf8))
        #expect(detail.sets.count == 4)
        #expect(detail.sets[0].exercise == "Cable pull-through")
        #expect(detail.sets[1].id == "98")
        #expect(detail.sets[1].loadLb == 135.5)
        #expect(detail.sets[1].reps == 8)
        #expect(detail.sets[2].loadLb == nil)
        #expect(detail.sets[3].loadLb == nil)
        // 35 × 12 + 135.5 × 8; bodyweight / unreadable loads add sets but no volume.
        #expect(detail.totals == ProgressWorkoutTotals(sets: 4, volumeLb: 1_504))

        let noSets = try ProgressTrainingMath.decodeWorkoutDetail(Data(#"{"workout":{"id":"w2"},"sets":[]}"#.utf8))
        #expect(noSets.totals == ProgressWorkoutTotals(sets: 0, volumeLb: 0))
        #expect(throws: (any Error).self) {
            try ProgressTrainingMath.decodeWorkoutDetail(Data(#"{"error":"not_found"}"#.utf8))
        }
    }

    @Test func bridgeConfigMatchesNeonBridgeRequests() {
        let config = ProgressBridgeConfig(baseURL: "https://jl-workout-ingest.vercel.app", apiKey: "secret")
        #expect(config.isConfigured)
        let request = config.request(path: "/api/workouts", queryItems: [URLQueryItem(name: "limit", value: "200")])
        #expect(request?.url?.absoluteString == "https://jl-workout-ingest.vercel.app/api/workouts?limit=200")
        let detail = config.request(path: ProgressBridgeConfig.workoutPath(id: "8c1f-2a"), queryItems: [])
        #expect(detail?.url?.absoluteString == "https://jl-workout-ingest.vercel.app/api/workouts/8c1f-2a")
        #expect(ProgressBridgeConfig.workoutPath(id: "a/b c") == "/api/workouts/a%2Fb%20c")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request?.httpMethod == "GET")

        #expect(!ProgressBridgeConfig(baseURL: "  ", apiKey: nil).isConfigured)
        #expect(!ProgressBridgeConfig(baseURL: "not a url", apiKey: nil).isConfigured)
        #expect(ProgressBridgeConfig(baseURL: "", apiKey: nil).request(path: "/api/workouts", queryItems: []) == nil)
        let anonymous = ProgressBridgeConfig(baseURL: "https://example.invalid", apiKey: nil)
            .request(path: "/api/workouts", queryItems: [URLQueryItem(name: "limit", value: "200")])
        #expect(anonymous?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
