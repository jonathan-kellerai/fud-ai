# Build 66 — Next workout in the cycle + change today's workout

## Problem
Jonathan (Tue 10/6 07:22 ET, screenshot of Train showing "Today's Workout: Upper Push"):
> "We need a way to change the workout for the day. Further default should be the next workout in the cycle."

`TrainingProgramSchedule.resolve` maps calendar weekday -> program day (Mon..Fri = Day1..Day5). Today is Tue so it shows Day 2,
but the last logged session was Day 4 (Thu 10/1), Day 5 was skipped, and Program V2 says order beats calendar and unfinished
days do not roll into the next week. The coach plan for today is Day 1 Lower A, week 2.

## Evidence
- Program V2 (`/home/box/jamie-lewis/plans/program-v2.md` line 35, `program-v2.json` sequence_rule): "Order beats calendar. Do the next
  unfinished day in the Day1→Day5 order. Saturday can be a makeup day. Never do two lifting sessions in one day ... Missed days don't
  carry into the next week." Week numbers are counted from week1 start 2026-09-28 (Mon–Sun ET weeks); reduction week = week 4 = 10/19–10/25.
- Coach routine planned files (`training/ledger/planned/2026-10-05-day1-lower-a.json`, `2026-10-06-day1-lower-a.json`): program_week 2,
  Day1_LowerA, "Day5 not logged (unfinished days do not roll over) ... next unfinished day this week = Day1".
- Neon (project long-tooth-97197675, read-only query 10/6): COMPLETED program-v2 rows `1-mon` 9/28, `2-tue` 9/29, `3-wed` 9/30, `4-thu` 10/1;
  older program-v1 rows use `Day4_UpperPhysique`. Active program v4: start_date 2026-09-28, rest_weekdays [sat, sun], reduction_week 4, 5 days.
- Bridge (`/workspace/jl-workout-ingest`): no "today"/"next session" endpoint; the gym PWA lists DAYS and the user picks. So the bridge
  does not decide the day and needs no change (YAGNI). The rule lives once in the app (Models) with tests.

## The rule (single source of truth: `ProgramCycle` in `ios/calorietracker/Models/ProgramCycle.swift`)
Inputs: program body, the date, and a `TrainingDayContext` { history: completed program sessions, override: today's chosen day?, inProgress: unsaved draft? }.
1. Before the program start date -> `.upcoming` (Day with the lowest day_index, on the first non-rest date >= start). (unchanged meaning)
2. Today's override (set from the Change sheet, stored with today's civil date) -> that day. Ignored on any other date.
3. A session already COMPLETED today (history) -> that day (latest one today). One lifting session per day: the card does not jump ahead the moment you save.
4. An unsaved draft started today -> that day (resume it).
5. Rest weekday (body.rest_weekdays) -> `.rest`, next label = the cycle suggestion on the next non-rest date.
6. Cycle suggestion: program week W = ET calendar week of today counted from start_date (ProgramWeekRules.weekNumber).
   Let L = latest completed session (by session date, then recorded order) whose date is in week W and before today.
   - no L -> Day 1 (lowest day_index) of week W (also: no history at all -> Day 1).
   - L exists -> the next day_index after L.dayIndex.
   - L was the last day (Day 5) -> week W is complete -> `.rest`, next = Day 1 on the first training date of week W+1 (wrap + week advance).
   Missed days never carry into the next week: a new week always starts at Day 1 (this is the 10/6 case: last Day 4 week 1 on 10/1 -> Day 1 week 2).
   After an overridden session is logged, the cycle continues from the day actually done (it is just history).
History = bridge `GET /api/workouts` rows with kind COMPLETED, synthetic != true, session_date <= today, day index parsed from
program_day `"<n>-<wkd>"` (iOS) or `"Day<n>_..."` (PWA/v1), else by matching title to a program day name; unparseable rows ignored.
The last successful bridge list is cached on device (offline launches keep the right day); the bridge list replaces the cache when it loads.
Program week for set rules (week 3 extra sets, week 4 reduction) stays the calendar week of the session date, so 10/19–10/25 sessions are cut.

Known divergence (documented, not coded): the coach routine says "next unfinished day" — after an override that skips ahead
(e.g. Day 1 then Day 3), the coach would go back to Day 2; the app continues from the day done (Day 4), as Jonathan asked.

## Design (SoC)
- Models/ProgramCycle.swift (pure, Foundation only, `nonisolated` value types): `CompletedProgramSession {dayIndex, sessionDate "yyyy-MM-dd"}`
  + `init?(remote: RemoteWorkout, days:)` + `static func dayIndex(programDay:title:days:)`; `TodayWorkoutOverride {date, dayIndex}`;
  `TrainingDayContext {history, override, inProgress}`; `ProgramCycle.suggestion(body:history:on:calendar:)` -> `.day(dayIndex:week:)` / `.weekComplete(week:)` / nil before start.
- Models/TrainingProgram.swift: `TrainingProgramSchedule.resolve(_:on:context:calendar:)` (context REQUIRED, no default, so no caller silently keeps the weekday map)
  implements steps 1–5 using ProgramCycle; delete the weekday->day lookup helpers it no longer uses. Add `suggestedDayIndex(_:on:context:calendar:)`
  (resolution ignoring the override; on rest days the next session's day) and `workoutOptions(_:on:)` -> [{dayIndex, name, exerciseCount, conditioning}] (dated via programV2Day(for:on:)).
- Stores/TrainProgressStore.swift: `@Observable final class`, `init(defaults: UserDefaults = .standard)`, `static let shared`. Persists
  history cache (`jl.physical.trainHistory.v1`) and override (`jl.physical.todayOverride.v1`) as JSON. API: `replaceHistory(with: [RemoteWorkout], days:)`,
  `setOverride(dayIndex:on:calendar:)`, `clearOverride()`, `context(draft: WorkoutDraft?, days:) -> TrainingDayContext`. Choosing the suggested day clears the override.
- Views: JLPhysicalTabView / HomeV2Cards / CoachIntentRouter / consumeWorkoutHandoff all call resolve with the store's context. Train feeds
  the store from its bridge list (raise limit 5 -> 10); Home feeds it from its 50-row list. Coach gets `trainingContext: (() -> TrainingDayContext)?` defaulting to the shared store (draft nil).
- Train card (extracted to Views/Train/TodaysWorkoutCard.swift first, pure move): subtitle "Week 2 · Day 1 · Next in cycle" or "Changed for today";
  a "Change" button (>=44 pt, label "Change workout", hint "Pick a different program day for today") on session AND rest/week-complete cards
  (Saturday makeup). Overridden card shows "Back to suggested". Sheet Views/Train/ChangeWorkoutSheet.swift: NavigationStack list of all
  program days (Day N · name, "7 exercises · 8 min steady ...", "Suggested" tag on the cycle's day, checkmark on current), a "Back to suggested"
  row when overridden, Cancel. Iron & Blood tokens only (IronTheme), Dynamic Type (no fixed heights, wraps at AX sizes), VoiceOver labels combine
  each row ("Day 3, Pull / Hinge, 6 exercises, conditioning ..., suggested, selected"), SE layout.

## Commits (one concern each)
1. docs: this plan.
2. refactor: Train uses TrainingProgramSchedule.programDay(in:matching:) instead of 2 local copies (+ Coach copy). No behavior change.
3. refactor: extract Today's Workout card from JLPhysicalTabView into Views/Train/TodaysWorkoutCard.swift (pure move).
4. refactor: ProgramWeekRules.weekNumber(civilDay:body:) split out of weekNumber(on:body:) (same results; tests unchanged).
5. behavior: ProgramCycle rule + CompletedProgramSession parsing + ProgramCycleTests.
6. behavior: resolve(context:) + TrainProgressStore + callers (Train, Home, Coach, handoff) + update existing schedule tests + TrainProgressStoreTests.
7. behavior: Change sheet + override on the Train card.
8. test-harness: VQA shots 100-train-next-in-cycle, 101-train-change-workout, 102-train-workout-changed (pinned Tue 2026-10-06 09:00 ET, stubbed history Day1–4 9/28–10/1, injected TrainProgressStore) [goldens-update]; VQA fixture trainingDate uses an empty context.
9. ci: add ProgramCycleTests, TrainProgressStoreTests, TrainingProgramTests, ProgramWeekRulesTests to -only-testing (+ the grep list / zero-test guard).

## Acceptance / tests
- ProgramCycleTests: real case (Day1–4 9/28–10/1, today Tue 10/6 -> Day 1 Lower A, week 2; also Mon 10/5); no history -> Day 1; in-week sequence
  (Day1 Mon -> Tue Day 2; Day1 Mon + Day2 Tue, Wed missed -> Thu Day 3); week boundary (Day 2 on Fri 10/2 -> Mon 10/5 Day 1);
  week complete (Day4+Day5 Thu -> Fri rest, next Lower A Monday); Saturday rest names the next session; override today wins, stale override ignored;
  after an overridden Day 3 on 10/6 -> 10/7 Day 4; completed today stays; draft today resumes, draft yesterday ignored; reduction week
  (Day1 Mon 10/19 -> Tue 10/20 Day 2, holdLoads + reduction weekNote via programV2Day); before start -> upcoming; parsing ("4-thu", "Day4_UpperPhysique",
  title fallback, garbage nil, non-COMPLETED / synthetic / future-dated ignored); workoutOptions lists 5 days with counts/conditioning; suggestedDayIndex ignores override.
- TrainProgressStoreTests: override survives a new store on the same defaults (restart), expires next day, clear, choosing suggested clears, history cache round-trip.
- Screenshots: 100/101/102 × {default, axL} × {Pro, SE}; every other Train shot's card may now say Day 1 (empty history in VQA) — expected.

## Codex plan review — resolutions (binding)
Full review: /workspace/r66/codex-plan.log.
1. (P1 override vs one-session-per-day) Precedence becomes: **completed today > override > draft started today > cycle**. Once any session is logged today the card shows that day as "Logged today" and the Change control is hidden; the override is consumed. If a draft for a different day exists when Start is tapped on the (changed) day, Start goes through the existing resume/discard confirmation (WorkoutHandoffDecision / PendingResume) instead of silently replacing the draft. Tests: override set then same/different day logged today; draft-today + override.
2. (P1 successor vs lowest-unfinished) Keep **successor of the last completed this week** — the brief explicitly says "the program day after the most recently COMPLETED logged workout" and "after logging an overridden session the cycle should continue from the day actually done"; Program V2's drop order (Day4 then Day2) is skip-ahead too. Divergence from the coach routine's "next unfinished" wording is reported to Jonathan, not coded. Tests: Day1 → overridden Day3 → Day4; backward override (Day3 then Day1 done) → Day2.
3. (P1 Day5→Day1 next day) Deferred and documented: only reachable by deliberately logging Day 5 on Sunday (a rest day) via Change; Saturday makeup → Monday is not "the day after". No code.
4. (P1 civil dates) One contract: **the device's civil date** (calendar passed by the caller, default .current) is "today" for resolution, overrides, drafts (WorkoutDraft.sessionDate is device-civil) and history (bridge session_date is the civil date the app posted). The program week for the cycle is computed from that civil-date string via `ProgramWeekRules.weekNumber(civilDay:body:)` (Mon–Sun, from start_date). The existing instant-based `weekNumber(on:body:)` / set rules stay exactly as they are (refactor 4 only extracts, keeping the instant API and its results). Tests include 10/18→10/19 and 10/25→10/26 week boundaries.
5. (P1 partial lists) History ordering is deterministic: sort by sessionDate, then recordedAt (store it, optional), then list position. Train fetches 20 rows (not 10), Home keeps 50; both lists are COMPLETED rows ordered by recorded_at and either covers the current week, so a replace from either gives the same suggestion. After the logger's save succeeds, the accepted session is recorded locally (`TrainProgressStore.recordCompleted(dayIndex:sessionDate:)`) at the ONE place where save success is observed (find it; prefer the logger's existing onSaved path used by both Train and Home, or WorkoutDraftStore.save's caller) so a failed refresh still advances; the next successful bridge list replaces the cache.
6. (P1 CI ids) ProgramWeekRulesTests is an extension of WorkoutLoggerLogicTests (already selected) — do NOT add a ProgramWeekRulesTests id. Add `TrainingProgramTests`, `ProgramCycleTests`, `TrainProgressStoreTests` to -only-testing and to the grep/zero-test guard, in the FIRST behavior commit that adds tests (ci change can be its own commit right after the docs commit). Resolver cases (override/draft/completed-today) live in the schedule tests (ProgramCycleTests may cover both ProgramCycle and TrainingProgramSchedule.resolve).
7. (P2 isolation) No `nonisolated` annotations: keep the default MainActor isolation like every other model in this target; TrainProgressStore is a plain @Observable final class (MainActor by default); persisted values are Codable structs, not the store. Tests mirror TrainingProgramTests' style (which already calls the MainActor schedule from @Test funcs).
8. (P2 Coach draft) ChatView passes `trainingContext:` to CoachIntentRouter.route built from TrainProgressStore.shared + the environment WorkoutDraftStore's draft; the default (tests) is an empty context provider.
9. (P2 VQA) New shots use an injected TrainProgressStore on a fresh suite + pinned date + stubbed COMPLETED history. Existing shots keep `.shared`; their stub rows are kind "strength" and are filtered out (kind must be COMPLETED), so their history is empty and deterministic (cards show Day 1). Review of changed existing shots happens in the PR (goldens-update label).
10. (P2 PR split) Refactor commits 2–4 are pushed and CI'd on their own SHA first (separate run proving no behavior/pixel change), then the behavior commits. One PR, two CI-proven stages (time budget). Pre-start `.upcoming` = Day 1 on the first non-rest date >= start (documented change for non-Monday starts).
