import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct JevExerciseMatchTests {
    private let credentials = JevCredentials(endpoint: .direct, apiKey: "test-key", model: "jev-latest")

    init() { TypeSafeStub.reset() }

    @Test func parserTable() {
        let bench = WorkoutLineParser.parse("bench 3x8 80kg")
        #expect(bench?.first?.name == "bench")
        #expect(bench?.first?.sets == 3)
        #expect(bench?.first?.reps == 8)
        #expect(bench?.first?.weight == "80")
        #expect(bench?.first?.unit == "kg")
        let pullups = WorkoutLineParser.parse("3x10 pullups")
        #expect(pullups?.first?.name == "pullups")
        #expect(pullups?.first?.sets == 3)
        let squat = WorkoutLineParser.parse("squat 5 sets of 5 at 100 kg")
        #expect(squat?.first?.sets == 5)
        #expect(squat?.first?.reps == 5)
        #expect(squat?.first?.weight == "100")
        let run = WorkoutLineParser.parse("run 20 min")
        #expect(run?.first?.timed == true)
        #expect(run?.first?.minutes == "20")
        let curls = WorkoutLineParser.parse("curls 3x12 @8")
        #expect(curls?.first?.rpe == "8")
        #expect(WorkoutLineParser.parse("yesterday bench 3x8") == nil)
        #expect(WorkoutLineParser.parse("bench heavy") == nil)
        #expect(WorkoutLineParser.parse("bench 3x8 80 stone") == nil)
    }

    @Test func aliasHitMakesZeroRequests() async {
        let cache = cache("alias")
        cache.store(fragment: "bench", id: "Barbell_Bench_Press")
        let draft = await WorkoutFastPath.draft(
            description: "bench 3x8 80kg",
            date: .now,
            unit: .kg,
            library: library,
            router: makeRouter(),
            aliases: cache,
            isEnabled: { true }
        )
        #expect(draft?.exercises.first?.exerciseID == "Barbell_Bench_Press")
        #expect(draft?.exercises.first?.sets.count == 3)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func oneRequestForAllUnresolvedLines() async throws {
        TypeSafeStub.handler = { _, body in (200, [:], Self.confidentBody(body)) }
        _ = await WorkoutFastPath.draft(
            description: "bench 3x8 80kg, pullups 3x10",
            date: .now,
            unit: .kg,
            library: library,
            router: makeRouter(),
            aliases: cache("one"),
            isEnabled: { true }
        )
        #expect(TypeSafeStub.requests.count == 1)
        let body = try #require(TypeSafeStub.requests.first?.1)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let questions = try #require(json["questions"] as? [String: Any])
        #expect(Set(questions.keys) == ["ex_1", "ex_2"])
        let first = try #require(questions["ex_1"] as? [String: Any])
        let criteria = try #require(first["criteria"] as? [String: Any])
        #expect(criteria.keys.contains("none"))
        #expect(criteria.keys.contains("Barbell_Bench_Press"))
    }

    @Test func allConfidentBuildsValidDraft() async throws {
        TypeSafeStub.handler = { _, body in (200, [:], Self.confidentBody(body)) }
        let draft = try #require(await WorkoutFastPath.draft(
            description: "bench 3x8 80kg, pullups 3x10",
            date: .now,
            unit: .kg,
            library: library,
            router: makeRouter(),
            aliases: cache("valid"),
            isEnabled: { true }
        ))
        #expect(try draft.planned(library: library).count == 2)
        #expect(draft.exercises.allSatisfy { $0.exerciseID != nil })
        #expect(draft.exercises[0].sets.count == 3)
        #expect(draft.exercises[0].unit == "kg")
    }

    @Test func anyLineLowConfidenceFallsBack() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.choiceJSON(p: 0.4, confidence: 0.4)) }
        let draft = await WorkoutFastPath.draft(
            description: "bench 3x8 80kg",
            date: .now,
            unit: .kg,
            library: library,
            router: makeRouter(),
            aliases: cache("low"),
            isEnabled: { true }
        )
        #expect(draft == nil)
    }

    @Test func noneFallsBack() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.noneJSON()) }
        let draft = await WorkoutFastPath.draft(
            description: "bench 3x8 80kg",
            date: .now,
            unit: .kg,
            library: library,
            router: makeRouter(),
            aliases: cache("none"),
            isEnabled: { true }
        )
        #expect(draft == nil)
    }

    @Test func confidentAcceptPersistsAliasThenSecondRunMakesZeroRequests() async {
        TypeSafeStub.handler = { _, body in (200, [:], Self.confidentBody(body)) }
        let aliases = cache("persist")
        let router = makeRouter()
        let first = await WorkoutFastPath.draft(description: "bench 3x8 80kg", date: .now, unit: .kg, library: library, router: router, aliases: aliases, isEnabled: { true })
        #expect(first != nil)
        #expect(TypeSafeStub.requests.count == 1)
        let second = await WorkoutFastPath.draft(description: "bench 3x8 80kg", date: .now, unit: .kg, library: library, router: router, aliases: aliases, isEnabled: { true })
        #expect(second?.exercises.first?.exerciseID == first?.exercises.first?.exerciseID)
        #expect(TypeSafeStub.requests.count == 1)
    }

    @Test func staleAliasIgnored() async {
        TypeSafeStub.handler = { _, body in (200, [:], Self.confidentBody(body)) }
        let aliases = cache("stale")
        aliases.store(fragment: "bench", id: "Missing_Exercise")
        let draft = await WorkoutFastPath.draft(description: "bench 3x8 80kg", date: .now, unit: .kg, library: library, router: makeRouter(), aliases: aliases, isEnabled: { true })
        #expect(draft?.exercises.first?.exerciseID != "Missing_Exercise")
        #expect(aliases.id(for: "bench", library: library) != "Missing_Exercise")
    }

    @Test func followUpJSONSkipsFastPath() async {
        let draft = await WorkoutFastPath.draft(description: "{\"original_workout\":\"bench\"}", date: .now, unit: .kg, library: library, router: makeRouter(), aliases: cache("json"), isEnabled: { true })
        #expect(draft == nil)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func timeoutFallsBack() async {
        TypeSafeStub.delay = 2
        TypeSafeStub.handler = { _, body in (200, [:], Self.confidentBody(body)) }
        let started = Date()
        let draft = await WorkoutFastPath.draft(description: "bench 3x8 80kg", date: .now, unit: .kg, library: library, router: makeRouter(), aliases: cache("timeout"), isEnabled: { true })
        #expect(draft == nil)
        #expect(Date().timeIntervalSince(started) < 1.2)
    }

    private var library: [ExerciseLibraryItem] {
        [
            ExerciseLibraryItem(id: "Barbell_Bench_Press", name: "Barbell Bench Press", category: "strength", rawEquipment: "Barbell"),
            ExerciseLibraryItem(id: "Pullups", name: "Pullups", category: "strength", rawEquipment: "Body Only"),
            ExerciseLibraryItem(id: "Running", name: "Running", category: "cardio", rawEquipment: "None")
        ]
    }

    private func makeRouter() -> JevRouter {
        JevRouter(
            credentials: { credentials },
            isActive: { _ in true },
            killSwitch: { false },
            session: stubSession(),
            telemetry: JevRouterTelemetry(defaults: suite("telemetry-\(UUID().uuidString)"))
        )
    }

    private func cache(_ name: String) -> ExerciseAliasCache {
        ExerciseAliasCache(defaults: suite("alias-\(name)"))
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TypeSafeStub.self]
        return URLSession(configuration: configuration)
    }

    private func suite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "jev.exercise.\(name)")!
        defaults.removePersistentDomain(forName: "jev.exercise.\(name)")
        return defaults
    }

    private static func confidentBody(_ body: Data?) -> Data {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let questions = json["questions"] as? [String: Any] else { return Data() }
        var answers: [String: Any] = [:]
        for (key, value) in questions {
            let criteria = (value as? [String: Any])?["criteria"] as? [String: Any] ?? [:]
            let choice = criteria.keys.first { $0 != "none" } ?? "none"
            answers[key] = [
                "type": "choice",
                "choice": choice,
                "confidence": 0.9,
                "probabilities": [choice: 0.9, "none": 0.04]
            ]
        }
        let root: [String: Any] = ["model": "jev-1.13.0", "answers": answers, "usage": ["input_tokens": 40, "output_tokens": 4]]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }

    private static func choiceJSON(p: Double, confidence: Double) -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": ["ex_1": ["type": "choice", "choice": "Barbell_Bench_Press", "confidence": confidence, "probabilities": ["Barbell_Bench_Press": p, "none": 0.5]]],
            "usage": ["input_tokens": 10, "output_tokens": 2]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }

    private static func noneJSON() -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": ["ex_1": ["type": "choice", "choice": "none", "confidence": 0.95, "probabilities": ["none": 0.92, "Barbell_Bench_Press": 0.05]]],
            "usage": ["input_tokens": 10, "output_tokens": 2]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }
}
