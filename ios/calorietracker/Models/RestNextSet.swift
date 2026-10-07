import Foundation

struct RestNextSet {
    let step: ExerciseStep
    let exercise: ProgramV2Exercise
    let value: LoggedSet
    let targetChips: Set<Int>
    let reference: String
    let referenceLoad: Double?
    let reason: String
    let isHold: Bool
    var canLog: Bool { value.reps > 0 && (value.weight > 0 || exercise.startLoadLb == 0) }
    var repChoices: [Int] {
        guard let range = ProgressionRule.repRange(exercise.reps), range.high - range.low <= 12 else { return [] }
        return Array(range.low...range.high)
    }
    var logLabel: String { "Set done · Log \(LoggerFormatting.load(value.weight)) × \(value.reps)" }
    func quickLoad(_ offset: Int) -> LoggedSet {
        var result = value
        result.weight = max(0, (referenceLoad ?? value.weight) + Double(offset))
        return result
    }
}

extension LoggerFormatting {
    static func restRange(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound) s" : "\(range.lowerBound)–\(range.upperBound) s"
    }

    static func nextSetReference(sets: [LoggedSet], last: LastPerformance?, at index: Int) -> String {
        var lines: [String] = []
        if let todayIndex = sets.lastIndex(where: { $0.reps > 0 }) {
            let row = sets[todayIndex]
            lines.append("Today S\(todayIndex + 1) \(load(row.weight)) × \(row.reps)\(row.rir.map { " @ RIR \($0)" } ?? "")")
        }
        if let last {
            let reference = last.sets.indices.contains(index) ? last.sets[index] : last.firstSet
            if let reference {
                lines.append("Last time \(load(reference.load)) × \(reference.reps)\(reference.rir.map { " @ \($0)" } ?? "")")
            }
        }
        return lines.joined(separator: " · ")
    }

    static func progressionReason(_ decision: ProgressionDecision, exercise: ProgramV2Exercise,
                                  reference: WorkingSetSummary?) -> String {
        switch decision.reason {
        case .increase: return "+5: hit \(reference?.reps ?? ProgressionRule.repRange(exercise.reps)?.high ?? 0) @ RIR \(reference?.rir ?? 4)"
        case .decrease:
            if let low = ProgressionRule.repRange(exercise.reps)?.low, let reference, reference.reps < low {
                return "−5: below \(low) reps"
            }
            return "−5: RIR 0"
        case .hold: return "Hold: in range"
        case .holdPreFatigued: return "Hold: done later than planned — not counted as a miss"
        case .holdReductionWeek: return "Hold: reduction week"
        case .noHistory: return decision.load == nil ? "Select load" : "Start: program load"
        }
    }
}
