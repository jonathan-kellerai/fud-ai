import Foundation
import Testing
@testable import calorietracker

struct TrainingProgramTests {
    @Test func decodesProgramListAndFullRow() throws {
        let list = try JSONDecoder().decode(TrainingProgramListResponse.self, from: Data(listJSON.utf8))
        #expect(list.programs.count == 3)
        #expect(list.programs[0].status == .active)
        #expect(list.programs[0].body == nil)
        #expect(list.programs[1].status == .draft)
        #expect(list.programs[2].lineageId == "line-1")
        #expect(list.programs[2].version == 1)

        let record = try JSONDecoder().decode(TrainingProgramRecord.self, from: Data(detailJSON.utf8))
        #expect(record.id == "prog-2")
        #expect(record.status == .active)
        #expect(record.body?.startDate == "2026-09-28")
        #expect(record.body?.dailyStepsTarget == 10_000)
        #expect(record.body?.restWeekdays == ["sat", "sun"])
        let days = try #require(record.body?.days)
        #expect(days.count == 2)
        #expect(days[0].name == "Lower A")
        #expect(days[0].weekday == "mon")
        #expect(days[0].conditioning?.minutes == 8)
        #expect(days[0].conditioning?.description == "steady: bike or incline treadmill walk, RPE 5-6/10")
        #expect(days[0].exercises[0].reps == "10-12")
        #expect(days[0].exercises[0].rir == "2")
        #expect(days[0].exercises[0].rpe == 8)
        #expect(days[0].exercises[0].restSec == 90)
        #expect(days[0].exercises[0].substitutions == ["hack squat"])
        #expect(days[1].conditioning == nil)
        #expect(days[1].exercises[0].rir == "2-3")
        #expect(days[1].exercises[0].reps == "8")

        let encoded = try JSONEncoder().encode(record.body)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["start_date"] as? String == "2026-09-28")
        #expect(object?["daily_steps_target"] as? Int == 10_000)
        let encodedDays = object?["days"] as? [[String: Any]]
        let exercises = encodedDays?.first?["exercises"] as? [[String: Any]]
        #expect(exercises?.first?["rest_sec"] as? Int == 90)
        #expect(exercises?.first?["load_note"] as? String == "Start 145 lb")
    }

    @Test func utcMidnightStaysOnTheCalendarDay() throws {
        let raw = "2026-09-24T00:00:00.000Z"
        #expect(SessionDateFormatting.displayString(from: raw) == "Thu, Sep 24")
        #expect(SessionDateFormatting.displayString(from: "2026-09-24") == "Thu, Sep 24")

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let instant = try #require(parser.date(from: raw))
        let newYork = DateFormatter()
        newYork.calendar = Calendar(identifier: .gregorian)
        newYork.locale = Locale(identifier: "en_US_POSIX")
        newYork.timeZone = TimeZone(identifier: "America/New_York")
        newYork.dateFormat = "yyyy-MM-dd"
        #expect(newYork.string(from: instant) == "2026-09-23")
    }

    @Test func sundayBeforeStartShowsFirstSessionAsUpcoming() {
        let calendar = newYorkCalendar()
        let sunday = civilDate(2026, 9, 27, calendar: calendar)
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: sunday, calendar: calendar)
        guard case .upcoming(let name, let weekday, let steps) = plan else {
            #expect(Bool(false))
            return
        }
        #expect(name == "Lower A")
        #expect(weekday == "Monday")
        #expect(steps == 10_000)
        #expect(plan.nextLabel == nil)
    }

    @Test func mondayOnStartDateIsLowerA() {
        let calendar = newYorkCalendar()
        let monday = civilDate(2026, 9, 28, calendar: calendar)
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: monday, calendar: calendar)
        guard case .session(_, let name, _) = plan else {
            #expect(Bool(false))
            return
        }
        #expect(name == "Lower A")
        let day = TrainingProgramSchedule.programDay(in: .bundledV2(), matching: plan)
        #expect(day?.conditioningSummary == "8 min steady: bike or incline treadmill walk, RPE 5-6/10")
        #expect(day?.exercises.first?.restSec == 90)
    }

    @Test func saturdayRestDayNamesTheNextSession() {
        let calendar = newYorkCalendar()
        let saturday = civilDate(2026, 10, 3, calendar: calendar)
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: saturday, calendar: calendar)
        guard case .rest(let steps, let nextName, let nextWeekday) = plan else {
            #expect(Bool(false))
            return
        }
        #expect(steps == 10_000)
        #expect(nextName == "Lower A")
        #expect(nextWeekday == "Monday")
        #expect(plan.nextLabel == "Next: Lower A Monday")
    }

    @Test func fridayMapsToLowerB() {
        let calendar = newYorkCalendar()
        let friday = civilDate(2026, 10, 2, calendar: calendar)
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: friday, calendar: calendar)
        guard case .session(_, let name, _) = plan else {
            #expect(Bool(false))
            return
        }
        #expect(name == "Lower B + Cond")
    }

    private func newYorkCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func civilDate(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts)!
    }
}

private let listJSON = """
{
  "programs": [
    {
      "id": "prog-2",
      "lineage_id": "line-1",
      "version": 2,
      "name": "Program V2",
      "status": "active",
      "parent_id": "prog-1",
      "created_at": "2026-09-20T12:00:00.000Z",
      "activated_at": "2026-09-21T12:00:00.000Z",
      "created_by": "app",
      "change_reason": "start week"
    },
    {
      "id": "prog-3",
      "lineage_id": "line-2",
      "version": 1,
      "name": "Draft",
      "status": "draft",
      "parent_id": null,
      "created_at": "2026-09-22T12:00:00.000Z",
      "activated_at": null,
      "created_by": "app",
      "change_reason": null
    },
    {
      "id": "prog-1",
      "lineage_id": "line-1",
      "version": 1,
      "name": "Program V2",
      "status": "archived",
      "parent_id": null,
      "created_at": "2026-09-01T12:00:00.000Z",
      "activated_at": null,
      "created_by": "app",
      "change_reason": null
    }
  ]
}
"""

private let detailJSON = """
{
  "id": "prog-2",
  "lineage_id": "line-1",
  "version": 2,
  "name": "Program V2",
  "status": "active",
  "parent_id": "prog-1",
  "created_at": "2026-09-20T12:00:00.000Z",
  "activated_at": "2026-09-21T12:00:00.000Z",
  "created_by": "app",
  "change_reason": "start week",
  "body": {
    "start_date": "2026-09-28",
    "daily_steps_target": 10000,
    "weeks": 6,
    "reduction_week": null,
    "rest_weekdays": ["sat", "sun"],
    "notes": "",
    "days": [
      {
        "day_index": 1,
        "weekday": "mon",
        "name": "Lower A",
        "conditioning": {
          "minutes": 8,
          "description": "steady: bike or incline treadmill walk, RPE 5-6/10"
        },
        "exercises": [
          {
            "order": 0,
            "name": "Leg press",
            "sets": 3,
            "reps": "10-12",
            "rir": 2,
            "rpe": 8,
            "rest_sec": 90,
            "load_note": "Start 145 lb",
            "substitutions": ["hack squat"],
            "notes": "Anchor."
          }
        ]
      },
      {
        "day_index": 2,
        "weekday": "tue",
        "name": "Upper Push",
        "conditioning": null,
        "exercises": [
          {
            "order": 0,
            "name": "Chest press machine",
            "sets": 3,
            "reps": 8,
            "rir": "2-3",
            "rest_sec": 120,
            "substitutions": [],
            "notes": null
          }
        ]
      }
    ]
  }
}
"""
