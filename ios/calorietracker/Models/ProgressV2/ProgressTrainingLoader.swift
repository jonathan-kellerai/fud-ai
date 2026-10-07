import Foundation

enum ProgressTrainingLoadState: Equatable {
    case idle
    case loading
    case loaded(ProgressTrainingSummary)
}

/// Builds the Training card from the workouts saved on this phone. The log is
/// complete, so no week is cut off and every session's sets are counted.
enum ProgressTrainingLoader {
    /// Range start and today are both Eastern day keys from one calendar,
    /// matching how sessions are bucketed.
    static func summary(range: TimeRange, details: [WorkoutDetailResponse], now: Date = .now) -> ProgressTrainingSummary {
        let workouts = details.map { detail in
            ProgressBridgeWorkout(
                id: detail.workout.id,
                kind: detail.workout.kind,
                programDay: detail.workout.programDay,
                title: detail.workout.title,
                sessionDate: detail.workout.sessionDate,
                recordedAt: detail.workout.recordedAt,
                synthetic: detail.workout.synthetic
            )
        }
        var totals: [String: ProgressWorkoutTotals] = [:]
        for detail in details {
            totals[detail.workout.id] = ProgressWorkoutTotals(
                sets: detail.sets.count,
                volumeLb: detail.sets.reduce(0) { $0 + $1.loadLb * Double($1.reps) }
            )
        }

        let oldestWorkout = workouts
            .filter(ProgressTrainingMath.isCompleted)
            .compactMap { ProgressTrainingMath.dayKey(for: $0) }
            .min()
        let (startKey, todayKey) = ProgressTrainingMath.rangeDayKeys(for: range, now: now, oldestWorkoutDay: oldestWorkout)
        return ProgressTrainingMath.summary(
            workouts: workouts,
            details: totals,
            startDayKey: startKey,
            todayKey: todayKey,
            listLimit: .max,
            detailLimit: .max
        )
    }
}
