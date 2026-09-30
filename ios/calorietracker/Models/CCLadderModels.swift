//
//  CCLadderModels.swift
//  calorietracker
//
//  JL Physical — Convict Conditioning ladders from GET /api/cc/ladders.
//  Every step name, rep range and target comes from the bridge payload.
//  Nothing here hardcodes a book table.
//

import Foundation

// MARK: - Response

struct CCLaddersResponse: Decodable {
    var generatedAt: String?
    var rule: CCLadderRule?
    var activeProgram: CCActiveProgram?
    var series: [CCSeriesState]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case rule
        case activeProgram = "active_program"
        case series
    }

    init(generatedAt: String? = nil, rule: CCLadderRule? = nil, activeProgram: CCActiveProgram? = nil, series: [CCSeriesState]) {
        self.generatedAt = generatedAt
        self.rule = rule
        self.activeProgram = activeProgram
        self.series = series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = container.ccString(.generatedAt)
        rule = try? container.decodeIfPresent(CCLadderRule.self, forKey: .rule)
        activeProgram = try? container.decodeIfPresent(CCActiveProgram.self, forKey: .activeProgram)
        series = try container.decode([CCSeriesState].self, forKey: .series)
    }
}

struct CCLadderRule: Decodable {
    var ruleDescription: String?
    var maxRir: Int?
    var workingSets: Int?
    var requiredStreak: Int?
    var masterStep: Int?
    /// Keyed by step number. The bridge sends string keys ("1"..."10").
    var targetRepsByStep: [Int: Int]

    enum CodingKeys: String, CodingKey {
        case ruleDescription = "description"
        case maxRir = "max_rir"
        case workingSets = "working_sets"
        case requiredStreak = "required_streak"
        case masterStep = "master_step"
        case targetRepsByStep = "target_reps_by_step"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleDescription = container.ccString(.ruleDescription)
        maxRir = container.ccInt(.maxRir)
        workingSets = container.ccInt(.workingSets)
        requiredStreak = container.ccInt(.requiredStreak)
        masterStep = container.ccInt(.masterStep)
        var byStep: [Int: Int] = [:]
        if let raw = try? container.decodeIfPresent([String: Int].self, forKey: .targetRepsByStep) {
            for (key, value) in raw {
                if let step = Int(key) {
                    byStep[step] = value
                }
            }
        }
        targetRepsByStep = byStep
    }
}

struct CCActiveProgram: Decodable {
    var id: String?
    var name: String?
    var version: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.ccString(.id)
        name = container.ccString(.name)
        version = container.ccInt(.version)
    }
}

// MARK: - Series

struct CCSeriesState: Decodable, Identifiable {
    var series: String
    var label: String
    var currentStep: Int?
    var stepName: String?
    var since: String?
    var targetReps: Int?
    var master: Bool
    var ready: Bool
    var streak: Int
    var requiredStreak: Int
    var flags: [String]
    var inProgram: Bool
    var programExercises: [CCProgramExercise]
    var lastEvent: CCLadderEvent?
    var sessions: [CCLadderSession]
    var steps: [CCLadderStep]

    var id: String { series }

    enum CodingKeys: String, CodingKey {
        case series
        case label
        case currentStep = "current_step"
        case stepName = "step_name"
        case since
        case targetReps = "target_reps"
        case master
        case ready
        case streak
        case requiredStreak = "required_streak"
        case flags
        case inProgram = "in_program"
        case programExercises = "program_exercises"
        case lastEvent = "last_event"
        case sessions
        case steps
    }

    init(
        series: String,
        label: String = "",
        currentStep: Int? = nil,
        stepName: String? = nil,
        since: String? = nil,
        targetReps: Int? = nil,
        master: Bool = false,
        ready: Bool = false,
        streak: Int = 0,
        requiredStreak: Int = 0,
        flags: [String] = [],
        inProgram: Bool = false,
        programExercises: [CCProgramExercise] = [],
        lastEvent: CCLadderEvent? = nil,
        sessions: [CCLadderSession] = [],
        steps: [CCLadderStep] = []
    ) {
        self.series = series
        self.label = label
        self.currentStep = currentStep
        self.stepName = stepName
        self.since = since
        self.targetReps = targetReps
        self.master = master
        self.ready = ready
        self.streak = streak
        self.requiredStreak = requiredStreak
        self.flags = flags
        self.inProgram = inProgram
        self.programExercises = programExercises
        self.lastEvent = lastEvent
        self.sessions = sessions
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        series = container.ccString(.series) ?? ""
        label = container.ccString(.label) ?? ""
        currentStep = container.ccInt(.currentStep)
        stepName = container.ccString(.stepName)
        since = container.ccString(.since)
        targetReps = container.ccInt(.targetReps)
        master = container.ccBool(.master) ?? false
        ready = container.ccBool(.ready) ?? false
        streak = container.ccInt(.streak) ?? 0
        requiredStreak = container.ccInt(.requiredStreak) ?? 0
        flags = (try? container.decodeIfPresent([String].self, forKey: .flags)) ?? []
        inProgram = container.ccBool(.inProgram) ?? false
        programExercises = (try? container.decodeIfPresent([CCProgramExercise].self, forKey: .programExercises)) ?? []
        lastEvent = try? container.decodeIfPresent(CCLadderEvent.self, forKey: .lastEvent)
        sessions = (try? container.decodeIfPresent([CCLadderSession].self, forKey: .sessions)) ?? []
        // Older bridge deploys do not send `steps`.
        steps = (try? container.decodeIfPresent([CCLadderStep].self, forKey: .steps)) ?? []
    }
}

struct CCLadderStep: Decodable, Identifiable, Equatable {
    var step: Int
    var name: String
    var workingReps: String?
    var targetReps: Int?

    var id: Int { step }

    enum CodingKeys: String, CodingKey {
        case step
        case name
        case workingReps = "working_reps"
        case targetReps = "target_reps"
    }

    init(step: Int, name: String, workingReps: String? = nil, targetReps: Int? = nil) {
        self.step = step
        self.name = name
        self.workingReps = workingReps
        self.targetReps = targetReps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = container.ccInt(.step) ?? 0
        name = container.ccString(.name) ?? ""
        workingReps = container.ccString(.workingReps)
        targetReps = container.ccInt(.targetReps)
    }
}

struct CCProgramExercise: Decodable {
    var day: String?
    var exercise: String?
    var step: Int?
    var sets: Int?
    /// A range like "8-15" or a plain number, kept as text.
    var reps: String?

    enum CodingKeys: String, CodingKey {
        case day, exercise, step, sets, reps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = container.ccString(.day)
        exercise = container.ccString(.exercise)
        step = container.ccInt(.step)
        sets = container.ccInt(.sets)
        reps = container.ccString(.reps)
    }
}

struct CCLadderEvent: Decodable {
    var id: String?
    var series: String?
    var eventType: String?
    var fromStep: Int?
    var toStep: Int?
    var occurredAt: String?
    var reason: String?
    var createdBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case series
        case eventType = "event_type"
        case fromStep = "from_step"
        case toStep = "to_step"
        case occurredAt = "occurred_at"
        case reason
        case createdBy = "created_by"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.ccString(.id)
        series = container.ccString(.series)
        eventType = container.ccString(.eventType)
        fromStep = container.ccInt(.fromStep)
        toStep = container.ccInt(.toStep)
        occurredAt = container.ccString(.occurredAt)
        reason = container.ccString(.reason)
        createdBy = container.ccString(.createdBy)
    }
}

struct CCLadderSession: Decodable, Identifiable {
    var workoutId: String?
    var sessionDate: String?
    var programDay: String?
    var title: String?
    var exercise: String?
    var step: Int?
    var sets: [CCLadderSessionSet]
    var countsTowardCurrentStep: Bool
    var qualifying: Bool
    var flags: [String]

    var id: String {
        [workoutId ?? "", sessionDate ?? "", exercise ?? "", step.map { String($0) } ?? ""].joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case sessionDate = "session_date"
        case programDay = "program_day"
        case title
        case exercise
        case step
        case sets
        case countsTowardCurrentStep = "counts_toward_current_step"
        case qualifying
        case flags
    }

    init(
        workoutId: String? = nil,
        sessionDate: String? = nil,
        exercise: String? = nil,
        step: Int? = nil,
        sets: [CCLadderSessionSet] = [],
        countsTowardCurrentStep: Bool = false,
        qualifying: Bool = false,
        flags: [String] = []
    ) {
        self.workoutId = workoutId
        self.sessionDate = sessionDate
        self.programDay = nil
        self.title = nil
        self.exercise = exercise
        self.step = step
        self.sets = sets
        self.countsTowardCurrentStep = countsTowardCurrentStep
        self.qualifying = qualifying
        self.flags = flags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workoutId = container.ccString(.workoutId)
        sessionDate = container.ccString(.sessionDate)
        programDay = container.ccString(.programDay)
        title = container.ccString(.title)
        exercise = container.ccString(.exercise)
        step = container.ccInt(.step)
        sets = (try? container.decodeIfPresent([CCLadderSessionSet].self, forKey: .sets)) ?? []
        countsTowardCurrentStep = container.ccBool(.countsTowardCurrentStep) ?? false
        qualifying = container.ccBool(.qualifying) ?? false
        flags = (try? container.decodeIfPresent([String].self, forKey: .flags)) ?? []
    }
}

struct CCLadderSessionSet: Decodable {
    var setOrder: Int?
    var reps: Int?
    var rir: Int?
    var loadLb: Double?

    enum CodingKeys: String, CodingKey {
        case setOrder = "set_order"
        case reps
        case rir
        case loadLb = "load_lb"
    }

    init(setOrder: Int? = nil, reps: Int? = nil, rir: Int? = nil, loadLb: Double? = nil) {
        self.setOrder = setOrder
        self.reps = reps
        self.rir = rir
        self.loadLb = loadLb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setOrder = container.ccInt(.setOrder)
        reps = container.ccInt(.reps)
        rir = container.ccInt(.rir)
        if let value = try? container.decodeIfPresent(Double.self, forKey: .loadLb) {
            loadLb = value
        } else {
            loadLb = nil
        }
    }
}

// MARK: - Event request

struct CCLadderEventRequest: Encodable, Equatable {
    var series: String
    var eventType: String
    var fromStep: Int
    var toStep: Int
    var reason: String
    var createdBy: String

    enum CodingKeys: String, CodingKey {
        case series
        case eventType = "event_type"
        case fromStep = "from_step"
        case toStep = "to_step"
        case reason
        case createdBy = "created_by"
    }
}

// MARK: - Logic

enum CCStepStatus: Equatable {
    case done
    case current
    case upcoming
}

enum CCStepChangeDirection: String, Equatable {
    case advance
    case regress
}

/// Pure display rules for the Ladders screen. Readiness itself is computed by
/// the bridge; the app only decides which controls to show.
enum CCLadderLogic {
    /// The spec's final step. Fixed: the bridge's series.master and
    /// rule.master_step are decoded but never change which controls show.
    static let masterStep = 10

    static func isSetUp(_ series: CCSeriesState) -> Bool {
        !series.steps.isEmpty
    }

    static func isMaster(_ series: CCSeriesState) -> Bool {
        guard isSetUp(series) else { return false }
        return series.currentStep == masterStep
    }

    static func showsAdvance(_ series: CCSeriesState) -> Bool {
        guard isSetUp(series), series.ready, let current = series.currentStep else { return false }
        return current < masterStep
    }

    static func showsGoBack(_ series: CCSeriesState) -> Bool {
        guard isSetUp(series), let current = series.currentStep else { return false }
        return current > 1
    }

    static func stepStatus(step: Int, current: Int?) -> CCStepStatus {
        guard let current else { return .upcoming }
        if step < current { return .done }
        if step == current { return .current }
        return .upcoming
    }

    static func currentStepInfo(_ series: CCSeriesState) -> CCLadderStep? {
        guard let current = series.currentStep else { return nil }
        return series.steps.first { $0.step == current }
    }

    static func targetReps(_ series: CCSeriesState) -> Int? {
        series.targetReps ?? currentStepInfo(series)?.targetReps
    }

    /// Short, human-readable reasons for bridge flags. Flags that do not
    /// explain readiness (for example sessions logged at another step) are skipped.
    static func readinessReasons(flags: [String]) -> [String] {
        var reasons: [String] = []
        for flag in flags {
            guard let reason = reason(for: flag), !reasons.contains(reason) else { continue }
            reasons.append(reason)
        }
        return reasons
    }

    /// Series flags plus flags on the most recent sessions that count toward the current step.
    static func readinessReasons(for series: CCSeriesState) -> [String] {
        let window = max(series.requiredStreak, 1)
        let counting = series.sessions.filter { $0.countsTowardCurrentStep }.prefix(window)
        var flags = series.flags
        for session in counting {
            flags.append(contentsOf: session.flags)
        }
        return readinessReasons(flags: flags)
    }

    static func reason(for flag: String) -> String? {
        switch flag {
        case "rir_above_max": return "RIR above 2"
        case "reps_below_target": return "Reps below target"
        case "possible_duplicate": return "Possible duplicate session"
        case "rir_missing": return "RIR missing"
        case "target_unknown": return "Target reps unknown"
        case "different_step", "before_step_start": return nil
        default:
            let words = flag.replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = words.first else { return nil }
            return String(first).uppercased() + String(words.dropFirst())
        }
    }

    static func recentSessions(_ series: CCSeriesState, limit: Int = 3) -> [CCLadderSession] {
        Array(series.sessions.prefix(limit))
    }

    /// "15 @ RIR 2" per set, joined with " · ".
    static func setsSummary(_ sets: [CCLadderSessionSet]) -> String {
        let ordered = sets.sorted { ($0.setOrder ?? 0) < ($1.setOrder ?? 0) }
        let parts = ordered.map { item -> String in
            let reps = item.reps.map { String($0) } ?? "–"
            let rir = item.rir.map { String($0) } ?? "–"
            return "\(reps) @ RIR \(rir)"
        }
        return parts.isEmpty ? "No sets" : parts.joined(separator: " · ")
    }

    static func changeRequest(for series: CCSeriesState, direction: CCStepChangeDirection) -> CCLadderEventRequest? {
        guard let current = series.currentStep else { return nil }
        switch direction {
        case .advance:
            guard showsAdvance(series) else { return nil }
            return CCLadderEventRequest(
                series: series.series,
                eventType: direction.rawValue,
                fromStep: current,
                toStep: current + 1,
                reason: "Advanced in app after bridge reported ready",
                createdBy: "app"
            )
        case .regress:
            guard showsGoBack(series) else { return nil }
            return CCLadderEventRequest(
                series: series.series,
                eventType: direction.rawValue,
                fromStep: current,
                toStep: current - 1,
                reason: "Went back a step in app",
                createdBy: "app"
            )
        }
    }

    /// "2026-09-24" -> "Sep 24". Falls back to the raw string.
    static func displayDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "–" }
        let day = String(raw.prefix(10))
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return raw }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Lenient decoding

private extension KeyedDecodingContainer {
    func ccString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func ccInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite, abs(value) < 1_000_000_000 {
            return Int(value)
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
    }

    func ccBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        return nil
    }
}
