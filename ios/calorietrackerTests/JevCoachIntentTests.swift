import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct JevCoachIntentTests {
    private let credentials = JevCredentials(endpoint: .direct, apiKey: "test-key", model: "jev-latest")

    init() {
        TypeSafeStub.reset()
    }

    @Test func requestHasThreeChoiceQuestionsAndOnlyMessageInState() async throws {
        let text = "how many steps have I done today?"
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answers(intent: "open_chat", intentP: 0.96)) }
        let router = makeRouter()
        _ = await CoachIntentRouter.route(text, router: router, isEnabled: { true }, stepsToday: { 0 }, stepGoal: { 10_000 })
        let recorded = try #require(TypeSafeStub.requests.first)
        let body = try #require(recorded.1)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let state = try #require(json["state"] as? [String: Any])
        #expect(Array(state.keys) == ["message"])
        #expect(state["message"] as? String == text)
        let questions = try #require(json["questions"] as? [String: Any])
        #expect(Set(questions.keys) == ["intent", "program_detail", "steps_detail"])
        for key in ["intent", "program_detail", "steps_detail"] {
            let question = try #require(questions[key] as? [String: Any])
            #expect(question["type"] as? String == "choice")
        }
    }

    @Test func stepsTodayRoutesLocal() async throws {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answers(
                intent: "steps_question",
                intentP: 0.93,
                steps: "today",
                stepsP: 0.9
            ))
        }
        let router = makeRouter()
        let message = await CoachIntentRouter.route(
            "how many steps have I done today?",
            router: router,
            isEnabled: { true },
            stepsToday: { 6420 },
            stepGoal: { 10_000 }
        )
        let content = try #require(message?.content)
        #expect(content.contains("6,420"))
        #expect(content.contains("64%"))
        #expect(content.contains("10,000"))
        #expect(message?.routerAction == .localAnswer)
    }

    @Test func programTodayUsesSchedule() async throws {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answers(
                intent: "program_question",
                intentP: 0.94,
                program: "today_session",
                programP: 0.88
            ))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 28, hour: 12))!
        let router = makeRouter()
        let message = await CoachIntentRouter.route(
            "what's today's session?",
            router: router,
            isEnabled: { true },
            program: { Self.upperA() },
            now: { date },
            calendar: calendar
        )
        let content = try #require(message?.content)
        #expect(content.contains("Upper A"))
        #expect(content.contains("Bench press"))
        #expect(content.contains("Row"))
    }

    @Test func programNextAfterLoggingTodayNamesTomorrowsSession() async throws {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answers(
                intent: "program_question",
                intentP: 0.94,
                program: "next_session",
                programP: 0.88
            ))
        }
        let calendar = ProgramWeekRules.easternCalendar
        let date = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 10, day: 6, hour: 16))!
        let history = programCycleRealHistory()
            + [CompletedProgramSession(dayIndex: 1, sessionDate: "2026-10-06", recordedAt: "2026-10-06T11:40:00.000Z")]
        let router = makeRouter()
        let message = await CoachIntentRouter.route(
            "what's my next session?",
            router: router,
            isEnabled: { true },
            program: { TrainingProgramBody.bundledV2() },
            trainingContext: { TrainingDayContext(history: history) },
            now: { date },
            calendar: calendar
        )
        #expect(message?.content == "Lower A is logged today. Next: Upper Push on Wed.")
        #expect(message?.routerAction == .localAnswer)
    }

    @Test func logFoodProducesActionNotEntry() async throws {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answers(intent: "log_food", intentP: 0.95)) }
        let router = makeRouter()
        let text = "log 2 eggs and toast"
        let message = await CoachIntentRouter.route(text, router: router, isEnabled: { true })
        #expect(message?.routerAction == .logFood(text))
        #expect(message?.content.contains("food review") == true)
    }

    @Test func openChatReturnsNil() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answers(intent: "open_chat", intentP: 0.97)) }
        let router = makeRouter()
        let message = await CoachIntentRouter.route("I feel tired today", router: router, isEnabled: { true })
        #expect(message == nil)
    }

    @Test func lowConfidenceReturnsNil() async {
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answers(intent: "steps_question", intentP: 0.9, confidence: 0.2, steps: "today", stepsP: 0.9)) }
        let router = makeRouter()
        let message = await CoachIntentRouter.route("steps?", router: router, isEnabled: { true }, stepsToday: { 100 }, stepGoal: { 10_000 })
        #expect(message == nil)
    }

    @Test func detailOtherReturnsNil() async {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answers(intent: "program_question", intentP: 0.93, program: "other", programP: 0.91))
        }
        let router = makeRouter()
        let message = await CoachIntentRouter.route(
            "what does my program say?",
            router: router,
            isEnabled: { true },
            program: { Self.upperA() }
        )
        #expect(message == nil)
    }

    @Test func imageAttachedSkipsJev() async {
        let router = makeRouter()
        let message = await CoachIntentRouter.route("log this meal", hasImage: true, router: router, isEnabled: { true })
        #expect(message == nil)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func longMessageSkipsJev() async {
        let router = makeRouter()
        let message = await CoachIntentRouter.route(String(repeating: "a", count: 301), router: router, isEnabled: { true })
        #expect(message == nil)
        #expect(TypeSafeStub.requests.isEmpty)
    }

    @Test func timeoutReturnsNil() async {
        TypeSafeStub.delay = 2
        TypeSafeStub.handler = { _, _ in (200, [:], Self.answers(intent: "log_food", intentP: 0.95)) }
        let router = makeRouter()
        let started = Date()
        let message = await CoachIntentRouter.route("log a latte", router: router, isEnabled: { true })
        #expect(message == nil)
        #expect(Date().timeIntervalSince(started) < 1.2)
    }

    @Test func healthKitErrorFallsBackToLLM() async {
        TypeSafeStub.handler = { _, _ in
            (200, [:], Self.answers(intent: "steps_question", intentP: 0.93, steps: "today", stepsP: 0.9))
        }
        let router = makeRouter()
        let message = await CoachIntentRouter.route(
            "how many steps today?",
            router: router,
            isEnabled: { true },
            stepsToday: { throw CoachStepsUnavailable() },
            stepGoal: { 10_000 }
        )
        #expect(message == nil)
        #expect(TypeSafeStub.requests.count == 1)
    }

    @Test func chatMessageDecodesWithoutRouterAction() throws {
        let id = UUID()
        let payload: [String: Any] = [
            "id": id.uuidString,
            "role": "user",
            "content": "hi",
            "timestamp": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let message = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(message.routerAction == nil)
        #expect(message.content == "hi")
        #expect(message.role == .user)
        #expect(message.id == id)
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
        let defaults = UserDefaults(suiteName: "jev.coach.tests.\(name)")!
        defaults.removePersistentDomain(forName: "jev.coach.tests.\(name)")
        return defaults
    }

    private static func upperA() -> TrainingProgramBody {
        TrainingProgramBody(
            startDate: "2026-09-01",
            dailyStepsTarget: 10_000,
            weeks: 4,
            reductionWeek: nil,
            restWeekdays: ["sat", "sun"],
            notes: nil,
            days: [
                TrainingProgramDay(
                    dayIndex: 1,
                    weekday: ProgramWeekday.mon.rawValue,
                    name: "Upper A",
                    conditioning: nil,
                    exercises: [
                        TrainingProgramExercise(order: 0, name: "Bench press", sets: 3, reps: "8"),
                        TrainingProgramExercise(order: 1, name: "Row", sets: 3, reps: "10")
                    ]
                )
            ]
        )
    }

    private static func answers(
        intent: String,
        intentP: Double,
        confidence: Double = 0.9,
        program: String = "other",
        programP: Double = 0.8,
        steps: String = "other",
        stepsP: Double = 0.8
    ) -> Data {
        let root: [String: Any] = [
            "model": "jev-1.13.0",
            "answers": [
                "intent": choice(intent, confidence: confidence, probabilities: spread(intent, intentP, keys: ["log_food", "log_sets", "program_question", "steps_question", "open_chat"])),
                "program_detail": choice(program, confidence: 0.8, probabilities: spread(program, programP, keys: ["today_session", "next_session", "other"])),
                "steps_detail": choice(steps, confidence: 0.8, probabilities: spread(steps, stepsP, keys: ["today", "yesterday", "last_7_days", "goal", "other"]))
            ],
            "usage": ["input_tokens": 30, "output_tokens": 4]
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }

    private static func choice(_ choice: String, confidence: Double, probabilities: [String: Double]) -> [String: Any] {
        [
            "type": "choice",
            "choice": choice,
            "confidence": confidence,
            "probabilities": probabilities
        ]
    }

    private static func spread(_ chosen: String, _ probability: Double, keys: [String]) -> [String: Double] {
        let others = keys.filter { $0 != chosen }
        let remainder = max(0, (1 - probability) / Double(max(others.count, 1)))
        var values: [String: Double] = [chosen: probability]
        for key in others { values[key] = remainder }
        return values
    }
}

private struct CoachStepsUnavailable: Error {}
