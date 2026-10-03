//
//  ProgramV2Templates.swift
//  calorietracker
//
//  Program V2 day templates from program-v2.json
//

import Foundation

struct ProgramV2Exercise: Identifiable {
    let id = UUID()
    let key: String
    let name: String
    var sets: Int
    let reps: String
    let restSeconds: ClosedRange<Int>
    var rirTarget: String
    let startLoadLb: Double?
    let notes: String
    var loadNote: String = ""
    /// Consecutive exercises sharing a group are done as a superset.
    var supersetGroup: String? = nil
    var setsLabel: String? = nil
}

struct ProgramV2Day: Identifiable {
    let id: String  // program_day
    let title: String
    let conditioning: String
    let conditioningMinimum: String
    var exercises: [ProgramV2Exercise]
    var weekNote: String? = nil
    var holdLoads: Bool = false
}

enum ProgramV2Templates {
    static let allDays: [ProgramV2Day] = [day1LowerA, day2UpperPush, day3PullHinge, day4UpperPhysique, day5LowerBCond]

    static func restLowerBound(matching name: String) -> Int? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        let exercises = allDays.flatMap(\.exercises)
        if let exact = exercises.first(where: { $0.name.lowercased() == needle }) {
            return exact.restSeconds.lowerBound
        }
        return exercises.first { exercise in
            needle.contains(exercise.key.lowercased()) || exercise.name.lowercased().contains(needle)
        }?.restSeconds.lowerBound
    }
    
    static let day1LowerA = ProgramV2Day(
        id: "Day1_LowerA",
        title: "Lower A",
        conditioning: "8 min steady: bike or incline treadmill walk, RPE 5-6/10",
        conditioningMinimum: "5 min",
        exercises: [
            ProgramV2Exercise(
                key: "leg press",
                name: "Leg press",
                sets: 3,
                reps: "10-15",
                restSeconds: 90...120,
                rirTarget: "sets 1-2: 2-3 RIR; last set 1-2 RIR",
                startLoadLb: 145,
                notes: "Anchor. 2-3 s eccentric."
            ),
            ProgramV2Exercise(
                key: "leg curl",
                name: "Lying or seated leg curl",
                sets: 3,
                reps: "10-15",
                restSeconds: 60...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 70,
                notes: ""
            ),
            ProgramV2Exercise(
                key: "leg extension",
                name: "Leg extension",
                sets: 2,
                reps: "12-15",
                restSeconds: 60...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 70,
                notes: "Stop short of joint pain."
            )
        ]
    )
    
    static let day2UpperPush = ProgramV2Day(
        id: "Day2_UpperPush",
        title: "Upper Push",
        conditioning: "8 min steady: incline treadmill walk or bike, RPE 5-6/10",
        conditioningMinimum: "5 min",
        exercises: [
            ProgramV2Exercise(
                key: "chest press machine",
                name: "Chest press machine",
                sets: 3,
                reps: "10-15",
                restSeconds: 120...120,
                rirTarget: "stop every set at 1-2 RIR; NO set to 0 RIR",
                startLoadLb: 125,
                notes: "Anchor. Use full rest."
            ),
            ProgramV2Exercise(
                key: "pec deck",
                name: "Pec deck or cable fly",
                sets: 2,
                reps: "12-15",
                restSeconds: 60...90,
                rirTarget: "set 1 ~3 RIR, set 2 ~2 RIR",
                startLoadLb: nil,
                notes: "SELECT ON FIRST SESSION. Stretch under control."
            ),
            ProgramV2Exercise(
                key: "overhead press machine",
                name: "Overhead press machine",
                sets: 2,
                reps: "8-12",
                restSeconds: 90...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 45,
                notes: "Shoulders stay happy."
            ),
            ProgramV2Exercise(
                key: "triceps pressdown",
                name: "Triceps pressdown",
                sets: 2,
                reps: "12-15",
                restSeconds: 60...60,
                rirTarget: "2-3 RIR",
                startLoadLb: 125,
                notes: "Pump finisher."
            ),
            ProgramV2Exercise(
                key: "Knee tuck",
                name: "CC leg raise ladder - step 1 Knee tuck",
                sets: 2,
                reps: "8-15",
                restSeconds: 60...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 0,
                notes: "Bodyweight. Skip if at 60 min."
            )
        ]
    )
    
    static let day3PullHinge = ProgramV2Day(
        id: "Day3_PullHinge",
        title: "Pull / Hinge",
        conditioning: "12 min bike intervals: 2 min easy, then 5 x (1 min hard RPE 7-8 / 1 min easy)",
        conditioningMinimum: "2 min easy + 3 rounds (8 min)",
        exercises: [
            ProgramV2Exercise(
                key: "cable pull-through",
                name: "Cable pull-through",
                sets: 3,
                reps: "8-12",
                restSeconds: 90...120,
                rirTarget: "set 1 ~4 RIR, sets 2-3 2-3 RIR",
                startLoadLb: nil,
                notes: "SELECT ON FIRST SESSION. Hips back, squeeze glutes."
            ),
            ProgramV2Exercise(
                key: "chest-supported row",
                name: "Chest-supported row",
                sets: 3,
                reps: "8-12",
                restSeconds: 90...90,
                rirTarget: "2-3 RIR; last set 1-2",
                startLoadLb: 110,
                notes: "Anchor. 1 s squeeze."
            ),
            ProgramV2Exercise(
                key: "lat pulldown",
                name: "Lat pulldown (neutral or long bar)",
                sets: 2,
                reps: "10-12",
                restSeconds: 60...90,
                rirTarget: "2 RIR",
                startLoadLb: 80,
                notes: "Full stretch."
            ),
            ProgramV2Exercise(
                key: "cable or db curl",
                name: "Cable or DB curl",
                sets: 2,
                reps: "12-15",
                restSeconds: 60...60,
                rirTarget: "2-3 RIR",
                startLoadLb: nil,
                notes: "SELECT ON FIRST SESSION. Direct biceps work."
            )
        ]
    )
    
    static let day4UpperPhysique = ProgramV2Day(
        id: "Day4_UpperPhysique",
        title: "Upper Physique",
        conditioning: "8 min steady: incline treadmill walk or bike, RPE 5-6/10",
        conditioningMinimum: "5 min",
        exercises: [
            ProgramV2Exercise(
                key: "incline chest press",
                name: "Incline chest press machine",
                sets: 3,
                reps: "10-12",
                restSeconds: 90...90,
                rirTarget: "2-3 RIR; last set 1-2",
                startLoadLb: 100,
                notes: "Not a max-effort day."
            ),
            ProgramV2Exercise(
                key: "reverse pec deck",
                name: "Reverse pec deck / rear-delt machine",
                sets: 3,
                reps: "12-15",
                restSeconds: 60...75,
                rirTarget: "2-3 RIR",
                startLoadLb: 20,
                notes: "Physique priority."
            ),
            ProgramV2Exercise(
                key: "cable lateral raise",
                name: "Cable lateral raise",
                sets: 2,
                reps: "12-15",
                restSeconds: 60...60,
                rirTarget: "2-3 RIR",
                startLoadLb: 15,
                notes: "Strict."
            ),
            ProgramV2Exercise(
                key: "cable or db curl",
                name: "Cable or DB curl",
                sets: 2,
                reps: "12-15",
                restSeconds: 0...0,
                rirTarget: "2-3 RIR",
                startLoadLb: nil,
                notes: "SELECT ON FIRST SESSION. Superset A: go straight to the pressdown.",
                supersetGroup: "curl-pressdown"
            ),
            ProgramV2Exercise(
                key: "triceps pressdown",
                name: "Triceps pressdown",
                sets: 2,
                reps: "12-15",
                restSeconds: 60...60,
                rirTarget: "2-3 RIR",
                startLoadLb: 125,
                notes: "Superset B: rest 60 s after each pair.",
                supersetGroup: "curl-pressdown"
            ),
            ProgramV2Exercise(
                key: "Short bridge",
                name: "CC bridge ladder - step 1 Short bridge",
                sets: 2,
                reps: "8-15",
                restSeconds: 60...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 0,
                notes: "Bodyweight. Skip if at 60 min."
            )
        ]
    )
    
    static let day5LowerBCond = ProgramV2Day(
        id: "Day5_LowerB_Cond",
        title: "Lower B + Cond",
        conditioning: "12 min steady: bike, incline walk or stair climber, RPE 6/10",
        conditioningMinimum: "8 min",
        exercises: [
            ProgramV2Exercise(
                key: "hack squat",
                name: "Hack squat (or second leg-press stance)",
                sets: 3,
                reps: "10-12",
                restSeconds: 90...120,
                rirTarget: "2-3 RIR; last set 1-2",
                startLoadLb: 90,
                notes: "Log stance."
            ),
            ProgramV2Exercise(
                key: "hip thrust",
                name: "Hip thrust machine / glute drive",
                sets: 2,
                reps: "10-15",
                restSeconds: 60...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 50,
                notes: "Glute bias."
            ),
            ProgramV2Exercise(
                key: "Jackknife squat",
                name: "CC squat ladder - step 2 Jackknife squat",
                sets: 2,
                reps: "8-15",
                restSeconds: 60...90,
                rirTarget: "2-3 RIR",
                startLoadLb: 0,
                notes: "Bodyweight. Skip if at 60 min."
            )
        ]
    )
}
