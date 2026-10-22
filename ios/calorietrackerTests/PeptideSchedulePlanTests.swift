import Foundation
import Testing
@testable import calorietracker

/// The AM / PM day plan: weekday schedules expand into their slots for a
/// sample week, one slot holds several compounds, a planned dose is logged
/// on its own, and the lab reminder sits above that morning's testosterone.
@MainActor
struct PeptideSchedulePlanTests {
    /// Mon 2026-12-28 … Sun 2027-01-03, the week with the lab reminder.
    private let week = (0..<7).map { ReconMath.addDays("2026-12-28", $0) }

    private func loaded() -> PeptideLogStore {
        let store = PeptideLogStore(persistence: .inMemory)
        let now = PeptideMath.date(civil: "2026-12-01", minutes: 9 * 60)!
        #expect(store.loadPreset(.own, today: "2026-12-01", now: now) == nil)
        return store
    }

    private func names(_ plan: PeptideDayPlan, _ slot: PeptideDoseSlot) -> [String] {
        (plan.slots.first { $0.slot == slot }?.items ?? []).map { item in
            switch item {
            case .reminder(let reminder): "reminder: " + reminder.title
            case .dose(let due): due.schedule.compound
            }
        }
    }

    @Test func weekdaySchedulesExpandIntoAMAndPMForASampleWeek() {
        let store = loaded()
        let am = week.map { names(store.dayPlan($0), .am) }
        let pm = week.map { names(store.dayPlan($0), .pm) }
        #expect(am == [
            ["Testosterone"],                                                  // Mon
            ["MT2"],                                                           // Tue
            ["hCG"],                                                           // Wed
            ["reminder: Labs: draw before testosterone injection", "Testosterone"], // Thu 31 Dec
            ["MT2"],                                                           // Fri
            ["hCG"],                                                           // Sat
            ["GLP3"],                                                          // Sun
        ])
        // Daily: two compounds share every PM slot.
        #expect(pm == Array(repeating: ["Tesamorelin", "BPC-157"], count: 7))
        #expect(store.dayPlan(week[0]).slots.map(\.slot) == [.am, .pm])
    }

    @Test func eachCompoundInASlotIsLoggedOnItsOwn() throws {
        let store = loaded()
        let monday = week[0]
        let evening = PeptideMath.date(civil: monday, minutes: 21 * 60)!
        let tesa = try #require(store.schedules.first { $0.compound == "Tesamorelin" })
        let id = try #require(store.logPlanned(scheduleID: tesa.id, now: evening))
        let pm = try #require(store.dayPlan(monday).slots.last)
        let logged = pm.items.compactMap { item -> (String, String?)? in
            if case .dose(let due) = item { return (due.schedule.compound, due.entry?.id) }
            return nil
        }
        #expect(logged.map(\.0) == ["Tesamorelin", "BPC-157"])
        #expect(logged.map(\.1) == [id, nil])
        // The other day's plan is untouched.
        #expect(store.dayPlan(week[1]).slots.last?.items.contains { if case .dose(let due) = $0 { return due.taken } else { return false } } == false)
    }

    @Test func twoSchedulesOfOneCompoundOnOneDayAreToldApart() throws {
        let store = PeptideLogStore(persistence: .inMemory)
        let morning = PeptideUserSchedule(id: "am", compound: "BPC-157", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-12-01", dose: PeptideDose(amount: 250, unit: .mcg), slot: .am)
        let evening = PeptideUserSchedule(id: "pm", compound: "BPC-157", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-12-01", dose: PeptideDose(amount: 250, unit: .mcg), slot: .pm)
        store.saveSchedule(morning)
        store.saveSchedule(evening)
        let at = PeptideMath.date(civil: "2026-12-02", minutes: 8 * 60)!
        let id = try #require(store.logPlanned(scheduleID: "am", now: at))
        let due = PeptideMath.dueItems(date: "2026-12-02", schedules: store.schedules, entries: store.entries)
        #expect(due.map(\.entry?.id) == [id, nil])
        // A draw logged on its own still counts for a schedule, as before build 72.
        var draft = PeptideLogDraft.new(compound: "bpc 157", now: at.addingTimeInterval(12 * 3600))
        draft.drawText = "15"
        draft.drawUnit = .units
        let drawID = try #require(store.log(draft, now: at))
        #expect(PeptideMath.dueItems(date: "2026-12-02", schedules: store.schedules, entries: store.entries).map(\.entry?.id) == [id, drawID])
    }

    @Test func schedulesSavedBeforeBuild72TakeTheirSlotFromTheirTime() {
        let early = PeptideUserSchedule(compound: "A", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-12-01", timeOfDay: 11 * 60 + 59)
        let noon = PeptideUserSchedule(compound: "B", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-12-01", timeOfDay: 12 * 60)
        let none = PeptideUserSchedule(compound: "C", frequency: ReconMath.Frequency(type: "daily"), startDate: "2026-12-01")
        let plan = PeptideMath.dayPlan(date: "2026-12-05", schedules: [early, noon, none], entries: [], reminders: [])
        #expect(names(plan, .am) == ["A", "C"])
        #expect(names(plan, .pm) == ["B"])
    }

    @Test func aDismissedReminderLeavesThePlanAndAnEditedDateMovesIt() throws {
        let store = loaded()
        let thursday = week[3]
        let reminder = try #require(store.reminders.first)
        #expect(reminder.date == "2026-12-31" && ReconMath.weekday(reminder.date) == 4)
        #expect(reminder.slot == .am && reminder.timeText == "8:00 AM–10:00 AM")
        #expect(store.setReminderDismissed(id: reminder.id, dismissed: true) == nil)
        #expect(names(store.dayPlan(thursday), .am) == ["Testosterone"])
        var moved = reminder
        moved.dismissed = false
        moved.date = "2027-01-04"
        #expect(store.saveReminder(moved) == nil)
        #expect(names(store.dayPlan(thursday), .am) == ["Testosterone"])
        #expect(names(store.dayPlan("2027-01-04"), .am).first == "reminder: Labs: draw before testosterone injection")
        // Any date is allowed; an empty title or a backwards window isn't.
        moved.title = " "
        #expect(store.saveReminder(moved) != nil)
        moved.title = "Labs"
        moved.endMinutes = 7 * 60
        #expect(store.saveReminder(moved) == "The end time is before the start time.")
        #expect(store.deleteReminder(id: reminder.id) == nil)
        #expect(store.reminders.isEmpty)
    }

    @Test func theLabReminderNotifiesAt8AMLocalOnItsDayOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let reminder = PeptideReminder(id: "labs", title: "Labs: draw before testosterone injection", date: "2026-12-31", startMinutes: 480, endMinutes: 600)
        let before = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 7, minute: 59))!
        let plans = PeptideReminder.notificationPlans([reminder], now: before, calendar: calendar)
        #expect(plans.count == 1)
        #expect(plans.first?.id == "peptide.reminder.labs")
        #expect(plans.first?.fireAt == DateComponents(year: 2026, month: 12, day: 31, hour: 8, minute: 0))
        #expect(plans.first?.body == "Labs: draw before testosterone injection · 8:00 AM–10:00 AM")
        let after = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 8, minute: 1))!
        #expect(PeptideReminder.notificationPlans([reminder], now: after, calendar: calendar).isEmpty)
        var dismissed = reminder
        dismissed.dismissed = true
        #expect(PeptideReminder.notificationPlans([dismissed], now: before, calendar: calendar).isEmpty)
    }
}
