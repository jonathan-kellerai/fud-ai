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
- **Records only.** The app never suggests, recommends or computes a dose. Every dose is one the user typed in a schedule, or one in the user's own schedule preset (below). No dose is converted between units.
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
- `PeptideCompoundCatalog`: known compound names, a prescription flag (Testosterone only), and a default unit for the editor (Testosterone mL, hCG IU, MT2/BPC-157 mcg, Tesamorelin/Retatrutide/TB-500 mg). It holds no doses.
  - `PeptideMath.compoundOptions` is unchanged: only the user's own vials and logged compounds.
  - The sheets show the catalog as a second chip group.

### Day plan (`PeptideMath.dayPlan`)

The plan for one civil date is built from the existing `dueItems` and grouped into AM and PM.

- In each slot, reminders come first, then doses in the order the schedules were saved. The lab reminder therefore sits above that day's testosterone dose.
- Each dose row carries the schedule, its planned dose and the entry that logged it (if any). That entry is one attributed to the schedule; otherwise an unattributed entry of the same compound on that date.

### Logging a planned dose (`PeptideLogStore.logPlanned`)

One tap logs the schedule's planned dose at the current time, with `scheduleID` set.

- **mL doses** are saved as an mL draw, so a linked vial's remaining-volume math keeps working.
- **IU, mg and mcg doses** are saved as `dose` + `units`.
- **No vial is linked**, so `vialConcentrationAtSave` is nil and `derivedMilligrams` / `milligramDerivation` show no mg. With testosterone at an unknown concentration, the 0.3 mL is recorded as entered and no mg is worked out.
- **Editing.** The entry detail's edit sheet gains an Amount field for entries with a dose, through the existing `PeptideCorrectionChanges.dose/units` and the correction trail.

### Schema

- **Saved log.** `PeptideLogStore.fileVersion` goes from 3 to 4, and the snapshot gains `reminders`.
  - Versions 2 and 3 read as before; their schedules get a derived slot and no planned dose.
  - Nothing is rewritten at launch: the next change saves version 4.
  - An older build that opens a version-4 log goes read-only (`newerVersion`) instead of saving over the new fields.
- **Archive.** `PeptideArchive.formatVersion` goes from 1 to 2. Schedules carry `dose`/`slot`/`route`/`origin`, and the file carries `reminders`. Version-1 files import and restore as before.

### Preset (`Models/PeptideOwnSchedulePreset.swift`)

All the preset content lives in one data struct, with no personal names:

| Slot | Days | Compound | Dose | Route |
|---|---|---|---|---|
| AM | Mon, Thu | Testosterone (Prescription) | 0.3 mL | SQ |
| AM | Tue, Fri | MT2 | 250 mcg | |
| AM | Wed, Sat | hCG | 500 IU | |
| AM | Sun (weekly) | Retatrutide | 2 mg | |
| PM | daily | Tesamorelin | 1.4 mg | |
| PM | daily | BPC-157 | 500 mcg | |
| (not scheduled) | | TB-500 | 2 mg | |

- **Lab reminder.** "Labs: draw before testosterone injection", Thu 2026-12-31, 08:00–10:00.
- **Load my schedule** is on the Schedule screen and in Peptide settings. It opens a confirmation sheet that lists every record above and says "These are your own or prescribed doses, saved as records. The app doesn't suggest or change doses."
- **Loading.** `loadPreset` removes every schedule and reminder whose `origin` is `preset`, then adds the preset's records under fixed ids. A schedule replaced under the same id keeps its `startDate` and `createdAt`. Loading twice therefore saves the same records, and schedules the user added are never touched.
- **TB-500** isn't scheduled. It's in the compound catalog, so the ad-hoc log sheet can pick it. Its 2 mg is listed on the confirmation sheet but not saved; see open items.

### Notification

`Services/PeptideReminderNotifier.swift` (iOS) syncs pending local requests with the id prefix `peptide.reminder.` from `PeptideReminder.notificationPlans` (pure, tested).

- It schedules one request for each reminder that isn't dismissed, at its start time (08:00) on its date, in the device calendar. A reminder whose time has passed gets none.
- It only schedules when notifications are already authorized. It never prompts.
- `PeptidesView` runs it whenever the reminders change, except in Visual QA (fixed clock).

### Views

- **Schedule list:** "Load my schedule", then AM and PM sections. Each card shows compound, dose, route, days, and a Prescription badge. A Reminders section follows.
- **Schedule editor:** compound chips (the user's own, then the catalog), slot AM/PM, frequency (daily / days of week / weekly with one weekday / the existing every N days and N× per week), dose + unit (mL / IU / mg / mcg, defaulting to the catalog unit when the compound is picked and no unit is chosen yet), and route.
- **Today:** AM and PM slot cards. Each dose row has one "Taken" button (planned dose), or "Logged · Edit" once logged. A reminder row has Edit and Dismiss.
- **Week:** each day's AM / PM plan with logged or not, Log buttons on today only, and the reminder on its day.
- **Reminder editor:** title, date (any date; the preset default is a Thursday), start and end time, show on Today (not dismissed), delete.

## Tests

| Suite | What it covers |
|---|---|
| `PeptideSchedulePlanTests` | weekday expansion (daily, Mon/Thu, weekly Sun) into AM/PM for a sample week; two compounds in PM; legacy weekly unchanged; reminder before testosterone in AM; dismissed reminder hidden; notification plans (08:00 local, past ones dropped, dismissed dropped) |
| `PeptideDoseUnitTests` | units round-trip through the log file and the archive; testosterone mL with no concentration → no mg (`derivedMilligrams`, `milligramDerivation`); planned IU/mg/mcg saved as dose + units; corrections of a planned dose |
| `PeptideSchedulePresetTests` | preset contents (slots, days, doses, routes, Prescription), idempotent load, the user's own schedules kept, TB-500 unscheduled but in the catalog, lab reminder date/slot, refusal while read-only |
| `PeptideScheduleMigrationTests` | version 3 log → slots derived, no planned dose, saved as version 4 and read back; version-1 archive still imports; newer log version stays read-only |
| `PeptideNoNetworkTests` | gains the preset load, one-tap logging, and reminder flows |

The new suites are added to the `-only-testing` list, the log grep, and the suite-passed check in `ios-build.yml`.

Visual QA (`VisualQASnapshotTests+Peptides.swift`, synthetic fixtures plus the preset data):

- 130 schedule list grouped AM/PM
- 131 schedule editor with the weekday picker and units
- 132 Today with AM/PM slots on the lab-reminder day (Thu 2026-12-31)
- 133 the preset confirmation sheet

## Verification

- No Xcode on the agent box, so CI is the compiler. Linux harness `/tmp/r72-harness` (symlinks into this worktree): `LD_LIBRARY_PATH=/tmp/r66-libs swift test`. `PeptideNoNetworkTests` and `WorkoutNoNetworkTests` run alone.
- The lints from `ios-build.yml` (peptides on device, workouts on device, name gate) are run locally.
- `swiftc -parse` on every changed app file.

## Open items

1. **TB-500 2 mg isn't saved anywhere.** Nothing schedules it, and the ad-hoc log sheet doesn't prefill. If a saved "as needed" dose is wanted, that's a new record type.
2. **The ad-hoc log sheet still records draws in units or mL only.** mg/mcg/IU doses come from one-tap planned doses. Ad-hoc mass doses would need a unit change in `PeptideLogDraft`.
3. **hCG is not flagged Prescription.** Only Testosterone is, as asked. Flag it too?
4. **The lock screen shows the reminder title** ("Labs: draw before testosterone injection"). A generic body may be preferable for privacy.
5. **Notifications are only re-synced while the Peptides screen is open.** Changes always happen there, and pending requests survive relaunch.
6. **Week view logs only today's planned doses.** Logging a past day still goes through the log sheet with a chosen time.
