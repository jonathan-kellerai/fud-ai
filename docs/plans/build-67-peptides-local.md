# Build 67 — Peptides fully self-contained (no bridge)

Audited at `integ/build-66` @ ad2a98237 (read-only). Line numbers are from that SHA; re-grep before editing because build-66 is still landing.

## 1. Problem, evidence, audit

Jonathan, 16:23: *"we also need to ensure peptide support is fully self contained. There's no need for a bridge."*

**Evidence**
- From STATUS.md, Neon `peptide_administrations` and `peptide_schedules` have 0 rows each.
- `peptide_inventory` has 10 rows (INV-PROD-*-001, USER_QNA, written by the peptide assistant). The app holds them only as a memory mirror, so the phone needs nothing from the bridge at runtime.
- Every peptide screen calls the bridge today:
  - Four screens run `.task { refreshIfStale() }`.
  - The Home card fetches `/today`, `/schedules` and `/inventory` itself.
  - The app root flushes on every foreground.
- With no bridge key, or in airplane mode, he gets "Add the bridge key…" banners and a "waiting for bridge" queue. Logs save, but stay *pending* forever.
- Peptide data is in **neither** the iCloud backup nor Delete Everything.
  - `CloudBackupService` snapshots only `UserDefaults.standard`, and `PeptideLogStore.persist()` deletes the defaults copy once the file is written (PeptideLogStore.swift:1315-1320).
  - Delete Everything leaves the app-group file, so the data comes back on the next launch.
- The repo is public, so the 10 records must never be bundled.

**Audit.** B = bridge dependency (y/n). Actions: K keep, R rewrite, D delete.

| file:line | what | B | act |
|---|---|---|---|
| Stores/PeptideLogStore.swift:13-25 | `PeptideBridgeClient` protocol | y | D |
| PeptideLogStore.swift:27-63 | `NeonPeptideBridgeClient` → NeonBridgeService | y | D |
| PeptideLogStore.swift:65-71 | `PeptideLogPersistence` (.appGroup/.inMemory/.file) | n | K |
| PeptideLogStore.swift:81-95 | read-only, conflict, cancel and planned-elsewhere messages | y | D |
| PeptideLogStore.swift:97-121 | rows cache, pendingOps, meta, inventory, lastSync, sync error, historyUnavailable, isRefreshing/isFlushing, skippedRowCount, historyComplete, inFlightOpID, flushTask | y | D. Keep vials, schedules, entries and persistError |
| PeptideLogStore.swift:146-161 | pendingCount, failedCount, syncWarning, isCreateUncertain | y | D |
| PeptideLogStore.swift:163-258 | entry, dayEntries, personVials, remaining, lowStock, loggedCompounds, hasLocalActivity | n | K. Drop plannedEntries (181), inventoryItem (247) and historyBlocksRemaining (215) |
| PeptideLogStore.swift:265-295 | `log(draft)` enqueues a CreatePayload | y | R: append a local entry |
| PeptideLogStore.swift:300-334 | logPlanned, failureMessage, isQueued | y | D |
| PeptideLogStore.swift:339-448 | correct and void (queue or bridge row), updateLocalDetails | y | R: `update(...)` and `remove(id)` |
| PeptideLogStore.swift:450-480 | retry, discard | y | D |
| PeptideLogStore.swift:484-522 | vial and schedule CRUD (device only) | n | K |
| PeptideLogStore.swift:524-993 | refresh, flush, send, classify, refreshRows, upsert, reconcile, scheduleFlush | y | D |
| PeptideLogStore.swift:1000-1165 | merge of rows + ops + meta | y | Move to migration (R2) |
| PeptideLogStore.swift:1169-1236 | Snapshot v1 | y | R: v2 snapshot. v1 is decoded only by the migration |
| PeptideLogStore.swift:1238-1322 | file URL, load, keepUnreadable, persist | n | K, extracted (R1) |
| PeptideLogStore.swift:1327-1416 | `PeptideAdministration: Encodable` and its memberwise init | y | D. Decoding moves to the migration |
| Models/PeptideRecords.swift:11-120, 366-400 | TodayResponse, Inventory*, Schedule*, Warning, AdministrationList | y | D |
| PeptideRecords.swift:122-363 | PeptideAdministration, Decode, Correction, JSONDisplay, Lossy | y/n | K: needed to read v1 files, and the corrections trail is kept |
| Models/PeptideTrackingModels.swift:12-27 | PeptidePerson | n | K |
| PeptideTrackingModels.swift:64 | `PeptideVial.bridgeInventoryID` | y | D. The old key is ignored on decode |
| PeptideTrackingModels.swift:186-358 | CreatePayload.body(), CorrectionChanges.dictionary(), PendingKind/Op | y | Move to migration and decode only. Keep CorrectionChanges as the edit value |
| PeptideTrackingModels.swift:360-378 | PeptideSyncState | y | D |
| PeptideTrackingModels.swift:381-488 | PeptideLogEntry (bridge fields) | y | R: Codable local record |
| Models/PeptideMath.swift:66-80 | `compoundOptions(inventoryCompounds:)` | y | R: drop the parameter |
| PeptideMath.swift:242-253 | incompleteHistory | y | D |
| PeptideMath.swift:696-710 | plannedAdherence | y | D |
| Services/NeonBridgeService.swift:39 | `isAlreadyCompleted` (used only by ReconStore) | y | D |
| NeonBridgeService.swift:245-441 | every `/api/peptides/*` call, plus createCompleted, correct, void and the write validator | y | D |
| NeonBridgeService.swift:533-540 | `PeptideBridgeWriteError` | y | D |
| calorietrackerApp.swift:192-193 | foreground `flush()` | y | D |
| calorietrackerApp.swift:124-136 | reload on `.cloudBackupDidRestore` | n | R: add `peptideLogStore.reloadFromDisk()` |
| calorietrackerApp.swift:231-234 | onboarding→false (only Delete Everything does this) | n | R: also wipe peptides and the Recon file |
| Views/HomeV2Cards.swift:111-119, 297-315, 863-1001, 1114-1131, 1182-1410 | bridge state, /today visibility, bridge card, `reloadPeptides`, PeptideActionSheet | y | D. The card becomes HomePeptideSummary plus "Log a dose" |
| Models/HomeV2Logic.swift:98-101, 239-264 | PeptideVolumeState, peptideCardVisible, volumeState | y | D |
| Views/Peptides/HomePeptideSummary.swift:5-44 | shownKeys against /today | y | R: show all of today's entries |
| PeptidesView.swift:61-71, 89-104, 170-205, 228-290, 458-460 | refresh and flush, failed dialog, queue/sync banners, planned rows | y | D. Keep the person save at 72-74 |
| PeptideScheduleView.swift:47, 55, 187-232, 354 | planned-adherence card, refresh, inventory compounds | y | D/R |
| PeptideVialsView.swift:42, 50, 226-330, 573-590, 649 | assistant inventory, badges, inventory link | y | D. Add an Import button |
| PeptideLogSheet.swift:104, 421 | inventory compounds, `.pending` preview | y | R |
| PeptideEntryDetailView.swift:48, 65, 75-80, 104-130, 155-157 | refresh, "Recorded via", badges, agent/failed banners, sync chip | y | D. Keep the trail at 32/178 |
| PeptideEntryDetailView.swift:220-505 | edit with reason, three-way void | y | R: `update` with no reason; one Remove with a confirm |
| PeptideComponents.swift:186-206, 238-256, 415-440 | DueStatus.planned, SyncChip, failed chip | y | D |
| PeptideComponents.swift:57-92, 486-495 | person toggle and memory (UserDefaults) | n | K |
| Views/BridgeSettingsView.swift:105-112 | "Sync Peptide Doses" toggle | y | D |
| Stores/ReconStore.swift:10-13, 20, 94-132, 176 | bridgeSyncEnabled, syncNotice, postTaken | y | D |
| ReconMath.swift:1056-1058; ReconView.swift:316-318, 346-357 | shouldSyncTakenToBridge; notice and "Dose sync" row | y | D |
| Services/CloudBackupService.swift:39-88 | UserDefaults only | n | R (§4) |
| DiaryExporter/Importer, Export/ImportDiaryView | food only | n | K |
| ContentView.swift:4063-4092 | Delete Everything, missing the peptide and Recon files | n | K. Wipe happens in the app root, so the god file isn't touched |
| Tests: PeptideLogStoreTests.swift:21-925 | queue tests and FakePeptideBridge | y | Mostly D, rewritten |
| Tests: BridgeKeyStorageTests.swift:135, 151, 307 | `/api/peptides/today` | y | D |
| Tests: HomeV2Tests.swift:59-75 | peptideCardVisible, volumeState | y | D, plus a new local test |
| Tests: ReconMathTests.swift:38-42; SettingsKeyPreservationTests.swift:29 | sync flag | y | D |
| Tests: VisualQAPeptideFixtures.swift:145-300; VisualQASnapshotTests.swift:1498, 1566, 1750-1770, 1940-1943, 1966-1969 | bridge stubs | y | R: seed locally |

## 2. Target design
- **One owner.** `PeptideLogStore` (`@Observable @MainActor`) has no client, no URLSession and no NeonBridgeService.
  - `init(persistence:)` only; the `client:` and `autoFlush:` parameters go.
- **Storage.** Same app-group file `PeptideLog/peptide_log_v1.json`, now at `version: 2`: `{entries, vials, schedules}`.
  - Keep the lossy decode, keepUnreadable and the defaults fallback.
  - No SwiftData.
- **Record.** `PeptideLogEntry` becomes the Codable local record:
  - Fields: `id, person, compound, dose?, units?, date?, datetimeRaw, route?, notes?, vialID?, drawnVolume?, drawnUnit?, voided, voidReason?, corrections, createdAt`.
  - `civilDate` is derived (explicit CodingKeys plus `init(from:)`).
- **Store API:**
  - `log(draft)`
  - `update(id, changes, vialID:, drawnVolume:, drawnUnit:)`, in place with no reason
  - `remove(id)`
  - `importArchive(_:)` and `exportArchive()`
  - `deleteAll()` and `reloadFromDisk()`
  - Remaining, lowStock, due items and vial/schedule CRUD are unchanged. Remaining is always calculable.
- **Views** only display. Nothing is gated on bridge settings. Home visibility is `hasLocalActivity(today:)`.
- **Migration on first launch** (`Stores/PeptideLegacyLog.swift`, `@MainActor`), in order:
  1. Copy the v1 file to `peptide_log_v1.pre-local-<stamp>.json`.
  2. Run the moved, unchanged v1 merge. This gives exactly what he sees today: cached rows with queued or failed corrections and voids applied, queued creates as entries, cancelled creates as voided, and the meta folded in.
  3. Drop PLANNED rows. They are the assistant's plans, not his records.
  4. Use the row id or crid as `id`.
  5. Keep the vials and schedules, then write v2.
- **No dose suggestions.** Nothing creates doses or schedules from inventory.

## 3. One-time import of the 10 Neon rows
- **One format for import and export.** `Models/PeptideArchive.swift`: `{format:"jl-peptides", format_version:1, exported_at, vials:[PeptideVial], schedules:[...], entries:[...]}`. A vial's `person` may be null.
- **UI.** Peptides › Vials gets an Import button: `.fileImporter([.json])`, the ImportDiaryView pattern, with a 1 MB cap.
  - A preview names the counts and the person before anything is applied.
  - It adds by id only when absent, so a re-import does nothing.
- **The file.** The orchestrator builds it from Neon and hands it to Jonathan outside the repo.
- **Mapping:**
  - `id` → `id`. `compound` → `compound`.
  - Neon has no owner column, so a null `person` becomes the person currently selected.
  - A strict yyyy-MM-dd `date_prepared` → `mixedOn`.
  - Into `notes`, verbatim as labeled lines with nulls skipped: `labeled_amount`, `concentration`, `diluent`, `diluent_volume`, `lot`, `source`, `date_received`, `expiration_or_bud`, `storage`, `qty_remaining`, `status`, `verification_status`, `identity_basis`, `concentration_basis`, `notes`, plus `uncertainties`/`warnings`/`badges` as JSON text.
  - No parsing of numbers: `components: []`, `diluentML: nil`, `concentrationConfirmed: false`.
  - Status is `finished` only for an explicit depleted value; otherwise `active`, with the raw value kept in notes.

## 4. Backup, export, Delete All Data
- **iCloud backup** (missing today):
  - `snapshotValues()` adds `peptides.archive.v1` = the file's data.
  - `applyValues()` writes that key back to the file, and `include` lets it through.
  - The restore handler calls `reloadFromDisk()`.
- **Local export** (missing today): a History "Export" button writes `PeptideArchive` and opens the share sheet.
- **Delete Everything** (missing today):
  - At calorietrackerApp.swift:231-234, call `peptideLogStore.deleteAll()`. It removes the file, the v1 copies, the defaults key and the in-memory state.
  - Also call `ReconBenchStore.deleteSavedData()`.
  - The person key and the Recon defaults are already wiped by `removePersistentDomain`.

## 5. Tests
All tests use real inputs and a temporary `.file(URL)`.

- **`PeptideLogStoreTests`** (rewrite; already in the CI list):
  - Covers log, invalid draft, edit, remove, vials with remaining, schedules and due items, person filter, and an unreadable file kept aside.
  - **Relaunch**: a new store on the same file sees the data.
  - Bridge-only tests at lines 21-776 are deleted (each listed in the PR) along with FakePeptideBridge.
- **`PeptideNoNetworkTests`** (new, `.serialized`):
  - A `PeptideNetworkTripwire: URLProtocol`, registered globally, logs every request and fails it.
  - Written justification for the stub: app code uses `URLSession.shared`, so a tripwire is the only way to prove "no call" without production hooks.
  - Each flow must end with an empty log: log, edit, remove, vial CRUD, schedule CRUD, Home load (`HomePeptideSummary` plus `hasLocalActivity`), person toggle, import/export, migration.
  - Requests to other suites' stub hosts are ignored, because suites run in parallel in one process.
- **`PeptideLegacyMigrationTests`** (new), using v1 JSON literals:
  - A synced app row and an agent COMPLETED row both become plain local entries.
  - PLANNED is dropped; a voided row is kept as voided.
  - A queued create with meta becomes an entry. A queued correction and a failed void are applied.
  - A cancelled uncertain create becomes voided. A create whose row exists stays a single entry.
  - The pre-local copy exists, a second launch is a no-op, and a bad element is skipped.
- **`PeptideArchiveTests`** (new):
  - Round-trip, idempotent import, null person → selected person.
  - Notes keep the text verbatim; numbers stay nil and unconfirmed.
  - Wrong format, a newer version and a file over 1 MB are refused.
- **`PeptideBackupAndResetTests`** (new): backup snapshot and restore round-trip; `deleteAll` leaves an empty fresh store; the Recon wipe.
- **`HomeV2Tests`**: lines 59-75 are replaced by "visible iff there is local activity".
- **CI changes:**
  - Add the 4 new suites to `ios-build.yml` after line 104 and to the grep at line 125. Nothing is removed from the list.
  - New lint step: `! grep -nE 'URLSession|URLRequest|NeonBridgeService|/api/peptides'` over `Stores/Peptide*`, `Models/Peptide*` and `Views/Peptides/`.

## 6. Commit sequence (`feat/peptides-local-only` → PR to `cursor/jl-physical-neon-bridge-366e`)
**CI run 1:**
1. `refactor: extract PeptideLogFile` (lines 1238-1322). Pure; existing tests unchanged.
2. `refactor: move the bridge merge into PeptideLegacyLog` (lines 1000-1165 plus the v1 decode). Pure.
3. `behavior: peptides persist on device only`: store rewrite and migration; delete the bridge code, NeonBridgeService 39/245-441/533-540 and the app-root flush; update views and tests. Grep for callers before deleting.
4. `behavior: Home card and Recon Bench stop using the bridge`: Home card, Recon and the toggle, their tests, the CI list and the lint step.

**CI run 2:**
5. `behavior: import and export the peptide archive`.
6. `behavior: peptides in iCloud backup and Delete Everything`.
7. `test-harness: Visual QA seeds peptides locally`. Labeled `goldens-update`, with a before/after table.
8. `ci:` anything still missing, plus the handoff note.

**Expected screenshot changes.** Every shot must still render on Pro and SE.
- **52:** local card seeded with "Due today" and Low stock.
- **60/68:** no sync banners, planned rows or sync chips.
- **61/62:** no assistant chips and no pending chip.
- **63:** no "Recorded via", badges or chip; the trail stays.
- **64:** the assistant section is gone; Import is added.
- **65:** the inventory link is gone.
- **66:** the adherence card is gone.
- **67:** no chips; Export is added.
- **69:** local lines only.
- **36:** the "Sync Peptide Doses" section is gone.
- **22:** the "Dose sync" row is gone.
- **20/21:** unchanged.

## 7. What the peptide assistant ("Peptide Mad Scientist") loses
- **Its writes stop reaching the phone.** Inventory, schedules, PLANNED doses and administrations written to `/api/peptides/*` no longer appear. That ends the inventory mirror, badges and warnings, "Mark taken" and the adherence card.
- **The phone's records stop reaching Neon.** Logs, edits, removals and Recon "taken" marks stay on the phone.
- **The only remaining hand-off is manual:** the archive file from §3/§4.
- **Unchanged:** the routes, the Neon tables and the assistant itself. The 10 inventory rows stay in Neon.

## 8. Risks, compile-risk spots, deferred
**Compile risks** (Swift 6.2, Swift 5 mode, default MainActor isolation):
- `PeptideLogEntry` must stay `nonisolated`, with custom Codable for `civilDate`.
- PeptideRecords types are not `nonisolated`, so their Decodable conformances are MainActor-isolated. Decode them only inside the `@MainActor` migration.
- Deleting the `PeptideAdministration` memberwise init breaks the fixtures. Build the v1 test data as JSON literals.
- The tripwire must mirror BridgeKeyStorageTests.swift:278: `nonisolated … @unchecked Sendable`, with a comment and a lock.
- Removing `PeptideSyncState`, `rowID` and `isAgentRow` breaks many call sites. Fix compile errors first, using the §1 table as the checklist.

**Product decision for Jonathan:** with KISS, edit needs no reason and Remove deletes. The fallback is to keep void-with-reason.

**Other risks:**
- The migration is reversible because the v1 copy is kept.
- The deleted tests gated behavior that is itself being deleted on Jonathan's instruction. They are not being removed to weaken a gate, and the PR must list each one for Codex.
- The tripwire's host allowlist is a weak point; the lint step is the backstop.

**Deferred:**
- ReconMath `onHandDefault`/roster may hold personal data in the public repo. Audit separately.
- Whether to retire the Neon peptide routes and tables is Jonathan's call.
- Folding the archive into the diary export UI.

## Codex plan review — resolutions (binding; full review /workspace/r67/codex-plan.log)
0. Branch is `integ/build-67` off the shipped build-66 commit; PR to `cursor/jl-physical-neon-bridge-366e`.
1. (P1 migration safety) Migration: read v1 bytes (file, else defaults); validate version; FIRST write the untouched copy `peptide_log_v1.pre-local-<stamp>.json` and verify it exists, else abort migration (keep running on the in-memory merge, do not write v2, surface persistError); write v2 atomically (`.atomic`); count skipped/unreadable elements and keep that count visible (persistError-style note on the History screen, plain text). Unsupported/newer version: leave file untouched and show the note. Tests: defaults-only v1, malformed element skipped+counted, unsupported version untouched, copy failure aborts without writing v2, second launch is a no-op.
2. (P1) Keep `sourceVial` on the local record (provenance) plus every retained v1 field, metadata link (vialID/drawn volume) and the corrections trail. Test each.
3. (P1) Every test/fixture caller (VisualQAPeptideClient in VisualQAPeptideFixtures.swift, PeptideMathTests.swift ~106/126/244/422, BridgeKeyStorageTests, HomeV2Tests, ReconMathTests, SettingsKeyPreservationTests) is updated in the SAME behavior commit that removes the API; the test target must compile at every pushed SHA.
4. (P1 tripwire) CI's unit job runs suites serially in one process (-parallel-testing-enabled NO). `PeptideNoNetworkTests`: register a tripwire URLProtocol for the test's duration with NO host exemptions; first assert a control request through URLSession.shared IS intercepted; then run real flows by awaiting store/model calls (log, edit, void, vial/schedule CRUD, archive import/export, migration, Recon taken mark, Home summary model inputs, person toggle) with NO bridge key configured; finally assert zero requests. Plus a relaunch test. Unregister in all paths (defer).
5. (P2) Add the new suites to -only-testing, the diagnostic grep AND the passing-suite loop in ios-build.yml (~148–161), exact declared type names.
6. (P2) Refactor commits pushed + CI'd on their own SHA first (stage 1), behavior after (stage 2), one PR — same as build 66 (time budget). CUT the edit/remove semantics change: keep today's UX semantics locally — edit requires a reason and appends to the corrections trail; Remove voids with a reason (entry kept as voided, shown struck/hidden as today). Keep the Recon Bench file in Delete Everything (it is peptide data).
7. (P2 backup) One serialization boundary: `PeptideArchive` (same JSON as export/import) is what the iCloud backup stores under `peptides.archive.v1`; restore decodes+validates before replacing, failure leaves current data and reports; older backups without the key leave peptides untouched. Backup tests inject temporary persistence (never the app-group file).
8. (P2 VQA) Peptide fixtures use VisualQAFixtures.referenceNow (fixed civil date) everywhere, stable ids, in-memory storage; harness updates land in the same push as the behavior.
9. (P2 privacy) Synthetic fixtures only (no real compounds-from-his-inventory with his notes); Jonathan's import file is generated by the orchestrator outside the repo and never committed/logged/screenshotted.
10. (P3) CI lint (bash, recursive, fails on scan error) over all shipping `ios/calorietracker` sources: no `/api/peptides`, no `peptide` symbol in NeonBridgeService, no `PeptideBridge`; and over Stores/Peptide*, Models/Peptide*, Views/Peptides/: no URLSession/URLRequest/NeonBridgeService.
Edit semantics note: void/correct were bridge audit rules; keeping them locally avoids an unrequested UX change.

## Implementation notes (build 67, as built)
Commits on `integ/build-67`, in order: plan; `refactor` PeptideLogFile; `refactor` PeptideLegacyLog;
`behavior` peptides live on this phone only (store, migration, screens, Home card); `behavior` Recon Bench
and the bridge client stop touching peptides (+ tripwire, CI lint job); `refactor` FileShareSheet;
`behavior` import/export archive; `behavior` iCloud backup + Delete Everything; `test-harness` VQA at
`referenceNow` + shots 104/105.

Deviations from §2–§6, all toward smaller diffs or the Codex resolutions:
- Edit/void semantics kept (resolution 6): `correct(entry, reason:, changes:)` appends one trail row per
  changed field (`by: "app"`); `void(entry, reason:)` keeps the entry, struck through, with a `voided`
  trail row. No `remove(id)`.
- No `reloadFromDisk()`: the backup restores through the store (`CloudBackupPeptides` contract), so the
  restore handler needs no reload.
- The Home card moved in the same commit as the store (its action sheet called removed store APIs);
  commit 4 is Recon + deleting the bridge client.
- `HomeView` gained an optional `referenceDate` (nil in the app) so Home peptide shots use `referenceNow`.
- An extra pure refactor (`FileShareSheet`) precedes export, per "move it to the owner on second use".

### Peptide archive (`format: "jl-peptides"`, `format_version: 1`)
UTF-8 JSON object, at most 1,000,000 bytes. Unknown keys are ignored. Import adds a record only when its
`id` is not already on the phone; there a record that fails to read is skipped and counted, never fatal.
An iCloud restore replaces everything, so it is strict: all three lists must be arrays and every record
must read, and the replacement is saved before it is shown. Otherwise the phone's peptides are kept and
the backup screen says why.

The on-device save (`version: 2`) also carries `omitted` (int, written only when > 0, absent reads as
0): records that couldn't be read and were left out of an earlier save (the version-1 upgrade, or a
damaged save). It keeps the "couldn't be read" note on History across relaunches until Delete Everything.

The version-1 upgrade adds a trail row for each queued or refused correction and void it applies,
using the queued op's reason and `createdAt`.

| key | type | notes |
|---|---|---|
| `format` | string | must be `"jl-peptides"` |
| `format_version` | int | must be 1 (2+ is refused as "newer version") |
| `exported_at` | string? | ISO-8601; display only |
| `vials` | array | see below |
| `schedules` | array | see below |
| `entries` | array | see below |

Vial: `id` string (required, non-empty), `compound` string (required), `person` string or null
(null/absent/empty → the person picked in the import preview), `is_blend` bool (default false),
`components` array of `{id?: string, name: string, amount?: number, unit: string}` (default []),
`diluent_ml` number?, `mixed_on` string? (kept only if strict `yyyy-MM-dd`), `concentration_confirmed`
bool (default false), `low_stock_threshold_ml` number?, `status` `"active"|"finished"` (anything else →
active), `notes` string (default ""), `created_at` ISO-8601? (default: import time).

Schedule: `id`, `compound` (required), `person`?, `amount`?, `units`?, `frequency`
`{type: "daily"|"weekly"|"weekdays"|"everyN"|"perWeek", days: [int], n?: number}` (required),
`start_date` `yyyy-MM-dd` (required), `end_date`?, `time_of_day` minutes?, `active` (default true),
`notes`, `created_at`?.

Entry: `id`, `compound` (required), `person`? (null → jonathan), `dose`?, `units`?, `datetime`
ISO-8601 with offset, `route`?, `notes`?, `source_vial`?, `vial_id`?, `drawn_volume`?, `drawn_unit`
(`"mL"|"units"`)?, `voided` (default false), `void_reason`?, `corrections`
`[{at, field, old, new, reason, by, derived?}]`, `created_at`?.

For the one-time Neon inventory import (§3): one vial per row, `person: null`, `components: []`,
`diluent_ml: null`, `concentration_confirmed: false`, the labeled facts as `notes` lines, `schedules: []`,
`entries: []`. The file is built outside the repo and never committed, logged or screenshotted.

### Deferred
- `MealShare` has its own share-sheet presenter (different anchor); merging it is a behavior change.
- ReconMath `onHandDefault`/roster may hold personal data in a public repo (audit separately).
- Retiring the Neon peptide routes/tables is Jonathan's call; the assistant's writes no longer reach the phone.
- Folding the archive into the diary export UI.
