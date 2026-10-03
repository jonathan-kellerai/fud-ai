import Foundation

enum ProgramWeekRules {
    static var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? calendar.timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    /// Compare ET civil dates, avoiding elapsed-hour arithmetic across DST.
    /// Both dates are anchored to their Monday, so weeks run Monday–Sunday.
    static func weekNumber(on date: Date, body: TrainingProgramBody) -> Int? {
        let calendar = easternCalendar
        guard let start = SessionDateFormatting.date(from: body.startDate, calendar: calendar),
              let civilToday = SessionDateFormatting.date(
                from: SessionDateFormatting.calendarDateString(from: date, calendar: calendar), calendar: calendar)
        else { return nil }
        func monday(_ day: Date) -> Date {
            let offset = (calendar.component(.weekday, from: day) + 5) % 7
            return calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: day)) ?? day
        }
        guard let days = calendar.dateComponents([.day], from: monday(start), to: monday(civilToday)).day,
              days >= 0 else { return nil }
        return days / 7 + 1
    }

    static func apply(to day: ProgramV2Day, dayIndex: Int, on date: Date, body: TrainingProgramBody) -> ProgramV2Day {
        guard let week = weekNumber(on: date, body: body) else { return day }
        var adjusted = day
        if week == body.reductionWeek {
            for index in adjusted.exercises.indices {
                let exercise = adjusted.exercises[index]
                if isCCFinisher(exercise) {
                    adjusted.exercises[index].sets = 1
                } else if isAnchor(exercise) {
                    adjusted.exercises[index].sets = 2
                } else {
                    adjusted.exercises[index].sets = min(exercise.sets, 2)
                    adjusted.exercises[index].setsLabel = "1–2"
                }
                adjusted.exercises[index].rirTarget = "3-4 RIR"
            }
            adjusted.holdLoads = true
            adjusted.weekNote = "Reduction week: anchors 2 sets, accessories 1–2, CC 1, 3–4 RIR, same loads"
        } else if week == 3 {
            for index in adjusted.exercises.indices {
                let name = adjusted.exercises[index].name.lowercased()
                if dayIndex == 2 && name == "overhead triceps extension (cable or db)" {
                    adjusted.exercises[index].sets += 1
                    adjusted.weekNote = "Week 3: +1 set on overhead extension (if elbows feel good)"
                } else if dayIndex == 3 && name == "cable or db curl" {
                    adjusted.exercises[index].sets += 1
                    adjusted.weekNote = "Week 3: +1 set on curl (if elbows feel good)"
                }
            }
        }
        return adjusted
    }

    private static func isAnchor(_ exercise: ProgramV2Exercise) -> Bool {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["leg press", "chest press machine", "chest-supported row", "cable pull-through"].contains(name)
            || exercise.notes.lowercased().contains("anchor.")
    }

    private static func isCCFinisher(_ exercise: ProgramV2Exercise) -> Bool {
        if CCLadderLogic.isLadderExerciseName(exercise.name) { return true }
        // Bare step names in older bridge programs; do not classify every
        // bodyweight accessory as a ladder.
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["knee tuck", "short bridge", "jackknife squat", "shoulderstand squat"].contains(name)
    }
}
