# Build 72: peptide schedule with fixed AM / PM slots

Branch `integ/build-72`, based on `fded74749` (the launch branch, TestFlight build 70).

## Problem

The peptide schedule doesn't match how the doses are actually taken:

- Doses happen in two fixed slots, morning and evening. One slot can hold more than one compound (PM: Tesamorelin and BPC-157).
- Schedules repeat on weekdays: daily, on chosen days (Mon/Thu), or weekly on one day (Sun).
- A schedule had no dose, and Today could only open an empty log sheet. Logging a planned dose took the whole sheet every time.
- Testosterone is a prescription and is drawn in mL from a vial whose concentration the app doesn't know.
- A lab draw has to happen before one testosterone injection, and nothing on Today reminded the user.
- Typing the whole schedule in by hand is slow and easy to get wrong.

## Rules that don't change

- **On this phone only.** No network code goes into peptide paths. The `Peptides stay on device` lint and `PeptideNoNetworkTests` must stay green. The lab reminder notification is a local `UNUserNotificationCenter` request.
- **Records only.** The app never suggests or recommends a dose. Every dose is one the user typed in a schedule, or one in the user's own schedule preset (below). No dose is converted between units.
- **U-100 units are arithmetic, not advice.** Every logged dose also records its U-100 syringe units (100 units = 1 mL), worked out from the user's own vial record: units = dose ÷ (vial amount ÷ water mL) × 100, and an mL dose is mL × 100. Without a concentration, a non-mL dose records no units.
- **Every saved log stays readable.** Versions 1, 2 and 3 load as before.

## Deliberate change from builds 67–71

Until now a schedule's amount was "the user's own note and is never used to fill a log". Here a schedule gets a **planned dose** (amount + unit) that the user types. One tap on Today logs that exact dose, and it can then be corrected with a reason, like any entry.

- The legacy `amount`/`units` on older schedules are still kept and never used. They were typed for the bridge era, and turning them into one-tap doses could log a number the user never confirmed here.
- The ad-hoc log sheet still starts with an empty draw and no unit.

## Design

### Model (`Models/PeptideSchedulePlan.swift`, `PeptideTrackingModels.swift`)

- `PeptideDoseSlot`: `.am` / `.pm`. A schedule's `slot` is optional on disk. When it's missing (any schedule saved before build 72), `daySlot` derives it from `timeOfDay`: before 12:00 is AM, otherwise PM. With no time it's AM.
- `PeptideDoseUnit`: `mL`, `IU`, `mg`, `mcg`. `PeptideDose` is an amount plus a unit, saved together, and never converted.
- `PeptideUserSchedule` gains `dose`, `slot`, `route`, and `origin` (`preset` for records the preset made; nil means the user made it).
- Weekly on one weekday: `Frequency(type: "weekly", days: [d])` falls on that weekday. A weekly schedule with no days (every one saved before build 72) still repeats every 7 days from its start, as before.
- `PeptideReminder`: a one-off record with a title, a civil date, a start and end time (minutes), `dismissed`, `origin` and `createdAt`. Its slot comes from its start time.
- `PeptideLogEntry` gains `scheduleID` (`schedule_id`), set when a planned dose is logged. That lets two schedules for one compound on one day be told apart. Entries without it still match a schedule by compound and date, as before.
- `PeptideCompoundCatalog`: known compound names, a prescription flag (Testosterone only), a default unit for the editor (Testosterone mL, hCG IU, MT2/BPC-157 mcg, Tesamorelin/GLP3 mg) and a note (GLP3: "identity unverified"). It holds no doses.
  - `PeptideMath.compoundOptions` is unchanged: only the user's own vials and logged compounds. The ad-hoc log sheet is unchanged.
  - The schedule editor shows the catalog as extra chips after the user's own.
- `PeptideVial` gains `premixed` (absent in older vials: mixed by the user). The mixing record is the existing amount + unit, water mL (premixed: the volume in the vial) and mix date. A premixed vial's label numbers need no "I mixed this vial" tick.
- `PeptideLogEntry` gains `syringeUnitsAtSave` (`syringe_units_at_save`): worked out once at save from the draw (at its scale) or from the dose and the vial. A correction of the amount works it out again.

### Day plan (`PeptideMath.dayPlan`)

The plan for one civil date is built from the existing `dueItems` and grouped into AM and PM.

- In each slot, reminders come first, then doses in the order the schedules were saved. The lab reminder therefore sits above that day's testosterone dose.
- Each dose row carries the schedule, its planned dose and the entry that logged it (if any). That entry is one attributed to the schedule; otherwise an unattributed entry of the same compound on that date.

### Logging a planned dose (`PeptideLogStore.logPlanned`)

One tap logs the schedule's planned dose at the current time, with `scheduleID` set. Tapping again the same day returns the entry already logged.

- **Saved as planned.** The dose is saved as `dose` + `units` in its own unit, for every unit including mL.
- **Linked vial.** It is linked to the compound's active vial (the latest mixed), with that vial's snapshot, and records its U-100 units.
- **No mg.** Testosterone's premixed vial has no amount, so its concentration is unknown. The 0.3 mL is recorded as entered, its units are 0.3 × 100 = 30, and no mg is worked out (`milligramsPerML` is nil and the entry has no draw for `milligramDerivation`).
- **Editing.** The entry detail's edit sheet corrects a planned dose as a dose (amount + unit), through `PeptideCorrectionChanges.dose/units` and the correction trail.

### Doses left (`PeptideMath.supply`)

For each active vial with a planned dose (from its compound's schedule):

- **Doses left** = (water mL, or volume if premixed) − the mL of every dose logged from the vial since it was mixed, all ÷ the dose's mL.
- **Remix soon** shows when less than one dose is left.
- **Never estimated:** one logged dose whose mL can't be known means nothing is shown.
- **Example:** Tesamorelin 5 mg + 0.5 mL at 1.4 mg is 3.57 doses. After three doses, 0.08 mL is left (0.57 doses), so it shows Remix soon.

### Schema

- **Saved log.** `PeptideLogStore.fileVersion` goes from 3 to 4, and the snapshot gains `reminders`.
  - Versions 2 and 3 read as before; their schedules get a derived slot and no planned dose.
  - Nothing is rewritten at launch: the next change saves version 4.
  - An older build that opens a version-4 log goes read-only (`newerVersion`) instead of saving over the new fields.
- **Archive.** `PeptideArchive.formatVersion` goes from 1 to 2. Schedules carry `dose`/`slot`/`route`/`origin`, and the file carries `reminders`. Version-1 files import and restore as before.

### Preset (`Models/PeptideOwnSchedulePreset.swift`)

All the preset content lives in one data struct, with no personal names:

| Slot | Days | Compound | Dose | Vial | Concentration | U-100 units |
|---|---|---|---|---|---|---|
| AM | Mon, Thu | Testosterone (Prescription), SQ | 0.3 mL | premixed | not entered | 30 |
| AM | Tue, Fri | MT2 | 250 mcg | 10 mg + 2 mL | 5 mg/mL | 5 |
| AM | Wed, Sat | hCG | 500 IU | 10,000 IU + 2 mL | 5,000 IU/mL | 10 |
| AM | Sun (weekly) | GLP3 ("identity unverified") | 2 mg | 10 mg + 1 mL | 10 mg/mL | 20 |
| PM | daily | Tesamorelin | 1.4 mg | 5 mg + 0.5 mL | 10 mg/mL | 14 (about 3.5 doses a vial) |
| PM | daily | BPC-157 | 500 mcg | 10 mg + 3 mL | 3.33 mg/mL | 15 |

There is no TB-500 in the preset: no compound is added and nothing is scheduled. Ad-hoc logging of any compound works as before.

- **Lab reminder.** "Labs: draw before testosterone injection", Thu 2026-12-31, 08:00–10:00.
- **Load my schedule** is on the Schedule screen and in Peptide settings. It opens a confirmation sheet that lists every record above and says "These are your own or prescribed doses, saved as records. The app doesn't suggest or change doses."
- **Loading.** `loadPreset` removes every schedule and reminder whose `origin` is `preset`, then adds the preset's records under fixed ids, and its vials under fixed ids (`preset-vial-…`), mixed on the load day.
  - A record replaced under the same id keeps its start date, mix date, status, notes and creation time. Loading twice therefore saves the same records.
  - Records the user added are never touched.
  - Loading confirms the mixed vials' numbers: the sheet lists every mix before anything is saved.

### Notification

`Services/PeptideReminderNotifier.swift` (iOS) syncs pending local requests with the id prefix `peptide.reminder.` from `PeptideReminder.notificationPlans` (pure, tested).

- It schedules one request for each reminder that isn't dismissed, at its start time (08:00) on its date, in the device calendar. A reminder whose time has passed gets none.
- It only schedules when notifications are already authorized. It never prompts.
- `PeptidesView` runs it whenever the reminders change, except in Visual QA (fixed clock).

### Views

- **Schedule list:** "Load my schedule", then AM and PM sections. Each card shows compound, dose, route, days, and a Prescription badge. A Reminders section follows.
- **Schedule editor:** compound chips (the user's own, then the catalog), slot AM/PM, frequency (daily / days of week / weekly with one weekday / the existing every N days and N× per week), dose + unit (mL / IU / mg / mcg, defaulting to the catalog unit when the compound is picked and no unit is chosen yet), and route.
- **Today:** AM and PM slot cards. Each dose row shows the dose, route and U-100 units, with one "Taken" button (planned dose), or "Logged · Edit" once logged. A reminder row has Edit and Dismiss.
- **Week:** each day's AM / PM plan with logged or not, Taken buttons on today only, and the reminder on its day. The week grid shows a planned dose in units ("14u"), so week text still never carries mg.
- **Vials:** Premixed and Prescription tags, Volume/Opened for premixed, doses left with per-dose units, and Remix soon. The vial editor has a premixed toggle.
- **Reminder editor:** title, date (any date; the preset default is a Thursday), start and end time, show on Today (not dismissed), delete.

## Tests

| Suite | Tests | What it covers |
|---|---|---|
| `PeptideSchedulePlanTests` | 6 | weekday expansion (daily, Mon/Thu, Tue/Fri, Wed/Sat, weekly Sun) into AM/PM for the week of 28 Dec; two compounds in PM; each logged on its own; two schedules of one compound told apart; legacy slot from time; lab reminder above testosterone, dismissed/moved; notification at 08:00 local, none once passed or dismissed |
| `PeptideDoseUnitTests` | 11 | units from the stored vial + water for all six (30, 5, 10, 20, 14, 15); testosterone mL with no concentration → no mg; no concentration → no units for non-mL; typed draws record units; Tesamorelin doses left 3.57 → Remix soon after three; only doses since mixing count; old vials without mixing data load; units round-trip (log, archive); a corrected dose works its units out again; dose text; week cells in units, never mg |
| `PeptideSchedulePresetTests` | 6 | preset contents; no TB-500 anywhere; schedules, vials, reminder saved, nothing logged; loading twice duplicates nothing and keeps the user's own records; stale preset records removed; refused while the log can't change |
| `PeptideScheduleMigrationTests` | 7 | version-3 log: slots derived, no planned dose, nothing rewritten; next change saves v4 and reads back; weekly-on-a-day vs legacy weekly; schedule_id kept through a correction; v1 archive restores, v2 needs reminders; archive round-trip; unreadable reminder skipped and counted |
| `PeptideNoNetworkTests` | +1 | preset load, plan, one-tap doses, doses left, reminder and notification plans, archive |

Three existing tests used the next version number as their "newer" literal (log 4, archive 2). They now use current + 1, with the same assertion. The archive key test pins `"format_version" : 2`.

Guards verified by breaking each and seeing a test fail: reminder-first ordering, schedule_id attribution, the since-mixing filter, preset replace-by-origin, and the concentration gate.

The new suites are added to the `-only-testing` list, the log grep, and the suite-passed check in `ios-build.yml`.

Visual QA (`VisualQASnapshotTests+Peptides.swift`, synthetic fixtures plus the preset data):

- 130 schedule list grouped AM/PM
- 131 schedule editor (Testosterone: weekday picker Mon/Thu, units mL, SQ)
- 132 Today with AM/PM slots on the lab-reminder morning (Thu 2026-12-31 07:30)
- 133 the preset confirmation sheet
- 134 Vials: each mixing record with doses left; Tesamorelin shows Remix soon

## Verification

- No Xcode on the agent box, so CI is the compiler. Linux harness `/tmp/r72-harness` (symlinks into this worktree): `LD_LIBRARY_PATH=/tmp/r66-libs swift test`. `PeptideNoNetworkTests` and `WorkoutNoNetworkTests` run alone.
- The lints from `ios-build.yml` (peptides on device, workouts on device, name gate) are run locally.
- `swiftc -parse` on every changed app file.

## Open items

1. **Not Xcode-verified yet.** The views, the notifier and the Visual QA shots are checked only by `swiftc -parse` here. CI on the pushed SHA is the compiler, and the screenshots need a review.
2. **The ad-hoc log sheet still records draws in units or mL only.** mg/mcg/IU doses come from one-tap planned doses.
3. **hCG is not flagged Prescription.** Only Testosterone is, as asked. Flag it too?
4. **The lock screen shows the reminder title** ("Labs: draw before testosterone injection"). A generic body may be preferable for privacy.
5. **Notifications are re-synced only while the Peptides screen is open.** Changes always happen there, and pending requests survive relaunch.
6. **Week view logs only today's planned doses.** Logging a past day still goes through the log sheet with a chosen time.
7. **Doses left counts doses linked to the vial.** One-tap doses link it automatically; an ad-hoc draw counts only if the user picked the vial.
8. **Loading the preset confirms its vial mixes** (it stamps the confirmation time), since the sheet lists them. If the user wants to tick each vial themselves instead, the load should save them unconfirmed.
9. **A preset re-load replaces the user's edits to preset schedules** (by design: "replaces previous preset-created schedules"). Vial mix dates and the reminder's creation time are kept.
