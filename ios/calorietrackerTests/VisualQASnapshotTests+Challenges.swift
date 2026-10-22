import SwiftUI
import UIKit
import XCTest
@testable import calorietracker

/// Challenges shots 79-83 (default + axL, Pro + SE) and the 44 pt hit-area gate.
/// Everything is pinned to Fri 2026-10-23 20:00 New York: day 12 of the swings challenge.
extension VisualQASnapshotTests {
    func test79ChallengesList() async throws {
        let fixture = try VisualQAChallengeFixture()
        try await capture("79-challenges-list") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { ChallengeListView() }
            }
            .environment(fixture.store)
        }
    }

    func test80ChallengeCreate() async throws {
        let fixture = try VisualQAChallengeFixture()
        try await capture("80-challenge-create", heightMultiplier: 1.6, sheet: {
            ChallengeCreateView(draft: VisualQAChallengeFixture.createDraft)
                .environment(fixture.store)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { ChallengeListView() }
            }
            .environment(fixture.store)
        }
    }

    func test81ChallengeDetail() async throws {
        let fixture = try VisualQAChallengeFixture()
        try await capture("81-challenge-detail", heightMultiplier: 2) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Challenges") {
                    ChallengeDetailView(challengeID: VisualQAChallengeFixture.swingsID)
                }
            }
            .environment(fixture.store)
        }
    }

    func test82ChallengeQuickAdd() async throws {
        let fixture = try VisualQAChallengeFixture()
        try await capture("82-challenge-quick-add", sheet: {
            ChallengeQuickAddSheet(challengeID: VisualQAChallengeFixture.swingsID)
                .environment(fixture.store)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Challenges") {
                    ChallengeDetailView(challengeID: VisualQAChallengeFixture.swingsID)
                }
            }
            .environment(fixture.store)
        }
    }

    func test83ChallengeRewardUnlocked() async throws {
        let fixture = try VisualQAChallengeFixture()
        let unlock = RewardUnlock(challengeID: VisualQAChallengeFixture.swingsID, rewardKey: "percent.25", title: "25% done")
        try await capture("83-challenge-reward-unlocked", sheet: {
            RewardUnlockedView(unlock: unlock, challengeTitle: "10K KB SWINGS", onClaim: {}, onDone: {})
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Challenges") {
                    ChallengeDetailView(challengeID: VisualQAChallengeFixture.swingsID)
                }
            }
            .environment(fixture.store)
        }
    }

    /// Gate: at the largest captured text size (axL), the detail Log button, the quick-add
    /// Log button and every quick-add chip keep a hit area of at least 44 x 44 pt.
    func test84ChallengeHitTargets() async throws {
        let fixture = try VisualQAChallengeFixture()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene; tests must run hosted in the app"
        )
        let chips = VisualQAChallengeFixture.chipCount
        let screens: [(name: String, view: AnyView, identifiers: [String])] = [
            (
                "detail",
                AnyView(NavigationStack { ChallengeDetailView(challengeID: VisualQAChallengeFixture.swingsID) }),
                ["challenge.detail.log"]
            ),
            (
                "quick-add",
                AnyView(ChallengeQuickAddSheet(challengeID: VisualQAChallengeFixture.swingsID)),
                ["challenge.quickAdd.log"] + (0..<chips).map { "challenge.quickAdd.chip.\($0)" }
            ),
        ]
        for screen in screens {
            let stores = VisualQAStores()
            let root = stores.inject(screen.view.environment(fixture.store), dynamicType: .accessibility3)
                .transaction { $0.disablesAnimations = true }
            let window = UIWindow(windowScene: scene)
            window.frame = scene.screen.bounds
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: AnyView(root))
            host.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
            window.rootViewController = host
            VisualQAGraveyard.keep(stores, window, host)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(1500))
            window.layoutIfNeeded()
            let frames = VisualQAChallengeFixture.anchorFrames(in: window, identifiers: Set(screen.identifiers))
            for identifier in screen.identifiers {
                guard let frame = frames[identifier] else {
                    XCTFail("\(screen.name): missing \(identifier)")
                    continue
                }
                XCTAssertGreaterThanOrEqual(frame.width, 44, "\(screen.name): \(identifier) is \(frame.width) pt wide")
                XCTAssertGreaterThanOrEqual(frame.height, 44, "\(screen.name): \(identifier) is \(frame.height) pt tall")
            }
            window.isHidden = true
        }
    }
}

/// A real ChallengeStore in a temporary directory, seeded through its public mutations.
@MainActor
final class VisualQAChallengeFixture {
    static let swingsID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000079")!
    static let waterID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000080")!
    static let alcoholID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000081")!
    static let swingsChips: [Double] = [25, 50, 100]
    static var chipCount: Int { swingsChips.count }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    /// Fri 2026-10-23 20:00 New York.
    static let referenceNow: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 20)) ?? .now
    static let start = ChallengeDay(year: 2026, month: 10, day: 12)

    static var createDraft: ChallengeDraft {
        var draft = ChallengeDraft()
        draft.title = "10K KB swings"
        draft.customName = "KB swings"
        draft.customUnit = "reps"
        draft.targetText = "10000"
        draft.stakeText = "$20 to Sam"
        return draft
    }

    let store: ChallengeStore

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-qa-challenges-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("challenges.v1.json")
        store = ChallengeStore(fileURL: url, calendar: Self.calendar)
        let now = Self.referenceNow
        let created = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7)) ?? now

        try store.create(Self.challenge(
            id: Self.swingsID, title: "10K KB SWINGS", kind: .total(10_000),
            metric: .custom(name: "KB swings", unit: "reps"), grace: 0, chips: Self.swingsChips,
            created: created.addingTimeInterval(120), stake: ChallengeStake(text: "$20 to Sam")
        ), now: now)
        let swings: [Double] = [300, 320, 340, 330, 335, 440, 300, 330, 310, 345, 340, 210]
        for (offset, value) in swings.enumerated() {
            try store.add(value: value, day: Self.start.adding(days: offset), to: Self.swingsID, now: now)
        }

        try store.create(Self.challenge(
            id: Self.waterID, title: "WATER 3 L", kind: .dailyHabit(.atLeast(3_000)),
            metric: .waterAppLog, grace: 2, chips: [], created: created.addingTimeInterval(60), stake: nil
        ), now: now)
        // Day 5 missed (one grace day used); today (day 12) already hit.
        var water: [ChallengeDay: Double] = [:]
        for offset in 0..<12 {
            water[Self.start.adding(days: offset)] = offset == 4 ? 1_800 : 3_000 + Double(offset * 50)
        }
        store.setAutoValues(water, availability: .available, for: Self.waterID, now: now)

        try store.create(Self.challenge(
            id: Self.alcoholID, title: "NO ALCOHOL", kind: .dailyHabit(.checkIn),
            metric: .custom(name: "Alcohol-free day", unit: "day"), grace: 2, chips: [], created: created, stake: nil
        ), now: now)
        for offset in 0..<11 {
            try store.setCheckIn(true, day: Self.start.adding(days: offset), for: Self.alcoholID, now: now)
        }

        store.reconcile(now: now)
        // Shots show screens, not the unlock pop-up (shot 83 draws it directly).
        for unlock in store.pendingUnlocks {
            store.acknowledge(unlock)
        }
        VisualQAGraveyard.keep(store)
    }

    private static func challenge(
        id: UUID,
        title: String,
        kind: ChallengeKind,
        metric: ChallengeMetric,
        grace: Int,
        chips: [Double],
        created: Date,
        stake: ChallengeStake?
    ) -> Challenge {
        Challenge(
            id: id,
            title: title,
            kind: kind,
            metric: metric,
            startDay: start,
            durationDays: 30,
            graceDays: grace,
            rewards: ChallengeRules.defaultRewards(for: kind),
            stake: stake,
            reminder: .standard,
            quickAddChips: chips,
            createdAt: created,
            endedEarlyAt: nil
        )
    }

    /// Frames (in window points) of views tagged with one of `identifiers` via
    /// accessibility identifier or layer name. Keeps the largest frame per identifier.
    static func anchorFrames(in window: UIWindow, identifiers: Set<String>) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        func walk(_ view: UIView) {
            let candidates = [view.accessibilityIdentifier, view.layer.name].compactMap { $0 }
            if let identifier = candidates.first(where: { identifiers.contains($0) }) {
                let frame = view.convert(view.bounds, to: window)
                let existingArea = frames[identifier].map { $0.width * $0.height } ?? -1
                if frame.width * frame.height > existingArea {
                    frames[identifier] = frame
                }
            }
            for subview in view.subviews { walk(subview) }
        }
        walk(window)
        return frames
    }
}
