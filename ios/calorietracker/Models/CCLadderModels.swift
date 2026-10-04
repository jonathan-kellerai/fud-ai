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
    /// Book graduate-at targets: series code -> step number -> target.
    /// Older bridges do not send it.
    var targetsBySeries: [String: [Int: CCStepTarget]]

    enum CodingKeys: String, CodingKey {
        case ruleDescription = "description"
        case maxRir = "max_rir"
        case workingSets = "working_sets"
        case requiredStreak = "required_streak"
        case masterStep = "master_step"
        case targetRepsByStep = "target_reps_by_step"
        case targetsBySeries = "targets_by_series"
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
        var bySeries: [String: [Int: CCStepTarget]] = [:]
        if let raw = try? container.decodeIfPresent([String: [String: CCStepTarget]].self, forKey: .targetsBySeries) {
            for (code, steps) in raw {
                var targets: [Int: CCStepTarget] = [:]
                for (key, value) in steps {
                    if let step = Int(key) {
                        targets[step] = value
                    }
                }
                bySeries[code] = targets
            }
        }
        targetsBySeries = bySeries
    }
}

/// One step's graduate-at target from rule.targets_by_series.
struct CCStepTarget: Decodable, Equatable {
    var sets: Int?
    var reps: Int?
    var holdSec: Int?
    var label: String?

    enum CodingKeys: String, CodingKey {
        case sets, reps, label
        case holdSec = "hold_sec"
    }

    init(sets: Int? = nil, reps: Int? = nil, holdSec: Int? = nil, label: String? = nil) {
        self.sets = sets
        self.reps = reps
        self.holdSec = holdSec
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sets = container.ccInt(.sets)
        reps = container.ccInt(.reps)
        holdSec = container.ccInt(.holdSec)
        label = container.ccString(.label)
    }
}

/// Within-step progress for a series. Every field is optional.
struct CCRepProgress: Decodable, Equatable {
    var bestTotalRepsLast: Int?
    var bestTotalRepsPrev: Int?
    var delta: Int?
    var improved: Bool?
    /// Percent of the graduate-at target on the 0...100 scale (may exceed 100).
    var pctOfTarget: Double?

    enum CodingKeys: String, CodingKey {
        case bestTotalRepsLast = "best_total_reps_last"
        case bestTotalRepsPrev = "best_total_reps_prev"
        case delta
        case improved
        case pctOfTarget = "pct_of_target"
    }

    init(
        bestTotalRepsLast: Int? = nil,
        bestTotalRepsPrev: Int? = nil,
        delta: Int? = nil,
        improved: Bool? = nil,
        pctOfTarget: Double? = nil
    ) {
        self.bestTotalRepsLast = bestTotalRepsLast
        self.bestTotalRepsPrev = bestTotalRepsPrev
        self.delta = delta
        self.improved = improved
        self.pctOfTarget = pctOfTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bestTotalRepsLast = container.ccInt(.bestTotalRepsLast)
        bestTotalRepsPrev = container.ccInt(.bestTotalRepsPrev)
        delta = container.ccInt(.delta)
        improved = container.ccBool(.improved)
        pctOfTarget = container.ccDouble(.pctOfTarget)
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
    var targetSets: Int?
    var targetHoldSec: Int?
    var targetLabel: String?
    var progress: CCRepProgress?
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
        case targetSets = "target_sets"
        case targetHoldSec = "target_hold_sec"
        case targetLabel = "target_label"
        case progress
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
        targetSets: Int? = nil,
        targetHoldSec: Int? = nil,
        targetLabel: String? = nil,
        progress: CCRepProgress? = nil,
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
        self.targetSets = targetSets
        self.targetHoldSec = targetHoldSec
        self.targetLabel = targetLabel
        self.progress = progress
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
        targetSets = container.ccInt(.targetSets)
        targetHoldSec = container.ccInt(.targetHoldSec)
        targetLabel = container.ccString(.targetLabel)
        progress = try? container.decodeIfPresent(CCRepProgress.self, forKey: .progress)
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
    var bookName: String?
    var pages: String?
    var targetSets: Int?
    /// Timed holds (HSP steps 1-3): seconds per set. The app logs hold
    /// seconds in the set's reps field.
    var targetHoldSec: Int?
    var targetLabel: String?

    var id: Int { step }

    enum CodingKeys: String, CodingKey {
        case step
        case name
        case workingReps = "working_reps"
        case targetReps = "target_reps"
        case bookName = "book_name"
        case pages
        case targetSets = "target_sets"
        case targetHoldSec = "target_hold_sec"
        case targetLabel = "target_label"
    }

    init(
        step: Int,
        name: String,
        workingReps: String? = nil,
        targetReps: Int? = nil,
        bookName: String? = nil,
        pages: String? = nil,
        targetSets: Int? = nil,
        targetHoldSec: Int? = nil,
        targetLabel: String? = nil
    ) {
        self.step = step
        self.name = name
        self.workingReps = workingReps
        self.targetReps = targetReps
        self.bookName = bookName
        self.pages = pages
        self.targetSets = targetSets
        self.targetHoldSec = targetHoldSec
        self.targetLabel = targetLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = container.ccInt(.step) ?? 0
        name = container.ccString(.name) ?? ""
        workingReps = container.ccString(.workingReps)
        targetReps = container.ccInt(.targetReps)
        bookName = container.ccString(.bookName)
        pages = container.ccString(.pages)
        targetSets = container.ccInt(.targetSets)
        targetHoldSec = container.ccInt(.targetHoldSec)
        targetLabel = container.ccString(.targetLabel)
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
    var totalReps: Int?
    /// Percent of the graduate-at target on the 0...100 scale.
    var pctOfTarget: Double?

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
        case totalReps = "total_reps"
        case pctOfTarget = "pct_of_target"
    }

    init(
        workoutId: String? = nil,
        sessionDate: String? = nil,
        exercise: String? = nil,
        step: Int? = nil,
        sets: [CCLadderSessionSet] = [],
        countsTowardCurrentStep: Bool = false,
        qualifying: Bool = false,
        flags: [String] = [],
        totalReps: Int? = nil,
        pctOfTarget: Double? = nil
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
        self.totalReps = totalReps
        self.pctOfTarget = pctOfTarget
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
        totalReps = container.ccInt(.totalReps)
        pctOfTarget = container.ccDouble(.pctOfTarget)
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

/// What the workout logger shows next to a CC ladder exercise.
struct CCLoggerLadderHint: Equatable {
    var text: String
    /// The logged step is a timed hold: the reps field takes seconds.
    var isHold: Bool
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
        case "reps_below_target": return "Reps below target"
        case "possible_duplicate": return "Possible duplicate session"
        case "target_unknown": return "Graduate-at target missing from the bridge"
        // RIR is no longer part of the rule, and rep progress is good news,
        // so none of these explain why a series is not ready.
        case "rir_above_max", "rir_missing", "rep_progress": return nil
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

    /// "15 @ RIR 2" per set (RIR only when logged), joined with " · ".
    /// Timed holds show the seconds logged in reps as "1:05".
    static func setsSummary(_ sets: [CCLadderSessionSet], isHold: Bool = false) -> String {
        let ordered = sets.sorted { ($0.setOrder ?? 0) < ($1.setOrder ?? 0) }
        let parts = ordered.map { item -> String in
            let value: String
            if isHold {
                value = item.reps.map { clockText(seconds: $0) } ?? "–"
            } else {
                value = item.reps.map { String($0) } ?? "–"
            }
            guard let rir = item.rir else { return value }
            return "\(value) @ RIR \(rir)"
        }
        return parts.isEmpty ? "No sets" : parts.joined(separator: " · ")
    }

    // MARK: Graduate-at targets

    static let repProgressFlag = "rep_progress"

    /// The advance rule as shown on the Ladders screen.
    static func ruleText(_ rule: CCLadderRule?) -> String {
        let streak = rule?.requiredStreak ?? 2
        return "Advance after you hit the step’s graduate-at target in \(streak) consecutive sessions: the first sets each at the target reps, or for holds a set held for the target time. The bridge decides readiness; you advance manually."
    }

    /// 125 -> "2:05".
    static func clockText(seconds: Int) -> String {
        let total = max(seconds, 0)
        let remainder = total % 60
        let padded = remainder < 10 ? "0\(remainder)" : "\(remainder)"
        return "\(total / 60):\(padded)"
    }

    /// 120 -> "2:00 hold".
    static func holdText(seconds: Int) -> String {
        "\(clockText(seconds: seconds)) hold"
    }

    static func isHold(_ step: CCLadderStep?) -> Bool {
        (step?.targetHoldSec ?? 0) > 0
    }

    /// True when the current step is a timed hold (sets log seconds in reps).
    static func isHoldSeries(_ series: CCSeriesState, rule: CCLadderRule? = nil) -> Bool {
        if (series.targetHoldSec ?? 0) > 0 { return true }
        guard let step = currentStepInfo(series) else { return false }
        return (target(for: step, series: series.series, rule: rule).holdSec ?? 0) > 0
    }

    /// Step fields first, then rule.targets_by_series for anything missing.
    static func target(for step: CCLadderStep, series: String, rule: CCLadderRule?) -> CCStepTarget {
        let fromRule = rule?.targetsBySeries[series]?[step.step]
        return CCStepTarget(
            sets: step.targetSets ?? fromRule?.sets,
            reps: step.targetReps ?? fromRule?.reps,
            holdSec: step.targetHoldSec ?? fromRule?.holdSec,
            label: nonEmpty(step.targetLabel) ?? nonEmpty(fromRule?.label)
        )
    }

    /// The bridge label, else "2:00 hold" / "2×1:00 hold" for holds, else "3×50".
    /// Nil when the target has neither a label nor sets with reps or a hold.
    static func composedLabel(_ target: CCStepTarget) -> String? {
        if let label = nonEmpty(target.label) { return label }
        if let hold = target.holdSec, hold > 0 {
            let text = holdText(seconds: hold)
            if let sets = target.sets, sets > 1 { return "\(sets)×\(text)" }
            return text
        }
        if let sets = target.sets, let reps = target.reps { return "\(sets)×\(reps)" }
        return nil
    }

    /// Target text for one row of the steps list, nil on older bridges.
    static func stepTargetLabel(_ step: CCLadderStep, series: String, rule: CCLadderRule?) -> String? {
        composedLabel(target(for: step, series: series, rule: rule))
    }

    /// The current step's graduate-at target: series label, series sets×reps or
    /// hold, the current step's target, then the old target reps / working range.
    static func graduateTarget(_ series: CCSeriesState, rule: CCLadderRule? = nil) -> String? {
        let seriesLevel = CCStepTarget(
            sets: series.targetSets,
            reps: series.targetSets == nil ? nil : series.targetReps,
            holdSec: series.targetHoldSec,
            label: series.targetLabel
        )
        if let text = composedLabel(seriesLevel) { return text }
        let step = currentStepInfo(series)
        if let step, let text = stepTargetLabel(step, series: series.series, rule: rule) { return text }
        if let reps = series.targetReps ?? step?.targetReps { return "\(reps) reps" }
        if let working = nonEmpty(step?.workingReps) { return "\(working) reps" }
        return nil
    }

    static func graduateAtText(_ series: CCSeriesState, rule: CCLadderRule? = nil) -> String? {
        graduateTarget(series, rule: rule).map { "Graduate at \($0)" }
    }

    /// "Book: Full push-ups · p. 54" when the bridge sends it. The book name is
    /// skipped when it only repeats the step name.
    static func bookText(_ step: CCLadderStep) -> String? {
        let name = step.bookName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pages = step.pages?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []
        if !name.isEmpty, name.caseInsensitiveCompare(step.name) != .orderedSame {
            parts.append(name)
        }
        if !pages.isEmpty {
            parts.append("p. \(pages)")
        }
        return parts.isEmpty ? nil : "Book: " + parts.joined(separator: " · ")
    }

    /// improved == true counts as progress even when the series is not ready.
    static func isImproving(_ series: CCSeriesState) -> Bool {
        series.progress?.improved == true
    }

    static func showsRepProgress(_ session: CCLadderSession) -> Bool {
        session.flags.contains(repProgressFlag)
    }

    /// "Rep progress: 46 → 52 (+6) · 43% of target". Holds use seconds.
    static func progressText(_ progress: CCRepProgress?, isHold: Bool = false) -> String? {
        guard let progress else { return nil }
        let unit = isHold ? "s" : ""
        var parts: [String] = []
        if let last = progress.bestTotalRepsLast {
            if let previous = progress.bestTotalRepsPrev {
                let delta = progress.delta ?? (last - previous)
                parts.append("\(previous)\(unit) → \(last)\(unit) (\(signedText(delta))\(unit))")
            } else {
                parts.append("\(last)\(unit)")
            }
        } else if let delta = progress.delta {
            parts.append("\(signedText(delta))\(unit)")
        }
        if let percent = percentText(progress.pctOfTarget) {
            parts.append(percent)
        }
        guard !parts.isEmpty else { return nil }
        return (isHold ? "Hold progress: " : "Rep progress: ") + parts.joined(separator: " · ")
    }

    /// "Total 52 · 43% of target" for one session, nil when neither is sent.
    static func sessionTotalsText(_ session: CCLadderSession, isHold: Bool = false) -> String? {
        var parts: [String] = []
        if let total = session.totalReps {
            parts.append(isHold ? "Total \(total)s" : "Total \(total)")
        }
        if let percent = percentText(session.pctOfTarget) {
            parts.append(percent)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 43.4 -> "43% of target". The bridge sends percent on the 0...100 scale.
    static func percentText(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        let clamped = min(max(value, 0), 9_999)
        return "\(Int(clamped.rounded()))% of target"
    }

    static func signedText(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(-value)" }
        return "±0"
    }

    // MARK: Logger hint

    /// Program V2 names its finishers "CC <series> ladder - step N <name>".
    static func isLadderExerciseName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("cc ") && lowered.contains("ladder")
    }

    /// Graduate-at text for a logger exercise, matched to its series by the
    /// program exercise name or by a step name equal to the exercise key.
    static func loggerHint(exerciseKey: String, exerciseName: String, in response: CCLaddersResponse?) -> CCLoggerLadderHint? {
        guard let response else { return nil }
        let key = normalized(exerciseKey)
        let name = normalized(exerciseName)
        guard let series = loggerSeries(exerciseKey: exerciseKey, exerciseName: exerciseName, in: response),
              let current = currentStepInfo(series),
              let target = graduateTarget(series, rule: response.rule)
        else { return nil }
        let currentName = normalized(current.name)
        let isCurrent = !currentName.isEmpty && (currentName == key || name.hasSuffix(currentName))
        let text = isCurrent
            ? "Graduate at \(target)"
            : "Ladder now at step \(current.step) · \(current.name) · graduate at \(target)"
        // Units follow the step being logged, which can differ from the current step.
        let isHold: Bool
        if let logged = loggedStep(series, exerciseKey: exerciseKey, exerciseName: exerciseName),
           logged.step != current.step {
            isHold = (Self.target(for: logged, series: series.series, rule: response.rule).holdSec ?? 0) > 0
        } else {
            isHold = isHoldSeries(series, rule: response.rule)
        }
        return CCLoggerLadderHint(text: text, isHold: isHold)
    }

    /// The series a logger exercise belongs to: by program exercise name, then
    /// by a step name equal to the exercise key.
    static func loggerSeries(exerciseKey: String, exerciseName: String, in response: CCLaddersResponse) -> CCSeriesState? {
        let key = normalized(exerciseKey)
        let name = normalized(exerciseName)
        return response.series.first { series in
            if series.programExercises.contains(where: { normalized($0.exercise ?? "") == name }) { return true }
            guard !key.isEmpty else { return false }
            return series.steps.contains { normalized($0.name) == key }
        }
    }

    /// The step a logged exercise names: a step or book name equal to the key or name,
    /// then "step N" in the program label, then a step or book name ending the label.
    static func loggedStep(_ series: CCSeriesState, exerciseKey: String, exerciseName: String) -> CCLadderStep? {
        let key = normalized(exerciseKey)
        let name = normalized(exerciseName)
        func names(_ step: CCLadderStep) -> [String] {
            [normalized(step.name), normalized(step.bookName ?? "")].filter { !$0.isEmpty }
        }
        if let exact = series.steps.first(where: { names($0).contains { $0 == key || $0 == name } }) {
            return exact
        }
        if let range = name.range(of: #"\bstep\s+\d+"#, options: .regularExpression),
           let number = Int(name[range].filter(\.isNumber)),
           let numbered = series.steps.first(where: { $0.step == number }) {
            return numbered
        }
        // Longest suffix wins: "half handstand push-up" over "handstand push-up".
        var best: (step: CCLadderStep, length: Int)?
        for step in series.steps {
            for candidate in names(step) where name.hasSuffix(candidate) && candidate.count > (best?.length ?? 0) {
                best = (step, candidate.count)
            }
        }
        return best?.step
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    func ccDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Double(text), value.isFinite {
            return value
        }
        return nil
    }
}
