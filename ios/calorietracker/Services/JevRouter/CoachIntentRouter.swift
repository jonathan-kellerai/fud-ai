import Foundation

/// Classifies a single Coach message and answers the narrow cases locally.
enum CoachIntentRouter {
    static func route(
        _ text: String,
        hasImage: Bool = false,
        router: JevRouter = .shared,
        isEnabled: () -> Bool = { JevRouterSettings.isActive(.coachIntent) },
        stepsToday: () async throws -> Int = { try await StepsTrackingService.shared.fetchTodaySteps() },
        stepsYesterday: () async throws -> Int = { try await StepsTrackingService.shared.fetchYesterdaySteps() },
        stepsLast7: () async throws -> [Int] = {
            try await StepsTrackingService.shared.fetchLast7Days().map { $0.steps ?? 0 }
        },
        stepGoal: () -> Int = { StepsGoal.current },
        program: () -> TrainingProgramBody? = { ActiveProgramCache.load()?.body },
        now: () -> Date = { Date() },
        calendar: Calendar = .current
    ) async -> ChatMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled() else { return nil }
        if hasImage || trimmed.count > 300 {
            await router.report(.coachIntent, .fellBack(.guardRejected), preview: trimmed)
            return nil
        }
        guard !trimmed.isEmpty else { return nil }

        let state = TypeSafeJSON.object(["message": .string(trimmed)])
        let questions = Self.questions
        let outcome = await router.ask(
            .coachIntent,
            cacheKey: JevText.normalize(trimmed),
            preview: trimmed
        ) { model in
            TypeSafeRequest(state: state, model: model, questions: questions)
        }
        guard case .answered(let response, _, let latency) = outcome else {
            await router.report(.coachIntent, .fellBack(.skipped), preview: trimmed)
            return nil
        }
        guard let intent = JevGates.acceptChoice(
            response.answers["intent"],
            minP: 0.85,
            minConfidence: 0.60,
            minMargin: 0.40,
            reject: ["open_chat"]
        ) else {
            await router.report(
                .coachIntent,
                .fellBack(intentFallback(response.answers["intent"])),
                preview: trimmed,
                latencyMs: latency,
                model: response.model
            )
            return nil
        }

        let message: ChatMessage?
        switch intent {
        case "steps_question":
            guard let detail = JevGates.acceptChoice(
                response.answers["steps_detail"],
                minP: 0.70,
                minConfidence: 0.50,
                minMargin: 0.30,
                reject: ["other"]
            ) else {
                await router.report(.coachIntent, .fellBack(.none), preview: trimmed, latencyMs: latency, model: response.model)
                return nil
            }
            message = await stepsMessage(detail, today: stepsToday, yesterday: stepsYesterday, last7: stepsLast7, goal: stepGoal)
        case "program_question":
            guard let detail = JevGates.acceptChoice(
                response.answers["program_detail"],
                minP: 0.70,
                minConfidence: 0.50,
                minMargin: 0.30,
                reject: ["other"]
            ) else {
                await router.report(.coachIntent, .fellBack(.none), preview: trimmed, latencyMs: latency, model: response.model)
                return nil
            }
            message = programMessage(detail, body: program(), now: now(), calendar: calendar)
        case "log_food":
            message = ChatMessage(
                role: .assistant,
                content: "I'll open the food review so you can check it first.",
                routerAction: .logFood(trimmed)
            )
        case "log_sets":
            message = ChatMessage(
                role: .assistant,
                content: "I'll open today's workout in Training so you can log it there.",
                routerAction: .logWorkout(trimmed)
            )
        default:
            message = nil
        }
        guard let message else {
            await router.report(.coachIntent, .fellBack(.skipped), preview: trimmed, latencyMs: latency, model: response.model)
            return nil
        }
        let confidence = choiceConfidence(response.answers["intent"])
        await router.report(
            .coachIntent,
            .accepted(label: intent, confidence: confidence, llmCallsAvoided: 1),
            preview: trimmed,
            latencyMs: latency,
            model: response.model
        )
        return message
    }

    private static var questions: [String: TypeSafeQuestion] {
        [
            "intent": .choice(
                instructions: .string("What does the user want from this one message to their fitness coach app?"),
                criteria: [
                    ("log_food", "Record food or drink they ate or are eating, e.g. 'log 2 eggs and toast', 'I just had a latte'"),
                    ("log_sets", "Record a finished workout or sets, e.g. 'bench 3x8 at 80 kg', 'log a 30 minute run'"),
                    ("program_question", "Ask what their training program says: today's or the next session, or rest days"),
                    ("steps_question", "Ask about their step count or step goal"),
                    ("open_chat", "Anything else: advice, questions about trends or nutrition, feelings, or several requests at once")
                ]
            ),
            "program_detail": .choice(
                instructions: .string("If the message asks about the training program, what exactly?"),
                criteria: [
                    ("today_session", "What to train today"),
                    ("next_session", "The next session or rest day"),
                    ("other", nil)
                ]
            ),
            "steps_detail": .choice(
                instructions: .string("If the message asks about steps, which period?"),
                criteria: [
                    ("today", nil),
                    ("yesterday", nil),
                    ("last_7_days", "This week or the last seven days"),
                    ("goal", "Their daily step goal"),
                    ("other", nil)
                ]
            )
        ]
    }

    private static func stepsMessage(
        _ detail: String,
        today: () async throws -> Int,
        yesterday: () async throws -> Int,
        last7: () async throws -> [Int],
        goal: () -> Int
    ) async -> ChatMessage? {
        let content: String
        do {
            switch detail {
            case "today":
                let steps = try await today()
                let target = goal()
                let percent = target > 0 ? Int((Double(steps) / Double(target) * 100).rounded()) : 0
                content = "You're at \(grouped(steps)) steps today, \(percent)% of your \(grouped(target)) goal."
            case "yesterday":
                let steps = try await yesterday()
                content = "You walked \(grouped(steps)) steps yesterday."
            case "last_7_days":
                let steps = try await last7().reduce(0, +)
                content = "You've taken \(grouped(steps)) steps in the last 7 days."
            case "goal":
                content = "Your daily step goal is \(grouped(goal()))."
            default:
                return nil
            }
        } catch {
            return nil
        }
        return ChatMessage(role: .assistant, content: content, routerAction: .localAnswer)
    }

    private static func programMessage(
        _ detail: String,
        body: TrainingProgramBody?,
        now: Date,
        calendar: Calendar
    ) -> ChatMessage? {
        guard let body else { return nil }
        let resolved = TrainingProgramSchedule.resolve(body, on: now, calendar: calendar)
        let content: String
        switch detail {
        case "today_session":
            switch resolved {
            case .session(let dayIndex, let name, _):
                let day = body.days.first { $0.dayIndex == dayIndex && $0.name == name }
                    ?? body.days.first { $0.dayIndex == dayIndex }
                let names = day?.exercises.sorted { $0.order < $1.order }.map(\.name) ?? []
                if names.isEmpty {
                    content = "Today: \(name)."
                } else {
                    content = "Today: \(name) (\(names.joined(separator: ", ")))."
                }
            case .rest(_, let nextName, let nextWeekday):
                content = restLine(nextName: nextName, nextWeekday: nextWeekday)
            case .upcoming(let name, let weekday, _):
                content = "Upcoming: \(name) on \(shortWeekday(weekday))."
            }
        case "next_session":
            switch resolved {
            case .session(let dayIndex, let name, _):
                content = "Today: \(name)."
                _ = dayIndex
            case .rest(_, let nextName, let nextWeekday):
                content = restLine(nextName: nextName, nextWeekday: nextWeekday)
            case .upcoming(let name, let weekday, _):
                content = "Upcoming: \(name) on \(shortWeekday(weekday))."
            }
        default:
            return nil
        }
        return ChatMessage(role: .assistant, content: content, routerAction: .localAnswer)
    }

    private static func restLine(nextName: String, nextWeekday: String) -> String {
        let day = shortWeekday(nextWeekday)
        if nextName.isEmpty || day.isEmpty { return "Rest day." }
        return "Rest day. Next: \(nextName) on \(day)."
    }

    private static func shortWeekday(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 3 { return trimmed }
        return String(trimmed.prefix(3))
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func intentFallback(_ answer: TypeSafeAnswer?) -> JevFallback {
        guard case .choice(let choice, let confidence, let probabilities) = answer else { return .lowConfidence }
        if choice == "open_chat" { return .none }
        if probabilities.isEmpty || confidence == 0 { return .lowConfidence }
        return .lowConfidence
    }

    private static func choiceConfidence(_ answer: TypeSafeAnswer?) -> Double? {
        guard case .choice(_, let confidence, _) = answer else { return nil }
        return confidence
    }
}
