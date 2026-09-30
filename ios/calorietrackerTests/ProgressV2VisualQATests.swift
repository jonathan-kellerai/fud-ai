import SwiftUI
import UIKit
import XCTest
@testable import calorietracker

/// Renders the Progress tab to PNG for visual QA, at the default text size and
/// at the largest accessibility size. Nothing here ships in the app.
///
/// CI runs this class next to VisualQASnapshotTests on a Pro-size and an SE simulator:
///   xcodebuild test ... -only-testing:calorietrackerTests/ProgressV2VisualQATests
/// PNGs go to $VISUAL_QA_DIR (TEST_RUNNER_VISUAL_QA_DIR) as "<device>_<size>_p2-*.png"
/// and are attached to the xcresult bundle.
///
/// All data is injected through `ProgressTabView(fixture:)` or straight into the
/// cards: no HealthKit query and no bridge request is made.
@MainActor
final class ProgressV2VisualQATests: XCTestCase {
    private static let sizes: [(label: String, size: DynamicTypeSize, category: UIContentSizeCategory)] = [
        ("default", .large, .large),
        ("ax5", .accessibility5, .accessibilityExtraExtraExtraLarge),
    ]

    // MARK: - Body composition (full tab, tall canvas)

    func testP2Weight() async throws {
        try await capture("p2-weight", heights: (2.4, 5)) {
            VisualQATabShell(selected: .progress) {
                ProgressTabView(fixture: ProgressV2QAFixtures.fixture(metric: .weight))
            }
        }
    }

    func testP2BodyFat() async throws {
        try await capture("p2-bodyfat", heights: (2.4, 5)) {
            VisualQATabShell(selected: .progress) {
                ProgressTabView(fixture: ProgressV2QAFixtures.fixture(metric: .bodyFat))
            }
        }
    }

    func testP2LeanMass() async throws {
        try await capture("p2-leanmass", heights: (2.4, 5)) {
            VisualQATabShell(selected: .progress) {
                ProgressTabView(fixture: ProgressV2QAFixtures.fixture(metric: .leanMass))
            }
        }
    }

    func testP2LeanMassEmpty() async throws {
        try await capture("p2-leanmass-empty", heights: (2.4, 5)) {
            VisualQATabShell(selected: .progress) {
                ProgressTabView(fixture: ProgressV2QAFixtures.fixture(metric: .leanMass, includeLeanMass: false))
            }
        }
    }

    // MARK: - Cards in the tab shell

    func testP2Steps() async throws {
        let summary = ProgressV2QAFixtures.stepsSummary()
        try await capture("p2-steps", heights: (1, 2.2)) {
            VisualQATabShell(selected: .progress) {
                ProgressV2QACardHost {
                    ProgressStepsCard(
                        state: .loaded(summary),
                        rangeDescription: TimeRange.month.rangeDescription,
                        goal: StepsView.dailyGoal
                    )
                }
                .progressV2QAPinned()
            }
        }
    }

    func testP2Training() async throws {
        let summary = ProgressV2QAFixtures.trainingSummary()
        try await capture("p2-training", heights: (1.2, 2.6)) {
            VisualQATabShell(selected: .progress) {
                ProgressV2QACardHost {
                    ProgressTrainingCard(
                        state: .loaded(summary),
                        rangeDescription: TimeRange.threeMonths.rangeDescription,
                        useMetric: false,
                        onRetry: {}
                    )
                }
                .progressV2QAPinned()
            }
        }
    }

    // MARK: - Rendering

    private func capture<Content: View>(
        _ name: String,
        heights: (standard: CGFloat, accessibility: CGFloat),
        @ViewBuilder content: @escaping () -> Content
    ) async throws {
        IronTheme.applyChrome()
        for size in Self.sizes {
            let stores = VisualQAStores()
            let root = AnyView(stores.inject(content(), dynamicType: size.size))
            VisualQAGraveyard.keep(stores, root)
            try await render(
                name: name,
                sizeLabel: size.label,
                category: size.category,
                heightMultiplier: size.size.isAccessibilitySize ? heights.accessibility : heights.standard,
                root: root
            )
        }
    }

    private func render(
        name: String,
        sizeLabel: String,
        category: UIContentSizeCategory,
        heightMultiplier: CGFloat,
        root: AnyView
    ) async throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene; tests must run hosted in the app"
        )
        let screen = scene.screen.bounds
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: screen.width, height: (screen.height * heightMultiplier).rounded())
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = UIColor(IronTheme.canvas)

        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = category
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(IronTheme.canvas)
        window.rootViewController = host
        VisualQAGraveyard.keep(window, host)
        window.makeKeyAndVisible()
        // Let the .task(id:) builders compute and the charts lay out.
        try await Task.sleep(for: .milliseconds(2200))

        let format = UIGraphicsImageRendererFormat()
        format.scale = scene.screen.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let fileName = "\(VisualQAOutput.deviceLabel)_\(sizeLabel)_\(name).png"
        if let data = image.pngData() {
            VisualQAOutput.write(data, named: fileName)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = fileName
            attachment.lifetime = .keepAlways
            add(attachment)
        } else {
            XCTFail("Could not encode \(fileName)")
        }

        // Same rule as VisualQASnapshotTests: never release app objects mid-test
        // (iOS <= 26.2 isolated-deinit double free); hide and keep them instead.
        window.isHidden = true
    }
}

/// One card on the Iron canvas inside a scroll view, like it sits on the tab.
struct ProgressV2QACardHost<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(16)
        }
        .background(IronTheme.canvas)
    }
}

// MARK: - Fixtures

extension View {
    /// Pins the locale, calendar and time zone the cards render with.
    @MainActor
    func progressV2QAPinned() -> some View {
        environment(\.locale, ProgressV2QAFixtures.locale)
            .environment(\.calendar, ProgressV2QAFixtures.calendar)
            .environment(\.timeZone, ProgressV2QAFixtures.calendar.timeZone)
    }
}

/// Deterministic Progress data relative to a fixed "now" (2026-09-30 12:00
/// New York): weight ~190 → 189 lb over 45 days, body fat on a few of the
/// same days, Withings lean mass, steps and a Neon bridge training history.
/// The same `now` and calendar go into `ProgressV2Fixture`, so the tab's
/// windows match the data no matter when or where the tests run.
@MainActor
enum ProgressV2QAFixtures {
    private static let poundsPerKilogram = ProgressV2Math.poundsPerKilogram

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    static let locale = Locale(identifier: "en_US")

    static let now: Date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)) ?? Date(timeIntervalSince1970: 1_790_784_000)

    static func fixture(metric: ProgressCompositionMetric, includeLeanMass: Bool = true) -> ProgressV2Fixture {
        ProgressV2Fixture(
            timeRange: .month,
            metric: metric,
            weightEntries: weightEntries(includeLeanMass: includeLeanMass),
            bodyFatEntries: bodyFatEntries(),
            stepsByDay: stepsByDay(),
            training: .loaded(trainingSummary()),
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    private static func day(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    /// Morning weigh-ins for 45 days, most days, drifting 190 → 189 lb.
    static func weightEntries(includeLeanMass: Bool) -> [WeightEntry] {
        var rows: [WeightEntry] = []
        for offset in stride(from: 44, through: 0, by: -1) where offset % 5 != 3 {
            let progress = Double(44 - offset) / 44
            let noise = sin(Double(offset) * 1.7) * 0.6
            let pounds = 190 - progress + noise
            rows.append(WeightEntry(
                date: day(offset, hour: 7),
                weightKg: pounds / poundsPerKilogram,
                healthSourceName: offset.isMultiple(of: 2) ? "Withings" : nil
            ))
        }
        // A second reading on one day, to exercise daily means.
        rows.append(WeightEntry(date: day(6, hour: 21), weightKg: 190.4 / poundsPerKilogram))
        if includeLeanMass {
            for offset in stride(from: 42, through: 0, by: -3) {
                let pounds = 148.1 + Double(42 - offset) / 42 * 0.6 + sin(Double(offset)) * 0.25
                rows.append(WeightEntry(
                    date: day(offset, hour: 7, minute: 1),
                    weightKg: pounds / poundsPerKilogram,
                    healthSourceName: "Withings",
                    leanBodyMass: true
                ))
            }
        }
        return rows
    }

    /// Body fat on a handful of days, each alongside that day's weigh-in.
    static func bodyFatEntries() -> [BodyFatEntry] {
        let readings: [(offset: Int, percent: Double)] = [
            (40, 22.4), (33, 22.1), (26, 22.0), (19, 21.6), (12, 21.5), (5, 21.2), (1, 21.0),
        ]
        return readings.map { reading in
            BodyFatEntry(
                date: day(reading.offset, hour: 7, minute: 2),
                bodyFatFraction: reading.percent / 100,
                healthSourceName: "Withings"
            )
        }
    }

    static func stepsByDay() -> [Date: Int] {
        let today = calendar.startOfDay(for: now)
        var values: [Date: Int] = [:]
        for offset in 0..<120 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            values[date] = offset % 11 == 10 ? 0 : 5_200 + (offset * 3_137) % 9_400
        }
        return values
    }

    static func stepsSummary() -> ProgressStepsSummary {
        let window = ProgressV2Math.stepsWindow(for: .month, now: now, calendar: calendar)
        return ProgressV2Math.stepsSummary(
            byDay: stepsByDay(),
            window: window,
            goal: StepsView.dailyGoal,
            weekly: false,
            calendar: calendar
        )
    }

    private static func shift(_ key: String, days: Int) -> String? {
        ProgressTrainingMath.shiftDayKey(key, days: days)
    }

    /// Eight weeks of Upper/Lower sessions with per-workout sets, in the
    /// /api/workouts and /api/workouts/{id} shapes.
    static func trainingSummary() -> ProgressTrainingSummary {
        let todayKey = ProgressTrainingMath.rangeDayKeys(for: .threeMonths, now: now, oldestWorkoutDay: nil).today
        let thisMonday = ProgressTrainingMath.mondayKey(for: todayKey) ?? todayKey
        var workouts: [ProgressBridgeWorkout] = []
        var details: [String: ProgressWorkoutTotals] = [:]
        for week in 0..<8 {
            guard let monday = shift(thisMonday, days: -7 * week) else { continue }
            let sessions = week == 3 ? 2 : (week.isMultiple(of: 2) ? 4 : 3)
            for session in 0..<sessions {
                guard let key = shift(monday, days: session * 2), key <= todayKey else { continue }
                let id = "qa-p2-\(week)-\(session)"
                workouts.append(ProgressBridgeWorkout(
                    id: id,
                    kind: "COMPLETED",
                    programDay: "Day\(session + 1)",
                    title: session.isMultiple(of: 2) ? "Lower" : "Upper",
                    sessionDate: "\(key)T00:00:00.000Z"
                ))
                let sets = 16 + (week + session) % 5
                details[id] = ProgressWorkoutTotals(sets: sets, volumeLb: Double(sets * (640 + week * 12)))
            }
        }
        let start = shift(thisMonday, days: -7 * 7) ?? thisMonday
        return ProgressTrainingMath.summary(
            workouts: workouts,
            details: details,
            startDayKey: start,
            todayKey: todayKey
        )
    }
}
