# Build 64 plan (rev 2): Challenges C1 + polish slice, one integration PR
Revised 2026-10-04 by the coder (Claude Code) after Codex's plan review (`/workspace/r64/codex-plan.log`, 13 findings). **Plan only:** no repo file was edited and no git state was changed.
- **Base:** `integ/build-63` @ `6f19a85b5`. Paths are relative to `ios/calorietracker/` unless they start with `ios/` or `.github/`.
- **Scope (Jonathan):** Challenges C1 + a polish slice. Three supporting refactors and one determinism harness commit come first.
- **Branch / PR:** `integ/build-64`, cut from `integ/build-63` only after 63 is green on its head SHA. **One** PR into `cursor/jl-physical-neon-bridge-366e`. Refactor, harness and behavior work go in separate, labelled commits (`docs:`, `refactor:`, `test:`, `test-harness:`, `behavior:`, `ci:`), and no commit mixes kinds.
- **CI budget:** 1 validation run on the full stack plus **at most 2 repair runs**. There is no per-phase run.
- **Labels:** `goldens-update` (because of the harness commits) and `build-64`.

## Accepted deviations from Codex's review
| Codex | Disposition |
|---|---|
| P1#1 (scope too big for the run budget) | **Not accepted (Jonathan's scope).** Mitigations: the stack is smaller than rev 1 (no DayKey refactor, no R6, no More cards, no Home header, no AppClock framework), there is a static pre-push checklist, and the repair-run policy below is fixed in advance. |
| P1#2 (refactor-first means separate PRs) | **Accepted deviation.** Our ship process is one integration PR with separately labelled commits, as in build 63. Each `refactor:` commit must be behavior-identical on its own. Reviewers use `git diff --color-moved=zebra` per commit. R6 is dropped, so no refactor commit changes fixture output. |
| P1#3 (More feature cards break the SE gate) | Accepted. P2 (More cards) is deferred. The CHALLENGES row goes **after About**, so the 7 gated rows keep their geometry. |
| P1#4 (private `eachSize`; missing `foodRange`) | Accepted. H1 exposes a narrow internal capture helper. R6/foodRange is dropped because it would need new fixture models. |
| P1#5 (a frozen env doesn't freeze the screens) | Accepted. Determinism uses explicit constructor/seed injection only, for the six volatile shots. What stays volatile is listed and reported, not gated. |
| P1#6 (re-keying can't fix time zones) | Accepted by narrowing the claim. Bucketing uses `Calendar.current`, like Progress and Home. Per-challenge time zones are dropped, and the limitation is documented. |
| P2#7–#11 | Accepted. See C1b–C1d. |
| P2#12 (AX5/light mode/44 pt) | 44 pt hit areas accepted and gated on the new screens. AX5, light-mode and Reduce Motion captures are deferred. |
| P3#13 (DayKey parser drift) | Accepted. The shared DayKey refactor is dropped and `StrengthWorkoutDate` is not touched. |

## Code facts this plan relies on (base SHA)
- `Utilities/JLFeatureFlags.swift`: compile-time `static let` Bools. There are no runtime flags yet.
- `ContentView.swift` (7,162 lines):
  - `HomeView` is at 838–2363, plus an extension at 2364–2448 and the private `BarcodeLookupAlertPresenter` at 2449–2489.
  - `ProfileSettingsCategory` is at 3694–3806, followed by `SettingsHubRowLabel` at 3808, the private `ProfileSettingsCategoryRow` at 3830 and the private `SettingsHubRowAnchor` at 3848.
  - `settingsHub` is at 4105–4170 and `hubSubtitle(for:)` at 4180.
- **Owner APIs reused as-is:**
  - `FoodStore.calories(for:)` and `protein(for:)` (`Stores/FoodStore.swift:187,191`);
  - `WaterStore.total(on:)` in ml (`:142`);
  - `HealthKitManager.fetchStepsByDay(from:through:) -> [Date: Int]?` (`:1310`). It returns `nil` when authorization fails, and it buckets by `Calendar.current`.
- **Change hooks already exist:** `foodStore.onEntriesChanged` (`calorietrackerApp.swift:389`) and `waterStore.onEntriesChanged` (`:400`). Both are single closures that are already assigned, so we add a line **inside** them and never reassign them. Steps have no observer (`HealthKitManager.swift:1828`).
- **Backup exclusion precedent:** `values.isExcludedFromBackup = true` in `Services/Gemma4LocalModelManager.swift:528`.
- **Volatile time sources:**
  - `RestTimerSheet.init` builds `RestSession` itself (`Views/RestTimerSheet.swift:19`), and `RestSession.init` takes `driver`/`initiallyMuted` (`Models/RestSession.swift:30`).
  - Home `selectedDate = .now` (`ContentView.swift:870`) and `paceNow` reads `Date()` (`Views/HomeV2Cards.swift:591`).
  - The harness seeds use `.now` (`VisualQASnapshotTests.swift:1476`), and `trainingDate` uses `.now` (`:1533`).
  - `peptideReferenceDate` is today at 09:00 (`VisualQAPeptideFixtures.swift:24`).
- **Harness:**
  - `eachSize` is `private` (`VisualQASnapshotTests.swift:883`).
  - The `axL` setting is `accessibility3`, **not AX5** (`:19`).
  - The SE More-hub gate requires all 7 rows to sit above the tab bar at rest (`:1074`).
  - The highest shot number is 77, and 78 is skipped.
- **CI:** `-only-testing` list at `.github/workflows/ios-build.yml:88–104`; VQA suites at `:207–208`.

## Defaults chosen (Jonathan can flip any)
| # | Default |
|---|---|
| 1 | **D64-1:** `JLFeatureFlags.challengesEnabled` reads UserDefaults `jl.flags.challenges` and defaults to **ON** when the key is absent. **No settings toggle in C1**: every candidate screen is either in ContentView or the wrong home. Turning it off means writing the key (debug) or shipping a new build. |
| 2 | Entry points: More hub CHALLENGES row (last row, after About) and the Home card. No Progress segment. |
| 3 | The Home card is hidden when there is no active challenge or the flag is off. Existing `HomeCardLayout.load` behavior is kept: an unknown ID is **appended at the end**, and the user can reorder it in Customize. |
| 4 | Duration 30 days (7–100); start = today; target > 0 and finite, ≤ 10,000,000. |
| 5 | Daily average = calendar average (a missing day counts as 0). Today counts as elapsed for pace, and today is provisional, never a miss. |
| 6 | Habit grace = `round(duration/15)`, clamped to `0…duration−1` (30 → 2). |
| 7 | Projection shown from day 3 (run rate). Required/day rounds up. |
| 8 | Rewards at 25/50/100 %, plus `streak(N)` for habits. An unlock is permanent. |
| 9 | Reminders at 19:00 local, only when the challenge is behind or today isn't hit. ≤ 2 per challenge and ≤ 20 in total. They obey the master `notificationsEnabled` switch and never request permission. |
| 10 | Water = app log only (no new HealthKit permission). Steps = the existing `.stepCount` read. |
| 11 | Storage: `Application Support/challenges.v1.json`, excluded from backup. Health numbers are never written to disk. |
| 12 | VQA reference time is **2026-10-07 09:00 America/New_York** for app shots and **Fri 2026-10-23 20:00 ET** for Challenges shots. |

## Commit order (each line is one commit)

### T0 `docs: build-64 plan`
- Copies this file to `docs/plans/build-64-challenges-c1.md`. Codex re-reviews it before code.

### R1 `refactor: move HomeView out of ContentView` (home-extract)
- `HomeView`, its extension and `BarcodeLookupAlertPresenter` (still `private`) move to `Views/Home/HomeView.swift`. It is a pure move: no renames, and access changes only where the compiler forces one (each is listed in the commit body).
- **Accept:** ContentView about −1,650 lines. `--color-moved` shows 0 non-moved lines apart from imports. No screenshot changes.

### R2 `refactor: move More hub types to Views/MoreHub` (more-hub-extract)
- `ProfileSettingsCategory`, `SettingsHubRowLabel`, `ProfileSettingsCategoryRow`, `SettingsHubRowAnchor` and the `settingsHub` row builders move to `Views/MoreHub/`. The two `private` rows become internal, which is the only access change.
- **Accept:** as for R1.

### R3 `refactor: split More hub subtitles (logic) from layout`
- **Logic:** `Models/MoreHub/MoreHubSubtitles.swift` holds `nonisolated struct MoreHubInputs`, the plain values `hubSubtitle` reads today with `now` as a field, and `static func text(for:_:) -> String`. The text is copied verbatim.
- **Layout:** `Views/MoreHub/MoreHubView.swift` renders the rows. `ProfileView` builds the inputs with `now: Date()`, and its sheets and destinations stay where they are.
- **Accept:** no screenshot changes.

### R4 `refactor: reference-time seams with live defaults`
- Only the constructor seams that the six volatile shots need. Every default reproduces today's call exactly:
  - `RestTimerSheet.init(…, now: Date = Date())`, forwarded to `RestSession` (adding the `now` parameter to `RestSession.init` if it is missing, defaulting to `Date()`);
  - `TextFoodInputView(…, rotatesPlaceholder: Bool = true)`, where `false` keeps index 0;
  - `StepsView(…, referenceDate: Date = Date())` for "Today/Yesterday" and "Last synced";
  - the `ProfileView` path gets `hubNow: Date = Date()`, passed to `MoreHubInputs.now`.
- **Not touched:** Home's `selectedDate`/`paceNow` (outside the six; threading it widens the Home surface).
- **Accept:** no screenshot changes. The grep shows no production call site passing a non-default value.

### R5 `test: pin More hub subtitles and the seams`
- New `MoreHubSubtitlesTests` (Swift Testing): every category, iCloud "2 h ago" with a fixed `now`, and notifications on/off with counts.

### H1 `test-harness: narrow internal capture helper` (no screenshot change)
- Adds an internal `VisualQACapture` with one entry point, `capture(_ name:, referenceNow:, heightMultiplier:, afterAppear:, content:)`, which wraps the existing private renderer. `eachSize` becomes a one-line call to it, and nothing else is widened.
- **Accept:** every existing PNG is byte-identical (apart from the six volatile shots), and the shot count is unchanged.

### H2 `test-harness: fixed reference time for the six volatile shots` (`goldens-update`)
- **Clock:** `VisualQAFixtures.referenceNow` = 2026-10-07 09:00 America/New_York, using an explicit `Calendar(identifier: .gregorian)` with the NY zone.
  - `trainingDate(rest:)` scans forward from **2026-10-07**: program week 2, outside the 10/19–10/25 reduction week.
- **Explicit injection** (no environment magic):

  | Shot | Fix |
  |---|---|
  | `05` rest timer | `RestTimerSheet(now: referenceNow)` in its separately hosted sheet root |
  | `16` food text input | `rotatesPlaceholder: false` |
  | `35` More hub | `hubNow: referenceNow`; the `icloudLastBackupISO` seed is derived from `referenceNow` |
  | `36` bridge settings | the `lastSyncDate` seed comes from `referenceNow` |
  | `06b` steps | `isoDay(offset:)` comes from `referenceNow`; `StepsView(referenceDate:)` |
  | `p2-bodyfat` | **not fixed**: its food-range stats read the live store, and the fix needs new fixture models (R6 dropped). Reported as volatile. |

- **Animations off:**
  - `UIView.setAnimationsEnabled(false)` in `setUp`, restored in `tearDown`;
  - `.transaction { $0.disablesAnimations = true }` on both renderers' roots **and** on each separately hosted sheet root.
- **Still not deterministic (reported, not gated):**
  - `p2-bodyfat`;
  - Home shots (`01`, `52`): `selectedDate`/`paceNow` still use the live clock;
  - the Peptides shots (`60–69`): `peptideReferenceDate` is today at 09:00;
  - the weight seeds at `:1476`.
  - The handoff lists these as the next determinism slice.
- **Accept:** the expected-change list below matches. The `05` timer reads 1:30, `16` shows placeholder 0, `35` and `36` show the timestamps derived from 2026-10-07, and `trainingDate` shots show the week of 10/07. A same-SHA re-run on another day happens only if a repair slot is left over; otherwise cross-day stability is **claimed only from the pinned values**, not proven.

### C0 `behavior: runtime Challenges flag (D64-1)`
- `JLFeatureFlags.challengesEnabled: Bool` is a computed `static var` that reads `UserDefaults.standard.object(forKey: "jl.flags.challenges") as? Bool ?? true`, so the stored default is ON. Its doc comment names the key.
- **Tests:** `JLFeatureFlagsTests` covers an absent key → true, `false` → false and `true` → true, using a suite-scoped `UserDefaults(suiteName:)` through an internal `challengesEnabled(in:)` overload. There is no mock type.

### C1a `behavior: challenge models + engine (pure)`
- **Files:** `Models/Challenges/ChallengeDay.swift`, `ChallengeModels.swift` and `ChallengeEngine.swift`. Everything is `nonisolated`, `Sendable` and `Codable`.
- **`ChallengeDay`:** year/month/day, built from a date and a calendar. It provides `string`, a strict `init?(string:)`, `startDate(in:)`, `adding(days:in:)` and `days(from:to:in:)`, which counts calendar days and never divides by 86,400. It is challenge-only and unrelated to `StrengthWorkoutDate`.
- **Models:**
  - `Challenge { id, title, kind, metric, startDay, durationDays, graceDays, rewards, stake?, reminder, quickAddChips, createdAt, endedEarlyAt? }`. There is no time-zone field.
  - `ChallengeKind = .total(target) | .dailyAverage(target) | .dailyHabit(HabitRule)`.
  - `HabitRule = .atLeast | .atMost | .checkIn`.
  - `ChallengeMetric = .steps | .waterAppLog | .protein | .calories | .custom(name, unit)`.
  - Manual `ChallengeEntry { id, day, value, note?, createdAt }`.
  - Check-ins are stored as `checkIns: [ChallengeDay: Bool]`, which is last-write-wins and **not** additive, so a YES→NO correction replaces the YES.
- **Engine:** `progress(challenge, daily: [ChallengeDay: Double], availability: .available | .unavailable, now:, calendar:)`. The calendar is passed in, and production passes `Calendar.current`.
- **Contracts:**
  - **Window:** `startDay … startDay+duration−1`.
  - **Pre-start:** status `.notStarted`, `dayIndex` 0, no pace, no reminders.
  - **Post-end** (or `endedEarlyAt`): `dayIndex` clamped, status final (`complete`/`failed`/`ended`), `requiredPerDay` nil.
  - **Final day:** `requiredPerDay = ceil(remaining / daysLeftInclToday)`, where the divisor is ≥ 1, so it never divides by zero.
  - **Total/average:** `complete` as soon as the target is met (logging stays open until the end); `failed` at the end if below target.
  - **Habit:** a day is *hit* when the rule holds. For `.atMost`, a day with no logged data is **not hit** (unknown ≠ under). `complete` once `hitDays ≥ duration − graceDays`. `failed` as soon as `missedDays > graceDays`, which makes completion impossible. Grace keeps the streak alive, and once grace is exhausted a miss resets it.
  - **Unavailable data:** `.unavailable` → status `.noData`. The UI shows "No step data", never 0. No rewards or reminders are evaluated.
  - **Invalid input:** a decoded challenge with a non-finite or ≤ 0 target, or a duration outside 7–100, gets status `.invalid` ("Can't evaluate") and does not crash.
- **Tests:** `ChallengeEngineTests` with a fixed NY calendar:
  - golden 10,000 / 30 d at day 12, total 3,900 → expected 4,000, delta −100, projected 9,750, required 339;
  - average 87,400 over days 1–9 → 9,711, needs 10,124/day;
  - day 1, day 2 (no projection), pre-start, post-end, final-day division, over-target, zero entries;
  - invalid and NaN targets;
  - habit grace spend and exhaustion, fail as soon as completion is impossible, complete at `duration − grace`, the YES→NO correction;
  - `.atMost` with no data;
  - DST: a streak from 10/12 to 11/02 is day 22 with no merged or split days;
  - the same inputs under a UTC calendar give a self-consistent result (this is the documented limitation, not a cross-zone claim).

### C1b `behavior: reward evaluator + reminder planner (pure)`
- **Reward evaluator:** `ChallengeRewardEvaluator.newUnlocks(rewards, progress, alreadyUnlocked:) -> [RewardUnlock]`.
- **Reminder planner:** `ChallengeReminderPlanner.plan([(Challenge, ChallengeProgress)], now:, calendar:) -> [PlannedNotification]`.
  - IDs are `challenge.<uuid>.nudge` and `challenge.<uuid>.checkin`.
  - It plans one-shot reminders for today only, applying the caps from default 9 with the most-behind first.
- **Tests:**
  - `ChallengeRewardEvaluatorTests`: unlocks once at the crossing; stays unlocked after a downward edit; two thresholds crossed by one entry unlock in order; `streak(N)`; nothing on `.noData`.
  - `ChallengeReminderPlannerTests`: none on a hit day, pre-start, post-end, `.noData`, or once the fire time has passed; caps 2 and 20 with 25 challenges in the input; identical output when re-planned.

### C1c `behavior: ChallengeStore with one reconcile()`
- `Stores/ChallengeStore.swift` is `@Observable` and MainActor. `init(fileURL:)` lets tests use a temporary directory.
- **Persisted:** challenges, manual entries, check-ins and the reward log (`unlockedAt`, `claimedAt`, stake `paidAt`).
- **In memory only:** `autoValues` and their availability.
- **Writes are atomic.** After each write the file is marked `isExcludedFromBackup = true`, using the Gemma pattern.
- **Corrupt file:** it is copied to `challenges.corrupt-<ts>.json` (also excluded from backup) and the store starts empty.
- **Write failure:** the in-memory state is kept and the error is exposed as `lastSaveError`.
- **Mutations:** `create`, `add(entry)`, `setCheckIn(day:, value:)`, `undo(entryID)`, `endEarly`, `updateReminder`, `claim`, `markStakePaid`. Entries outside the window or with non-finite or ≤ 0 values are rejected with a typed error.
- **`reconcile(now:)` is the single evaluation path.** It recomputes progress from the manual data and `autoValues`, runs the evaluator, persists **new** unlocks once, appends them to `pendingUnlocks`, and returns the planned notifications.
  - Every mutation and every provider refresh ends in `reconcile`.
- **Tests:** `ChallengeStoreTests` (`@MainActor`, temp directory):
  - round-trip; corrupt-file backup; backup-exclusion flag set on the main file and on the corrupt copy;
  - write failure in an unwritable directory; undo; out-of-window rejection;
  - an **automatic** crossing (set `autoValues`, then reconcile) unlocks once; reload gives no duplicate; a duplicate refresh gives no duplicate; a downward correction keeps the unlock.

### C1d `behavior: metric providers + reminder wiring`
- **Providers:** `Services/Challenges/ChallengeMetricProviders.swift` holds MainActor adapters that turn the owner APIs into plain `[ChallengeDay: Double]`.
  - Steps: `fetchStepsByDay`; `nil` → `.unavailable`.
  - Water: `WaterStore.total(on:)`.
  - Protein and calories: `FoodStore.protein(for:)` / `calories(for:)`.
  - **No new nutrition math.**
- **Scheduling:** `NotificationManager.scheduleChallengeReminders(_:)` removes the `challenge.` prefix and then adds. It is serialized by one stored `Task` that is cancelled and awaited before the next replacement. It is a no-op when the master switch is off.
- **Triggers:**
  - scene `.active`: refresh steps, then reconcile;
  - every store mutation;
  - **one added line** inside the existing `foodStore.onEntriesChanged` and `waterStore.onEntriesChanged` closures in `calorietrackerApp.swift`;
  - opening the list or detail refreshes steps.
- **Documented limitation:** steps have no observer, and today-only reminders are not refreshed unless the app runs again.
- **Time zones:** documented in the code and the plan doc. Days are bucketed in `Calendar.current` at evaluation time, the same as Progress and Home. Travelling re-buckets **all** sources consistently. Per-challenge zones would need calendar-aware owner queries (deferred).
- **App wiring:** `@State challengeStore` plus `.environment` on both chains in `calorietrackerApp.swift`.
- **Tests:** `ChallengeMetricProviderTests` with real `FoodStore`/`WaterStore` instances (temp storage). The day values must equal `calories(for:)`, `protein(for:)` and `total(on:)` for the same days.

### P0 `behavior: shared Iron components for Challenges`
- `Theme/IronComponents.swift` holds `IronSectionLabel`, `IronStatusPill` and `IronStatTile`, and nothing that Challenges doesn't use.
  - They use `@ScaledMetric`, wrap rather than truncate, and have accessibility labels written as sentences.
  - New tokens: `IronTheme.pillFillOpacity 0.10` and `borderTintOpacity 0.35`.
- **Tests:** add to `IronThemeTests`: the pill and tile accessibility strings, and the token values.

### C1e `behavior: Challenges views, Home card, More row`
- **Screens** (`Views/Challenges/`): `ChallengeListView`, `ChallengeCreateView`, `ChallengeDetailView` (ring, `PaceChartShape` as a plain `Shape`, the tiles), `ChallengeQuickAddSheet` (TODAY/YESTERDAY, chips, YES/NO for check-ins, 5 s UNDO), `RewardUnlockedView` (fade under Reduce Motion, `.success` haptic), `RewardLogView`, `ChallengeHomeCard`, `ChallengeRing` and `ChallengeDayGrid`.
- **Views only display:** every value comes from `ChallengeProgress`.
- **Wiring (ContentView +0 lines):**
  - `HomeCardID.challenges`: every exhaustive switch is updated (`HomeV2Cards:174`, the titles and icons in `CustomizeHomeSheet`). It is hidden when the flag is off.
  - `MoreHubView`: a CHALLENGES `NavigationLink` row placed **after About**, behind the flag, with id `settings.category.challenges`.
- **44 pt:** every control has a `frame(minWidth: 44, minHeight: 44)` hit area plus `contentShape`, even where the glyph is smaller.
- **Accessibility identifiers:** `challenges.list`, `challenges.row.<n>`, `challenges.create.save`, `challenge.detail.log`, `challenge.quickAdd.log`, `challenge.quickAdd.chip.<n>`, `reward.claim`, `home.card.challenges`.
- **Tests:** add to `HomeV2Tests`: a legacy saved layout loads with `.challenges` appended at the end, and the flag-off filter hides it.

### C1f `test-harness: Challenges VQA` (`goldens-update`; new shots only)
- **File:** `VisualQASnapshotTests+Challenges.swift`, which uses `VisualQACapture` with `referenceNow` = 2026-10-23 20:00 ET.
- **Fixture:** an in-memory `ChallengeStore` in a temporary directory, seeded with real values.
  - "10K KB SWINGS": days 1–12 are `300,320,340,330,335,440,300,330,310,345,340,210`, total 3,900.
  - "WATER 3 L" habit, with one grace day used.
  - "NO ALCOHOL" check-in.
- **Shots** (default and axL, Pro and SE): `79-challenges-list`, `80-challenge-create`, `81-challenge-detail`, `82-challenge-quick-add`, `83-challenge-reward-unlocked`. Heights go through `VisualQACanvas.cappedMultiplier`.
- **Gate:** on SE axL, the frames of `challenge.detail.log`, `challenge.quickAdd.log` and the quick-add chips are ≥ 44 × 44.

### P1 `behavior: Train segmented underline (T1)`
- `TrainModeSwitch` (`Views/CCLaddersView.swift:23`): the selected tab sits on the surface with bone text and a 2 px blood underline, plus a `.selection` haptic. Each segment has a hit area of at least 44 pt.

### P2 `behavior: Peptides status pills`
- The due rows use `IronStatusPill` with LOGGED / PLANNED / PENDING. The state comes from the existing peptide model, and the view only maps it to a pill.

### CI `ci: run the new suites and fail on zero executed tests`
- **Add** to `-only-testing`: `MoreHubSubtitlesTests`, `JLFeatureFlagsTests`, `ChallengeEngineTests`, `ChallengeRewardEvaluatorTests`, `ChallengeReminderPlannerTests`, `ChallengeStoreTests`, `ChallengeMetricProviderTests`, `IronThemeTests`, `HomeV2Tests`. Nothing is removed.
- **New guard step:** for each listed new suite, grep the test log for its passed line with at least 1 test. A missing line fails the job, so a misspelled identifier can't give a lying green.
- **Pre-existing reds:** `IronThemeTests` and `HomeV2Tests` exist but have not run in CI before. If either is already red, that is reported as pre-existing and fixed in a repair run; it is never removed.

## CI plan (1 validation + ≤ 2 repair runs)
- **Pre-push static checklist (no Xcode on the box):**
  - every new `@Suite` type name matches its `-only-testing` entry;
  - every `switch` over `HomeCardID` is updated;
  - `nonisolated` on all pure types (default MainActor isolation on the app target);
  - test suites touching stores are `@MainActor`;
  - no `@unchecked Sendable`, and no deprecated `onChange(of:perform:)`;
  - ContentView line count ≤ base − 1,650.
- **V (validation):** push T0…CI and run once on the head SHA.
- **Gate:**
  - compile clean;
  - all `-only-testing` suites green, with every new suite actually executed;
  - the VQA diff against the build-63 green artifact equals the expected table;
  - the SE More-hub gate is unchanged and green;
  - the new shots are not blank or clipped.
- **Attribution:** refactor equivalence is proven at the head, because only shots attributed to H2/C1e/C1f/P1/P2 may move. Any other moved shot is a bug in a refactor commit.
- **Repair 1:** fix compile errors first, then tests, then VQA, with fix-forward `fix:` commits that each name one concern.
- **Repair 2:** same order. Any **polish** (P1/P2) commit that is still failing is reverted with a new revert commit instead of being re-fixed, so Challenges keeps priority.
- **Stop rule:** if Repair 2 is red, stop and report the red run with its logs to Jonathan (D64-4). There are no further runs and no gate is weakened.

## Expected screenshot changes (`goldens-update` before/after table)
| Commit | Shots | Why |
|---|---|---|
| R1–R5, H1, C0–C1d, P0 | **none** | refactors, harness plumbing and logic without UI |
| H2 | `05`, `16`, `35`, `36`, `06b` | pinned to the reference-time values |
| H2 | shots built on `trainingDate`: `02*`, `03`, `04*`, `24-train-resume-workout`, `49–51`, `73*`, `77` | the session date is pinned to the week of 10/07 |
| C1e | `10b-more-settings-scrolled` (and `10-more-settings` only if the new last row is visible at rest) | the CHALLENGES row after About |
| C1f | new `79`–`83` × {default, axL} × {Pro, SE} | new screens |
| P1 | `02-train-lifting-day` and the CCLadders/Train-switch shots | the underline segment |
| P2 | the Peptides due-row shots in `60–69` | status pills |
| — | `p2-bodyfat`, `01`, `52`, the remaining `60–69` content | **still volatile (reported, not gated)** |

Home shots do not gain the card, because the fixtures have no active challenge. Any moved shot that is not in this table is a bug.

## Swift 6 / Xcode 26 risks
1. Pure types must be `nonisolated`. Otherwise `Codable` conformances become MainActor-isolated and the Swift Testing functions need `await`.
2. The providers stay MainActor and hand plain `[ChallengeDay: Double]` to the engine. `FoodEntry` is not assumed to be `Sendable`.
3. `UNMutableNotificationContent` is built inside the MainActor method and added with async `add`.
4. Moving `private` file-scope types forces internal access. Grep for `fileprivate` extensions on `HomeView` before R1.
5. A Swift Testing `-only-testing` identifier must be the `@Suite` type name. The guard step catches a 0-test selection.

## Deferred (with reason)
- **Challenges:**
  - per-challenge time zones and calendar-aware owner queries (Codex P1#6);
  - a step observer;
  - the Progress segment;
  - logged-days averages; never-miss-twice; the calorie band;
  - weigh-in and exercise metrics (C2);
  - HealthKit water;
  - multi-habit check-in; actionable notifications; deep links;
  - result lock; restart; recap card; App Intent;
  - iCloud backup of challenges;
  - sharing, boards and the bridge (C3);
  - `81b` habit-grid and `84` Home-card shots.
- **Determinism:**
  - `p2-bodyfat` (needs `ProgressV2Fixture.foodRange`);
  - Home `selectedDate`/`paceNow`;
  - `peptideReferenceDate`;
  - the weight seeds;
  - emptying `refactor_gate_volatile_shots` (engine config, after proof).
- **Polish:**
  - More feature cards and the "DATA STAYS ON DEVICE" footer (SE gate, Codex P1#3/P2#9);
  - the Home brand header, numbered labels and card radius (they risk the Home gates);
  - the Peptides trust footer and feature cards;
  - `IronFeatureCard`, `IronTrustFooter`, `IronBrandHeader`;
  - a generic `IronSegmented`;
  - the forged hero; T2/T3; Food, Progress and Coach polish;
  - `IronPrimaryButtonStyle` Dynamic Type.
- **Accessibility:** AX5 actual-height captures, light-mode and Reduce Motion VQA (P2#12). Only the 44 pt hit-area gate ships.
- **Refactor:** the shared DayKey (Codex P3#13).

## Open decisions for Jonathan
- **D64-2:** approve the `goldens-update` commits H2 and C1f.
- **D64-3:** a Progress segment in C2?
- **D64-4:** if Repair 2 is red, which commits ship?
- **D64-5:** is a Challenges toggle wanted in a later build (it needs a non-ContentView settings home)?

## Done means
- CI is green on the PR head SHA; the run URL and SHA are cited, plus the repair-run URLs if any.
- Codex signs off on the plan, then on the PR.
- Jonathan checks on the device:
  - "10K KB SWINGS / 30 d" with a +50 quick-add: the ring, pace and projection match the golden;
  - a steps challenge equals Progress steps for 3 days;
  - denied Health access shows "No step data";
  - a reward unlocks once, including from steps alone;
  - a reminder fires only when the challenge is behind.
- TestFlight goes out only with Jonathan's explicit approval.
