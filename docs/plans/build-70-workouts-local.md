# Build 70 — Workouts live on this phone only

Branch `integ/build-70` off build 67 (7f13e35cd). It will be rebased onto build 68/69, so peptide-redesign
and AI Providers files are left alone except where §8 says otherwise.

## 1. Problem and evidence

Jonathan: *"Save workout data locally as well for privacy."* Clarified: workouts are stored **only** on
the phone, same as peptides. No bridge backup, no sync toggle.

Today every workout path goes through the Neon bridge (`NeonBridgeService`, `/api/workouts`). Line
numbers are at 7f13e35cd.

| file:line | what | act |
|---|---|---|
| Stores/WorkoutDraftStore.swift:276-288 | `save()` POSTs `/api/workouts`; the draft is cleared only after the bridge accepts | R: save to the on-device log |
| Views/ProgramV2WorkoutLogView.swift:153 | last performance from `ExerciseHistoryLoader` (bridge list + details) | R: from the log |
| Services/ExerciseHistoryLoader.swift:22-66 | `listWorkouts` + up to 50 `getWorkout` calls | R: read the log, no async |
| Views/WorkoutHistoryEditView.swift:121, 162, 172 | GET, PUT and DELETE `/api/workouts/{id}` | R: log `detail`, `correct`, `delete` |
| Views/JLPhysicalTabView.swift:245, 398, 409 | recent list, history list, swipe delete | R: from the log |
| Views/HomeV2Cards.swift:886-897 | week marks and today's session via list + detail | R: from the log |
| Models/ProgressV2/ProgressTrainingLoader.swift (all) | `/api/workouts` + `/api/workouts/{id}` with caches | R: totals from the log |
| Models/ProgressV2/ProgressV2Training.swift:520-708 | bridge decoding, `ProgressBridgeConfig`, `ProgressTrainingAPI`, detail cache | D (the week math stays) |
| Services/WorkoutSyncService.swift (all) | unused queue that posted `StrengthWorkoutSession`s; only its queue count is read (ContentView:2289) | D: the file is removed (see §8) |
| Services/NeonBridgeService.swift:74-131 | `postWorkout`, `listWorkouts`, `getWorkout`, `updateWorkout`, `deleteWorkout` | D |
| Stores/TrainProgressStore.swift:31-36 | next-in-cycle history replaced by the bridge list | R: replaced by the log |
| Models/NeonBridgeModels.swift:33-190 | workout payload, response and record types | Move to `Models/WorkoutRecords.swift` (refactor); delete `WorkoutResponse`/`ListWorkoutsResponse` |

**Progression.** No `/api/progression` call exists. `ProgressionRule` (+5 lb at the top of the range with
RIR ≥ 4, −5 lb below the range or at RIR 0) already runs on the phone. Its input, `LastPerformance`, came
from the bridge through `ExerciseHistoryLoader`; it now comes from the log. The rule itself is unchanged.

**Steps and HealthKit** are unchanged. So are CC ladders, programs, nutrition and the peptide bridge calls
(§9 lists every remaining call site).

## 2. Target design

- **One owner: `WorkoutLogStore`** (`Stores/WorkoutLogStore.swift`, `@Observable @MainActor`). It has no
  URLSession and no `NeonBridgeService`. It is injected from the app root, like `WorkoutDraftStore`.
  - `save(_ draft: WorkoutDraft, now:) -> String`: one local record from the draft's session.
  - `correct(id:, title:, conditioning:, notes:, sets:, now:)`: the record changes in place, and the
    version it replaces is kept in `revisions`.
  - `delete(id:, now:)`: the record is kept as a tombstone (`deleted_at`). It leaves every list, and a
    re-import can't bring it back.
  - Reads: `workouts` (live records, newest session first), `detail(id:)`, `details`.
  - Import: `importSummary(of:)` (preview) and `importFile(_:)`.
  - Backup: `backupData()` and `restoreBackupData(_:)`. Reset: `deleteAll()`.
- **Read shape.** A record is the bridge's own `{workout, sets}` (`RemoteWorkout` and `RemoteWorkoutSet`)
  plus `revisions` and `deleted_at`. Last performance, next-in-cycle, Home, Progress and History keep their
  math and only change where the rows come from. Renaming the `Remote*` types is deferred (§10).
- **The file: `WorkoutLogFile`.** It is the peptide approach, through the shared `DeviceLogFile`:
  - Location: `Application Support/WorkoutLog/workout_log_v1.json`, `{version: 1, workouts: [...], omitted?}`.
  - Writes are atomic. Unreadable bytes are set aside as `workout_log_v1.unreadable-<stamp>.json` and
    never overwritten.
  - Before an import changes the log, a `pre-import` copy is written next to it.
  - Decoding is lossy per record. A record that can't be read is counted (`omitted`), and History says so.
  - A newer `version` leaves the file untouched and runs read-only in memory, with a note.
- **Save.** The logger saves to the log, and the draft clears only once the log has written the record.
  A failed write keeps the draft and shows the error, as a failed POST did. The confirmation says
  "Saved on this phone".
- **Next-in-cycle.** `TrainProgressStore.replaceHistory(with:)` is fed the log's workouts. While the log
  is empty (nothing saved or imported yet on this build), the cached history from the last bridge list is
  kept, so upgrading doesn't reset Train to Day 1 before the import.
- **Progress.** `ProgressTrainingLoader.load(range:workouts:now:)` builds the same
  `ProgressTrainingSummary` from the log. The list is complete, so nothing is truncated or "didn't load".
  The `.notConfigured` and `.failed` states and their bridge wording go.

## 3. One-time import from a file

- **UI.** More › **Workouts** (a new hub row under Peptides) shows how many workouts are on this phone,
  then "Workout history" and **Import from a file**. Import opens `.fileImporter([.json])`, which is
  the Files picker. A preview sheet shows the counts before anything changes: "11 new workouts, 0 already
  on this phone, 0 couldn't be read". After import it says "11 workouts imported, 0 duplicates".
- **Format: exactly `jl-workouts-export-v1`.**
  `{format, exported_at_utc?, workouts: [{workout: {id, kind, program_version, program_day, title, units,
  session_date, conditioning, notes[], content_hash, source_fingerprint, synthetic, recorded_at}, sets:
  [{id, workout_id, set_order, exercise, load_lb, reps, rir, rpe, logged_at, exercise_position,
  planned_position}]}]}`.
  - Any other `format` is refused. So is a file over 5 MB.
  - Elements are decoded lossily: a bad element is skipped and counted.
- **Idempotent.** An element is a duplicate when its `id` is already in the log (tombstones included), or
  when its non-null `content_hash` matches a record already in the log (or earlier in the same file).
  Re-importing the same file adds 0.
- **No network and no key.** The file comes from the Files picker. The bridge isn't contacted.
- **Fixture.** `calorietrackerTests/Fixtures/jl-workouts-import.json` is a synthetic export with the
  bridge export's schema and shape (11 workouts, 87 sets, the same field names). Every id, hash, load,
  note and time in it is made up; the repo is public, so no real training data is committed. Visual QA
  shots use their own synthetic 11-workout file.

## 4. Backup and Delete Everything (same as peptides)

- **iCloud backup.** `CloudBackupService` adds `workouts.log.v1`, holding the log file's bytes. A restore
  decodes and validates the whole log first, then saves it before it replaces the phone's log. A bad
  value keeps the phone's workouts and says so. A backup from an older build, without the key, leaves
  workouts alone.
- **Delete Everything** calls `workoutLogStore.deleteAll()`. That removes the file, every copy set aside
  next to it, and the in-memory records.

## 5. Tests (real inputs; temp files; no mocks except the tripwire)

- **`WorkoutLogStoreTests`** (new):
  - A save from a real `WorkoutDraft` has every set, conditioning, the program day and the session date.
  - It persists across a reload (a new store on the same file).
  - Correct changes sets and notes and keeps the prior version in `revisions`, across a reload.
  - Delete leaves a tombstone, hides the record from every read, and survives a reload.
  - A corrupt file is set aside and never overwritten. One bad record is skipped and counted. A newer
    version is left untouched.
  - The draft clears only after the log saved it. A failed write keeps the draft.
  - Last performance and the progression input come from the log. Next-in-cycle with an empty log keeps
    the cache.
- **`WorkoutImportTests`** (new, using the fixture):
  - Importing the file gives 11 workouts with their sets.
  - Importing twice still gives 11 (the second run adds 0, with 11 duplicates).
  - A content_hash duplicate under a new id is skipped. A tombstoned id isn't re-added.
  - A wrong format, an oversize file and malformed JSON are refused and change nothing.
  - A bad element is skipped and counted.
  - A `pre-import` copy is written before the change.
- **`WorkoutBackupAndResetTests`** (new): backup round-trip, a bad backup keeps the phone's log, and
  `deleteAll`.
- **`WorkoutNoNetworkTests`** (new, `.serialized`, the peptide tripwire pattern): a `URLProtocol` with
  no host exemptions records and fails every request. A control request proves it's in the path. Then
  save, reload, correct, delete, import, History/Home/Train reads, last performance and the Progress
  summary all run, and the log must stay empty. CI runs this suite alone, in its own process, as it does
  for peptides.
- **Changed:**
  - `WorkoutDraftStoreTests`: save goes to a log, not a post closure.
  - `TrainProgressStoreTests`: the empty-log rule.
  - `ProgressV2MathTests`: the summary from log records.
- **Deleted, because the behavior they gate is removed on Jonathan's instruction** (each listed in the
  as-built section):
  - The workout lines of `BridgeKeyStorageTests.everyBridgeClientSendsTheConfiguredSecretStoreKey`.
  - In `ProgressV2MathTests`: the bridge-decoding, config and cache tests.
- **CI:**
  - The new suites join the `-only-testing` list, the diagnostic grep and the passing-suite loop.
  - `WorkoutNoNetworkTests` gets its own step and guard.
  - A new lint, **"Workouts stay on device"**, fails if `Stores/WorkoutLog*`, `Stores/WorkoutDraftStore`,
    `Models/WorkoutRecords`, `Services/ExerciseHistoryLoader`, `ProgressTrainingLoader`, the logger, the
    History/Edit/Import views or `JLPhysicalTabView` mention `api/workouts`, `URLSession`, `URLRequest`
    or `NeonBridgeService`. It also fails if `NeonBridgeService.swift` has `/api/workouts` or a workout
    method. Nothing is removed from any list.

## 6. Visual QA (`[goldens-update]`)

- **13 History and 14 detail:** now seeded into an in-memory log, not the stub bridge. They should look
  the same.
- **106 Workouts settings:** the import button, before any import.
- **107 import preview:** "11 new workouts".
- **108 after import:** "11 workouts imported, 0 duplicates".
- **109 logger save confirmation:** "Saved on this phone".
- **10 More hub:** gains the Workouts row (SE stays gated by `assertHubRowsAboveTabBar`).
- **Progress Training card shots:** the subtitle wording changes.
- **Train shots 100-103:** seeded into the log, so there's no change.

## 7. Commit sequence

1. `docs:` this plan
2. `refactor:` extract `DeviceLogFile` from `PeptideLogFile` (pure)
3. `refactor:` workout record types move out of `NeonBridgeModels` (pure)
4. `behavior:` on-device workout log (store, file, tests)
5. `behavior:` the logger saves to the phone; History, edit, delete, Train, Home, Progress and last
   performance read the phone; the bridge workout calls are removed
6. `test:` the bridge export as the import fixture
7. `behavior:` import workouts from a file (More › Workouts)
8. `behavior:` workouts in iCloud backup and Delete Everything
9. `test:` workout no-network tripwire
10. `ci:` wire the suites, the tripwire step and the lint
11. `test-harness:` Visual QA from the on-device log, plus the new shots `[goldens-update]`
12. `docs:` as built, and still calls the bridge

## 8. Risks and decisions for Jonathan

- **No real data in a public repo.** The import fixture is synthetic (§3), not his export.
- **File removed:** `Services/WorkoutSyncService.swift`. It is dead code whose whole purpose was a bridge
  post. Rule 0 asks for per-instance approval to delete files, so this needs his OK before push.
- **Upgrade gap.** Until he imports, History, Progress and last performance are empty on the phone.
  Next-in-cycle keeps its cache.
- **`PeptideLogFile` refactor.** Build 68 changes `keepBeforeUpgrade` to take a `label:`. `DeviceLogFile`
  already takes one, so on rebase `PeptideLogFile.keepBeforeUpgrade(label:)` becomes a one-line delegate.
- **Compile risks** (no Xcode here; CI on a pushed SHA is the only proof):
  - `RemoteWorkout` Codable is MainActor-isolated by default. It is decoded only in `@MainActor` code.
  - `WorkoutDraft.payload` is unchanged. `save` converts the payload to a record.

## 9. Still calls the bridge

Filled in as built (§ As built).

## 10. Deferred

- Rename `RemoteWorkout` / `RemoteWorkoutSet` / `WorkoutDetailResponse` to local names. This is a pure
  refactor touching many tests, so it waits until after the rebase.
- An export button. Not requested; the iCloud backup covers device loss.
- Retiring `/api/workouts` and the Neon tables is Jonathan's call.
