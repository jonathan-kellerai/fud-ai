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
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: sunday, context: .empty, calendar: calendar)
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
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: monday, context: .empty, calendar: calendar)
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
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: saturday, context: .empty, calendar: calendar)
        guard case .rest(let steps, let nextName, let nextWeekday) = plan else {
            #expect(Bool(false))
            return
        }
        #expect(steps == 10_000)
        #expect(nextName == "Lower A")
        #expect(nextWeekday == "Monday")
        #expect(plan.nextLabel == "Next: Lower A Monday")
    }

    @Test func seededNullsStayEmptyAndResolveRestFromNotes() throws {
        let record = try JSONDecoder().decode(TrainingProgramRecord.self, from: Data(seededJSON.utf8))
        let body = try #require(record.body)
        #expect(body.weeks == nil)
        #expect(body.reductionWeek == 4)
        #expect(body.restWeekdays == ["sat", "sun"])
        #expect(body.days.map(\.name) == ["Lower A", "Pull / Hinge", "Lower B + Cond"])

        let legPress = try #require(body.days[0].exercises.first)
        #expect(legPress.rir.isEmpty)
        #expect(legPress.restSec == nil)
        #expect(legPress.reps == "10-15")
        #expect(legPress.resolvedRestSeconds == 90)
        #expect(legPress.parsedStartLoadLb == 145)
        #expect(ExerciseRest.lowerBoundSeconds(in: legPress.notes) == 90)

        let logged = body.days[0].asProgramV2Day()
        #expect(logged.title == "Lower A")
        #expect(logged.exercises[0].restSeconds == 90...90)
        #expect(logged.exercises[0].startLoadLb == 145)
        #expect(logged.exercises[0].rirTarget.isEmpty)
        #expect(logged.exercises[0].loadNote.hasPrefix("Start load: 145 lb"))
        #expect(logged.exercises[0].notes.contains("2-3 s eccentric"))

        let pull = body.days[1].asProgramV2Day()
        #expect(pull.title == "Pull / Hinge")
        #expect(pull.exercises[0].name == "Lat pulldown (neutral or long bar)")
        #expect(pull.exercises[0].rirTarget == "2")
        #expect(pull.exercises[0].restSeconds.lowerBound == 60)
        #expect(pull.exercises[0].startLoadLb == 80)

        let lowerB = body.days[2]
        #expect(lowerB.name == "Lower B + Cond")
        #expect(lowerB.exercises[0].parsedStartLoadLb == nil)
        #expect(lowerB.exercises[1].parsedStartLoadLb == 0)
        #expect(lowerB.exercises[1].resolvedRestSeconds == 120)

        let encoded = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["weeks"] as? NSNull != nil)
        let encodedDays = object?["days"] as? [[String: Any]]
        let firstExercise = (encodedDays?.first?["exercises"] as? [[String: Any]])?.first
        #expect(firstExercise?["rir"] as? NSNull != nil)
        #expect(firstExercise?["rest_sec"] as? NSNull != nil)
    }

    @Test func restParserUsesTheRestLineAndBundledDefault() {
        #expect(ExerciseRest.lowerBoundSeconds(in: "Rest: 90-120 s. 2-3 s eccentric.") == 90)
        #expect(ExerciseRest.lowerBoundSeconds(in: "Rest: 120 (use the full rest) s.") == 120)
        #expect(ExerciseRest.lowerBoundSeconds(in: "Rest: 60-75 s.") == 60)
        #expect(ExerciseRest.lowerBoundSeconds(in: "RIR target: 2-3 RIR. 2-3 s eccentric.") == nil)

        let explicit = TrainingProgramExercise(
            order: 1,
            name: "Leg press",
            sets: 3,
            reps: "10-15",
            restSec: 45,
            notes: "Rest: 90-120 s."
        )
        #expect(explicit.resolvedRestSeconds == 45)

        let fromBundle = TrainingProgramExercise(
            order: 1,
            name: "Overhead press machine",
            sets: 3,
            reps: "8-12",
            notes: "RIR target: 2-3 RIR."
        )
        #expect(fromBundle.restSec == nil)
        #expect(fromBundle.resolvedRestSeconds == 90)

        let unknown = TrainingProgramExercise(
            order: 1,
            name: "Mystery lift",
            sets: 3,
            reps: "8"
        )
        #expect(unknown.resolvedRestSeconds == 90)
        #expect(ExerciseRest.startLoadPounds(from: "Start load: select on first session.") == nil)
        #expect(ExerciseRest.startLoadPounds(from: "Start load: 0 (bodyweight).") == 0)
        #expect(ExerciseRest.startLoadPounds(from: "Start load: 80 lb. if 80 feels easy use 85.") == 80)
    }

    @Test func nullRestWeekdaysDecodeAsEmpty() throws {
        let json = """
        {"start_date":"2026-09-28","daily_steps_target":10000,"weeks":null,"reduction_week":null,"rest_weekdays":null,"notes":null,"days":[]}
        """
        let body = try JSONDecoder().decode(TrainingProgramBody.self, from: Data(json.utf8))
        #expect(body.weeks == nil)
        #expect(body.restWeekdays.isEmpty)
        #expect(body.days.isEmpty)
    }

    @Test func bridgeErrorsPreferMessageThenIssues() {
        let notDraft = Data(#"{"error":"not_draft","message":"only draft programs can be edited or deleted; use POST /api/programs/:id/revise"}"#.utf8)
        #expect(BridgeErrorFormatting.userMessage(from: notDraft) == "only draft programs can be edited or deleted; use POST /api/programs/:id/revise")

        let rejected = Data(#"{"error":"body.nope is not a recognized field","issues":["body.nope is not a recognized field","body.days is required (array)"]}"#.utf8)
        #expect(BridgeErrorFormatting.userMessage(from: rejected) == "body.nope is not a recognized field\nbody.days is required (array)")

        let children = Data(#"{"error":"has_children","message":"delete the child version first"}"#.utf8)
        #expect(BridgeErrorFormatting.userMessage(from: children) == "delete the child version first")
    }

    @Test func reviseRequestSendsCreatedBy() throws {
        let payload = ProgramReviseRequest(
            body: .blank(),
            name: "Program V2",
            changeReason: "load tweak",
            activate: false,
            createdBy: "app"
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        #expect(object?["change_reason"] as? String == "load tweak")
        #expect(object?["created_by"] as? String == "app")
        #expect(object?["activate"] as? Bool == false)
    }

    @Test func fridayMapsToLowerB() {
        let calendar = newYorkCalendar()
        let friday = civilDate(2026, 10, 2, calendar: calendar)
        // Day 1–4 done Mon–Thu, so the cycle lands on Day 5 on Friday.
        let plan = TrainingProgramSchedule.resolve(.bundledV2(), on: friday,
            context: programCycleContext(reaching: 5, on: "2026-10-02"), calendar: calendar)
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

private let seededJSON = """
{
  "id": "a37d2986-f43c-4309-acd5-ef802e9965c2",
  "lineage_id": "a37d2986-f43c-4309-acd5-ef802e9965c2",
  "version": 1,
  "name": "Program V2",
  "status": "active",
  "parent_id": null,
  "change_reason": "Seeded from approved Program V2 (2026-09-26)",
  "created_by": "seed",
  "created_at": "2026-09-27T16:18:26.074Z",
  "activated_at": "2026-09-27T16:18:26.074Z",
  "body": {
    "start_date": "2026-09-28",
    "daily_steps_target": 10000,
    "weeks": null,
    "reduction_week": 4,
    "rest_weekdays": ["sat", "sun"],
    "notes": "program-v2",
    "days": [
      {
        "day_index": 1,
        "weekday": "mon",
        "name": "Lower A",
        "conditioning": {"minutes": 8, "description": "8 min steady: bike or incline treadmill walk, RPE 5-6/10"},
        "exercises": [
          {
            "order": 1,
            "name": "Leg press",
            "sets": 3,
            "reps": "10-15",
            "rir": null,
            "rpe": null,
            "rest_sec": null,
            "load_note": "Start load: 145 lb. First session: 145 x 12-15.",
            "substitutions": [],
            "notes": "Rest: 90-120 s. RIR target: sets 1-2: 2-3 RIR; last set 1-2 RIR. Anchor. 2-3 s eccentric."
          }
        ]
      },
      {
        "day_index": 3,
        "weekday": "wed",
        "name": "Pull / Hinge",
        "conditioning": null,
        "exercises": [
          {
            "order": 3,
            "name": "Lat pulldown (neutral or long bar)",
            "sets": 2,
            "reps": "10-12",
            "rir": 2,
            "rest_sec": null,
            "load_note": "Start load: 80 lb. First session: 80 x 10-12 @ 2 RIR.",
            "substitutions": [],
            "notes": "Rest: 60-90 s. RIR target: 2 RIR. the logging app's suggestion engine will say 'hold 90'."
          }
        ]
      },
      {
        "day_index": 5,
        "weekday": "fri",
        "name": "Lower B + Cond",
        "conditioning": {"minutes": 12, "description": "12 min steady"},
        "exercises": [
          {
            "order": 1,
            "name": "Cable pull-through",
            "sets": 3,
            "reps": "8-12",
            "rir": null,
            "rest_sec": null,
            "load_note": "Start load: select on first session.",
            "substitutions": [],
            "notes": "Rest: 90-120 s."
          },
          {
            "order": 2,
            "name": "Chest press machine",
            "sets": 3,
            "reps": "10-15",
            "rir": null,
            "rest_sec": 120,
            "load_note": "Start load: 0 (bodyweight).",
            "substitutions": [],
            "notes": "Rest: 60-90 s. full 120 s rest."
          }
        ]
      }
    ]
  }
}
"""
