import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct JevPlausibilityTests {
    private let credentials = JevCredentials(endpoint: .direct, apiKey: "test-key", model: "jev-latest")

    init() { TypeSafeStub.reset() }

    @Test func greyFlagShownOnlyWhenJevSaysMistake() async {
        let flag = PlausibilityFlag(id: "w", severity: .grey, title: "Weight", message: "Check", fact: "Body weight moved about 2% since yesterday.")
        TypeSafeStub.handler = { _, _ in (200, [:], Self.noul(0.8)) }
        let shown = await PlausibilityReview.visible([flag], router: makeRouter(), localActive: true, tieBreak: true)
        #expect(shown.count == 1)
        TypeSafeStub.reset()
        TypeSafeStub.handler = { _, _ in (200, [:], Self.noul(0.3)) }
        let hidden = await PlausibilityReview.visible([flag], router: makeRouter(), localActive: true, tieBreak: true)
        #expect(hidden.isEmpty)
    }

    @Test func greyFlagHiddenOnTimeout() async {
        TypeSafeStub.delay = 2
        TypeSafeStub.handler = { _, _ in (200, [:], Self.noul(0.9)) }
        let flag = PlausibilityFlag(id: "w", severity: .grey, title: "Weight", message: "Check", fact: "Body weight moved about 2% since yesterday.")
        let started = Date()
        let visible = await PlausibilityReview.visible([flag], router: makeRouter(), localActive: true, tieBreak: true)
        #expect(visible.isEmpty)
        #expect(Date().timeIntervalSince(started) < 1.2)
    }

    @Test func strongFlagNeedsNoJevCall() async {
        let flag = PlausibilityFlag(id: "s", severity: .strong, title: "Unit", message: "Check the unit", fact: "The load is close to a kg/lb conversion.")
        let visible = await PlausibilityReview.visible([flag], router: makeRouter(), localActive: true, tieBreak: true)
        #expect(visible.count == 1)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func stateHasNoAbsoluteBodyWeight() async throws {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.noul(0.9)) }
        let flag = PlausibilityFlag(id: "w", severity: .grey, title: "Weight", message: "Check", fact: "Body weight moved about 2% since yesterday, entered in the user's usual unit.")
        _ = await PlausibilityReview.visible([flag], router: makeRouter(), localActive: true, tieBreak: true)
        let body = try #require(TypeSafeStub.requests.first?.1)
        let raw = String(decoding: body, as: UTF8.self)
        #expect(raw.range(of: #"\d+(\.\d+)?\s*(kg|lb)"#, options: .regularExpression) == nil)
    }

    @Test func killSwitchNoFlagsAtAll() async {
        let flags = [
            PlausibilityFlag(id: "s", severity: .strong, title: "Unit", message: "Check", fact: "relative"),
            PlausibilityFlag(id: "g", severity: .grey, title: "Close", message: "Check", fact: "relative")
        ]
        let visible = await PlausibilityReview.visible(flags, router: makeRouter(), localActive: false, tieBreak: true)
        #expect(visible.isEmpty)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    private func makeRouter() -> JevRouter {
        JevRouter(
            credentials: { credentials },
            isActive: { _ in true },
            killSwitch: { false },
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
        let defaults = UserDefaults(suiteName: "jev.plausibility.\(name)")!
        defaults.removePersistentDomain(forName: "jev.plausibility.\(name)")
        return defaults
    }

    private static func noul(_ value: Double) -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": ["flag_1": ["type": "noul", "noul": value]],
            "usage": ["input_tokens": 8, "output_tokens": 1]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }
}
