import Testing
@testable import calorietracker

extension WorkoutLoggerLogicTests {
    @Test func adjustedLoadPinsExistingThresholds() {
        let cases: [(Double, Int, Int?, Double)] = [
            (110, 15, 4, 115), (110, 17, 5, 115), (110, 15, 3, 110),
            (110, 12, 2, 110), (110, 8, 2, 105), (110, 12, 0, 105),
            (3, 5, 2, 0), (0, 20, 5, 0), (110, 15, nil, 110),
            (110, 8, nil, 105)
        ]
        for (load, reps, rir, expected) in cases {
            #expect(ProgressionRule.adjustedLoad(
                after: WorkingSetSummary(load: load, reps: reps, rir: rir),
                range: RepRange(low: 10, high: 15)
            ) == expected)
        }
    }
}
