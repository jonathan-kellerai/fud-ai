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
  - `delete(id:, now:)`: the record is kept as a tombstone (`deleted_at`, plus `tombstone` with every id and
    content hash it carried, current and replaced). It leaves every list, and a re-import can't bring it
    back, not even by the original hash of a workout corrected before it was deleted.
  - Reads: `workouts` (live records, newest session first), `detail(id:)`, `details`.
  - Import: `importSummary(of:)` (preview) and `importFile(_:)`.
  - Backup: `backupData()` and `restoreBackupData(_:)`. Reset: `deleteAll()`.
- **Read shape.** A record is the bridge's own `{workout, sets}` (`RemoteWorkout` and `RemoteWorkoutSet`)
  plus `revisions` and `deleted_at`. Last performance, next-in-cycle, Home, Progress and History keep their
  math and only change where the rows come from. Renaming the `Remote*` types is deferred (§10).
- **The file: `WorkoutLogFile`.** It is the peptide approach, through the shared `DeviceLogFile`:
  - Location: `Application Support/WorkoutLog/workout_log_v1.json`, `{version: 1, workouts: [...], omitted?}`.
  - Writes are atomic. Unreadable bytes are set aside as `workout_log_v1.unreadable-<stamp>.json` and
    never overwritten. If that copy can't be made (or doesn't read back the same), the log is read-only
    until a later launch makes it: save, correct, delete, import, backup and restore all refuse, and
    Settings › Workouts says why. That covers a wholly unreadable log and a log with skipped records.
  - A file that is there but can't be opened (file protection before first unlock, no permission) is
    not an empty log. `DeviceLogFile.readFile()` tells it apart from a missing file. The store then shows
    nothing and refuses every change, backup and restore, with a note in Settings › Workouts. It reads
    the file again before each change and when the app comes to the foreground.
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

- **UI.** More › Training › **Workouts** (see resolution 10) shows how many workouts are on this phone,
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
- **Open question for Jonathan:** workouts, like peptides, ride in the user's own iCloud backup (the
  `workouts.log.v1` key, when iCloud backup is on). That follows his "same as peptides" instruction, so it
  stays as built. Codex flagged it (P1, `CloudBackupService.swift:90`) because training history then leaves
  the phone for the user's iCloud. Whether workouts and peptides should both stay in the backup is his call.

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
  post. Jonathan asked for workout network calls to go away entirely, so it stays deleted (Rule 0's
  per-instance approval for this deletion is that instruction).
- **Upgrade gap.** Until he imports, History, Progress and last performance are empty on the phone.
  Next-in-cycle keeps its cache.
- **`PeptideLogFile` refactor.** Build 68 changes `keepBeforeUpgrade` to take a `label:`. `DeviceLogFile`
  already takes one, so on rebase `PeptideLogFile.keepBeforeUpgrade(label:)` becomes a one-line delegate.
- **Compile risks** (no Xcode here; CI on a pushed SHA is the only proof):
  - `RemoteWorkout` Codable is MainActor-isolated by default. It is decoded only in `@MainActor` code.
  - `WorkoutDraft.payload` is unchanged. `save` converts the payload to a record.

## Plan review — resolutions (binding)

The fresh-eyes review ran as a subagent, standing in for Codex: 3 P1, 7 P2 and 6 P3 findings.

1. **(P1) `WorkoutSyncService` has more callers.** Besides ContentView:2289 there are ContentView:2306,
   `BridgeSettingsView` 17/82/91 (the "Pending Workouts" row and its last error) and
   `MoreHubInputs.bridgePendingCount`.
   - All go in the phone-only commit, and `MoreHubSubtitles.bridgeStatus` loses `pendingCount`.
   - `MoreHubSubtitlesTests` changes are listed as built.
   - The file deletion needs Jonathan's OK before push. Nothing is pushed in this session.
2. **(P1) Every commit must compile, tests included.** The commit that removes the bridge workout methods
   also reseeds the Visual QA workouts into the log (not the stub bridge) and drops the workout lines of
   `BridgeKeyStorageTests`. It is marked `[goldens-update]`.
3. **(P1) The lint must not fail on code that stays.** It bans `/api/workouts` across all app sources and
   `listWorkouts|getWorkout|postWorkout|updateWorkout|deleteWorkout` everywhere. `URLSession|URLRequest`
   is banned only in pure workout files: the log, records, draft store, `ExerciseHistoryLoader`,
   `ProgressTrainingLoader`, `ProgressV2Training`, History/Edit/Import views. `JLPhysicalTabView` and the
   logger keep `NeonBridgeService` for the active program and CC ladders.
4. **(P2) Next-in-cycle.** `TrainProgressStore.adopt(_ log:)`:
   - Until a file import has added workouts (`imported_at` saved in the log), next-in-cycle uses the
     sessions cached from the last bridge list merged with the log's.
   - After that, it uses the log only.
   - The bridge cache is never overwritten before then, so a workout deleted from the log never lingers
     in it.
   - `replaceHistory(with:)` stays as it is; Visual QA uses it.
   - The logger calls `adopt` after a save. `recordCompleted` existed only for a failed bridge list, and
     it goes.
5. **(P2) Duplicate saves.** `WorkoutDraft.recordID` is a stable id set when the draft starts. Saving the
   same id again replaces that workout instead of adding a second one, and a deleted one stays deleted.
6. **(P2) Writes.** The log has no UserDefaults fallback, and memory changes only after a successful write.
7. **(P2) Unreadable records.** When some records can't be read, the whole file is set aside before the
   next save drops them.
8. **(P2) Two owners?** AGENTS.md says workout logging lives in `StrengthWorkoutStore`. That store is the
   feature-flagged legacy Fud strength diary (`StrengthWorkoutSession` in UserDefaults). Program
   workouts never lived there: they were owned by the bridge, with `WorkoutDraftStore` for the unsaved
   session. `WorkoutLogStore` takes over the bridge's role. Jonathan should confirm the AGENTS.md wording
   (it is not edited here).
9. **(P2) View logic moves first.** The history editor's payload building and note splitting move to the
   model in a `refactor:` commit while the bridge is still the source.
10. **(P2) No new More-hub row.** An eighth row would push About under the tab bar on SE. A pure
    `refactor:` first extracts More › Training's "Program" section from ContentView, and the Workouts row
    is added in the extracted file. The path is More › Training › Workouts › Import from a file.
11. **(P3) Progress.** `ProgressTrainingCard`'s bridge states and wording change. `ProgressTabView` reads
    the log through an optional environment value, only after the fixture guard. The log is built in
    `calorietrackerApp.init`, which `CloudBackupService` needs.
12. **(P3) Import.** It reuses the security-scoped read and is refused while the log is read-only.
    Records sort by `sessionDate.prefix(10)` descending, then `recordedAt` descending.
13. **(P3) The tripwire** exercises store and math functions, not hosted views. Train's active-program
    fetch is out of scope.

## 7b. Commit sequence as revised

1. docs
2. refactor `DeviceLogFile`
3. refactor record types
4. behavior: the log
5. refactor: the history editor's correction moves to the model
6. refactor: More › Training's Program section leaves ContentView
7. behavior: phone-only (with the Visual QA reseed) `[goldens-update]`
8. test: fixture
9. behavior: import
10. behavior: backup and Delete Everything
11. test: tripwire
12. ci
13. test-harness: new shots `[goldens-update]`
14. docs

## 9. Still calls the bridge

See § As built — Still calls the bridge.

## 10. Deferred

- Rename `RemoteWorkout` / `RemoteWorkoutSet` / `WorkoutDetailResponse` to local names. This is a pure
  refactor touching many tests, so it waits until after the rebase.
- An export button. Not requested; the iCloud backup covers device loss.
- Retiring `/api/workouts` and the Neon tables is Jonathan's call.

## As built (integ/build-70, not pushed; no CI run yet)

Commits on `integ/build-70` after 7f13e35cd, in order:
1. plan
2. `refactor` DeviceLogFile
3. `refactor` record types
4. `behavior` on-device log
5. review resolutions
6. `refactor` historyCorrection
7. `refactor` TrainingProgramSettingsSection
8. `behavior` phone-only `[goldens-update]`
9. `test` fixture
10. `behavior` import `[goldens-update]`
11. `behavior` backup + Delete Everything
12. `test` tripwire
13. `ci`
14. `test-harness` VQA 106-109 `[goldens-update]`
15. Three code-review fixes:
    - UniformTypeIdentifiers import (a compile error)
    - a save to a since-deleted id keeps the draft
    - Home shows "Logged" for a set-less workout, and the logger adopts with program days
16. this doc
17. Fixes after CI run 37616995246 and the Codex review:
    - `test` SetRowPolishTests save into the log (the CI test-build error)
    - `refactor` `keepUnreadable` reports whether the copy is safe
    - `behavior` an unreadable log that can't be set aside is read-only (Codex P1)
    - `behavior` Delete keeps a tombstone of every id and content hash (Codex P2)
    - this doc (the iCloud backup is an open question; Codex P1 on `CloudBackupService.swift:90` is not changed)
18. Fixes after Codex review round 3:
    - `refactor` `DeviceLogFile.readFile()` says whether the file is missing, read, or there but unreadable
    - `behavior` a workout log that can't be opened is never written over (Codex P1, `WorkoutLogStore.swift:279`)
    - this doc

**Saved file** (`Application Support/WorkoutLog/workout_log_v1.json`):
- Top level: `{version: 1, workouts: [StoredWorkout], omitted?: int, imported_at?: ISO-8601}`.
- `StoredWorkout`: `{workout: <bridge workout row>, sets: [<bridge set row>], revisions: [{replaced_at, workout, sets}], deleted_at?, tombstone?: {ids, content_hashes}}`.
- Row keys are the bridge's, plus `source_fingerprint` and `logged_at`, which are kept from imports.
- A deleted workout has no sets or revisions; its `tombstone` keeps every id and content hash it carried.

**Import file:** exactly `jl-workouts-export-v1`, as in §3.

**Backup:** the same bytes as the saved file (sorted keys) under `workouts.log.v1`.

**Verified here:**
- **Linux harness** (`/tmp/r70-harness`, not committed; Swift 6.2, the model and store files symlinked from this worktree): 196 tests in 13 suites as of round 3 (194 before it; now including SetRowPolishTests and the `WorkoutSetEntry` files it needs, which the CI test-build error showed were missing), plus `PeptideNoNetworkTests` 5/5 and `WorkoutNoNetworkTests` 3/3, each run alone. That covers the workout log, import, backup/reset, draft store, next-in-cycle, logger logic, Progress training math, and the peptide and Recon suites.
  - Peptide and Recon totals are the same before and after the `DeviceLogFile` refactor: 76/76 on both.
- **Tripwire mutation:** an injected `GET /api/workouts` in `WorkoutLogStore.save` fails `WorkoutNoNetworkTests`.
- **Lint:** the "Workouts stay on device" script passes on this tree and fails on an injected `postWorkout` call and `URLSession` use.
- **Parse check:** every changed Swift file passes `swiftc -parse`.
- **Not verified:** nothing has been built by Xcode, and no simulator or Visual QA run has happened. Proof needs a CI run on the pushed SHA.

**Tests removed** (each gated bridge behavior that was removed on Jonathan's instruction):
- `BridgeKeyStorageTests.everyBridgeClientSendsTheConfiguredSecretStoreKey`: the workout list/detail/post lines, the Progress fetches, their expected requests and their stub cases. The test still covers health, programs, steps and CC.
- `ProgressV2MathTests`: `detailCacheInvalidationForcesRefetch`, `decodesWorkoutListTolerantly`, `decodesWorkoutDetailWithStringNumbersAndNulls`, `bridgeConfigMatchesNeonBridgeRequests`. They are replaced by `trainingSummaryComesFromTheWorkoutLog`.
- `WorkoutDraftStoreTests.editsDuringSaveSurviveSuccessfulSave`: save is synchronous now, so nothing can be in flight. It is replaced by `savingAgainAfterACrashKeepsOneWorkout`.
- `MoreHubSubtitlesTests.bridgePendingWinsOverConfiguration` becomes `bridgeStatusFollowsConfiguration`: the pending count is gone along with `WorkoutSyncService`.
- `TrainProgressStoreTests.aRecordedSaveAdvancesTheCardWithoutABridgeList` becomes `aSavedWorkoutAdvancesTheCard`, with the same assertions, against the log.

### Still calls the bridge

Line numbers are at this doc's commit. Every call goes through `NeonBridgeService` (`Services/NeonBridgeService.swift`) or `CCLadderClient`, to the configured bridge URL (default `https://jl-workout-ingest.vercel.app`).

| endpoint | defined at | called from |
|---|---|---|
| GET `/api/bridge/health` | NeonBridgeService.swift:65 | Views/BridgeSettingsView.swift:114 (Save & Test) |
| GET `/api/programs` | NeonBridgeService.swift:84 | Views/ProgramEditorView.swift:228 (program library) |
| GET `/api/programs/active` | NeonBridgeService.swift:92 | Views/JLPhysicalTabView.swift:244, Views/HomeV2Cards.swift:863 |
| GET `/api/programs/{id}` | NeonBridgeService.swift:100 | Views/ProgramEditorView.swift:537 |
| POST `/api/programs` | NeonBridgeService.swift:113 | Views/ProgramEditorView.swift:578 |
| PATCH `/api/programs/{id}` | NeonBridgeService.swift:135 | Views/ProgramEditorView.swift:582 |
| POST `/api/programs/{id}/revise` | NeonBridgeService.swift:155 | Views/ProgramEditorView.swift:601 |
| POST `/api/programs/{id}/activate` | NeonBridgeService.swift:172 | Views/ProgramEditorView.swift:586 |
| DELETE `/api/programs/{id}` | NeonBridgeService.swift:179 | Views/ProgramEditorView.swift:243, :621 |
| POST `/api/steps` | NeonBridgeService.swift:188 | Services/StepsTrackingService.swift:187, :199 (foreground, HealthKit observer, BGAppRefresh) |
| GET `/api/steps` | NeonBridgeService.swift:200 | no caller |
| GET `/api/cc/ladders` | Services/CCLadderClient.swift:14 | Views/CCLaddersView.swift:176, Views/ProgramV2WorkoutLogView.swift:536 (ladder hints, best effort) |
| POST `/api/cc/events` | Services/CCLadderClient.swift:27 | Views/CCLaddersView.swift:192 |

Peptides make no bridge calls (build 67, lint-gated). Nutrition has no bridge endpoint.

**Other network clients (not the bridge)**, for completeness:

| call site | where it goes |
|---|---|
| GeminiService.swift:1145, ChatService.swift:859 | the user's AI providers (AIProvider.swift:66-74) |
| HostedAIService.swift:112 | `fud-ai.app/api/hosted-ai/v1` |
| TypeSafeClient.swift:220 | TypeSafe estimate check (user base URL) |
| SpeechService.swift:461 | speech-to-text providers |
| ModelCatalogService.swift:158 | provider model lists |
| OpenFoodFactsService.swift:93, :369 | world.openfoodfacts.org |
| WeeklyChallengeAPIClient.swift:182 | `fud-ai.app/api/challenge/v1` |
| MealShare.swift:47 | fud-ai.app share links |
| WorkoutFrameStore.swift:215 | `assets.fud-ai.app` exercise frames |
| Gemma4LocalModelManager.swift:675 | huggingface.co model download |
| ContentView.swift:71 | itunes.apple.com version lookup |

### Open items for Jonathan (before push)
1. **Resolved: the import fixture is synthetic.** It has the export's schema and shape (11 workouts, 87 sets) with made-up ids, hashes, loads, notes and times. No real training data is in any commit on this branch.
2. **Resolved: `Services/WorkoutSyncService.swift` stays deleted.** Jonathan asked for workout network calls to go away entirely; this file's only job was posting workouts to the bridge.
3. **Resolved in build 71: the AGENTS.md wording.** The invariant now names `WorkoutLogStore` and `WorkoutDraftStore` for program workouts and calls `StrengthWorkoutStore` the legacy Fud diary. It also says `WorkoutSyncService.swift` stays deleted.
4. **The new CI job must be required in branch protection** for the lint to block merges.
5. **Decided: workouts and peptides stay in the iCloud backup.** Jonathan chose to keep both in his own iCloud backup (§4). No code change.
6. **Fixed in build 71: peptides had the same unreadable-copy gap.** `PeptideLogStore.load` ignored whether `keepUnreadable` succeeded. Now a failed copy makes the log read-only, as for workouts. See `docs/plans/build-71-peptide-unreadable-log.md`.
7. **Fixed in build 71: peptides also read a locked file as an empty log.** Peptides now use `readFile()` and stay read-only until the file opens. They no longer fall back to UserDefaults for a file that is there but can't be opened. See `docs/plans/build-71-peptide-unreadable-log.md`.
