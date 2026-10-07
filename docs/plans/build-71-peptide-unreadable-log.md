# Build 71: a peptide log the app can't read is never written over

Branch `integ/build-71`, based on `573f87f14` (the launch branch, TestFlight build 69). This applies build 70's workout data-loss fix to peptides. It closes build-70 open items 6 and 7 (`docs/plans/build-70-workouts-local.md`).

## Problem

`PeptideLogStore` could save over a peptide log it had never read:

1. **A locked file read as no file.** `load()` read through `DeviceLogFile.read()`. That treated a file that is there but can't be opened (file protection before first unlock, permissions) as missing, then fell back to the UserDefaults copy, which may be older or absent. The next change saved that copy over the real log.
2. **A failed copy was ignored.** For bytes that can't be read (not JSON, a version-3 save that won't decode, a version-1 save that won't migrate), the store set them aside with `keepUnreadable` and started a new log. It did this even when the copy failed, so the next save replaced the only copy.
3. **Skipped records were dropped.** A version-3 log with records skipped on reading was never copied, so the next save dropped those records for good.

## What changed

- **Reading.** `PeptideLogFile.read()` returns missing / data / failed, built on `DeviceLogFile.readFile()`. The UserDefaults copy is read only when there is no file, the case it exists for: it holds the bytes only while the file couldn't be written. It is never used for a failed read. `DeviceLogFile.read()` had no callers left and is removed.
- **What counts as no file.** `readFile()` now reads a path with no file at it as missing: nothing there, a folder in the file's place, or a plain file where a folder should be. Only a file that is there but can't be read is failed. This keeps the UserDefaults fallback working for a log that couldn't be written (the existing restore test puts a folder at the log's path).
- **Why saving is off.** The old `savingBlocked` Bool became `PeptideLogReadOnly`:
  - `.newerVersion` and `.upgradeNotKept` behave as before: changes are shown but not saved.
  - `.notOpened` and `.unreadableNotKept` refuse every change and leave memory as it was.
- **Refusing.** Every public change checks first:
  - `log` returns nil.
  - `correct` and `void` return the reason.
  - Vials, schedules, the syringe scale, and held-aside keep/delete change nothing.
  - `importArchive` adds nothing.
  - `adoptReconBench` returns false, so the Recon Bench save stays where it is for the next launch.
  - `replaceAll` / `restoreArchiveData` refuse.
  - `persistError` says why in each case.
- **Backup.** See *iCloud backup while a log is read-only* below.
- **Delete Everything.** `deleteAll()` still works and clears the state.
- **Re-reading.** `reloadIfNotOpened()` reads a log that wasn't opened again. It runs before every change and when the app becomes active, through the same `scenePhase == .active` hook as workouts. Once the phone is unlocked, the records appear and a change keeps them all.
- **Unreadable bytes.** If the whole file can't be read and can't be copied aside, the store is `.unreadableNotKept`. The next launch tries again; once the copy is made a new log starts, as before.
- **Skipped records.** A version-3 log with skipped records is copied aside first (`peptide_log_v1.unreadable-<stamp>.json`). If that copy fails, the log is shown but `.unreadableNotKept`.
  - Versions 1 and 2 already keep their whole bytes before the upgrade save, and save nothing when that copy fails, so they are unchanged.
  - Like workouts, a version-3 log with skipped records gets a new copy at each launch until a save drops them.
- **UI (minimal).**
  - The Peptides screen already shows `storageNote` and `persistError`.
  - The vial, Recon, schedule and log sheets now show the refusal and stay open instead of closing as if saved.
  - The import sheet shows it instead of "Imported".
  - Peptide settings shows `persistError`.

## iCloud backup while a log is read-only

The backup upload replaces the last iCloud backup. Leaving peptides or workouts out of it (what nil used to do) dropped the copy the earlier backup held.

- **Contract.** `CloudBackupPeptides.backupArchiveData()` and `CloudBackupWorkouts.backupData()` return `CloudBackupPart`: `.include(Data)` or `.blocked(reason:)`. The protocols no longer use nil. The refactor commit changed only the type; the behavior commit changed what happens.
- **Blocked when.** Peptides: any `PeptideLogReadOnly` (`.notOpened`, `.unreadableNotKept`, `.newerVersion`, `.upgradeNotKept`). A newer-version log no longer backs up as an empty archive. Workouts: any read-only state (`.notOpened`, `.unreadableNotKept`, `.newerVersion`). Both stores also block when encoding fails. Both re-read a log that wasn't opened before answering.
- **Backup.** `snapshotValues()` throws `CloudBackupError.backupSkipped(reason)`. `backupNow()` (manual, auto, and turning backup on) uploads nothing, leaves the last-backup time and hash alone, and sets `errorMessage`, e.g. "Peptides couldn't be read on this phone, so iCloud backup was skipped to keep your last backup." The settings screen shows it after Back Up Now, Keep this phone, or turning backup on. Auto backup only sets it, and it tries again next time. `backupNow()` and `restoreNow()` clear the old message first.
- **Restore.** Before, `applyValues` replaced every UserDefaults key, and then the read-only store refused its part. That left the phone half restored: diary and settings from the backup, peptides or workouts from the phone. Now, when the backup carries peptides or workouts and that store is blocked, nothing changes: no UserDefaults key, no photo (`restoreNow` restores photos only after `applyValues` succeeds), no last-backup time. `errorMessage` says e.g. "Peptides couldn't be read on this phone, so nothing was restored and everything on this phone was kept." A backup without that key (older builds) still restores.
- **Still partial.** A restore whose store isn't read-only but whose save fails (no space, a folder at the path) still applies UserDefaults and keeps the phone's peptides or workouts, with the message saying so. That failure can't be known before trying, and it was left as it is.
- **Smoke test.** It logs `FAIL` with the reason when a store is blocked.
- **Not proven here.** `backupNow()`/`restoreNow()` need CloudKit, so the harness tests the decisions they use: `snapshotValues()` and `applyValues()`.

Readable logs behave as before: versions 1, 2 and 3, the newer-version block, held-aside records, and Recon Bench adoption.

## Tests

New suite `PeptideUnreadableLogTests`, added to the CI `-only-testing` list, the log grep and the suite-passed check in `ios-build.yml`. It uses real temp files, `chmod`, and a throwaway UserDefaults suite, with no mocks.

| test | guard that makes it fail when disabled |
|---|---|
| `noFileAtThePathReadsAsMissingAndALockedFileDoesNot` | `readFile()` missing for no file / folder at the path |
| `aLogThatCantBeOpenedRefusesEveryChangeAndIsNeverWrittenOver` (chmod 000: nothing shown, every change refused, bytes untouched, backup nil, restore refused; after unlock + `reloadIfNotOpened` the records appear and a save keeps them) | failed read → `.notOpened`; refusal; backup nil |
| `aChangeAfterTheLogBecomesReadableKeepsEveryEarlierRecord` | re-read before a change |
| `theUserDefaultsCopyIsNotUsedWhileTheFileCantBeOpened` | no UserDefaults fallback on a failed read |
| `withNoFileTheUserDefaultsCopyIsStillRead` | (keeps the fallback for a missing file) |
| `deleteEverythingStillWorksWhileTheLogCantBeOpened` | failed read → `.notOpened` |
| `anUnreadableLogThatCantBeSetAsideIsNeverWrittenOver` (folder 0555) | `keepUnreadable` result honored |
| `skippedRecordsThatCantBeSetAsideAreShownButNeverDropped` | skipped-records copy result honored |
| `skippedRecordsAreSetAsideBeforeASaveDropsThem` | (success path: copy made, changes allowed) |

Backup/restore while read-only (in existing suites `PeptideBackupAndResetTests` and `WorkoutBackupAndResetTests`, already in `ios-build.yml`):

| test | guard that makes it fail when disabled |
|---|---|
| `aReadOnlyPeptideLogSkipsTheWholeBackup` (chmod 000 log and a version-7 log: `.blocked`, `snapshotValues` throws, message text) | `snapshotValues` throws on `.blocked`; newer-version peptides blocked |
| `restoreOverAPeptideLogThatCantBeOpenedChangesNothing` (UserDefaults and file untouched; a backup without peptides still restores; after unlock the restore goes through) | restore pre-check; re-read before answering |
| `aReadOnlyWorkoutLogSkipsTheWholeBackup` (chmod 000 log and a version-2 log) | `snapshotValues` throws on `.blocked`; workouts blocked while read-only |
| `restoreOverANewerWorkoutLogChangesNothing` | restore pre-check |

Each guard was disabled in turn in the Linux harness, and at least one listed test failed each time. With the folder check removed, `PeptideBackupAndResetTests.restoreThatCantBeSavedKeepsThePhonesPeptides` fails too.

## Codex round 1 fixes

- **A folder on the way that can't be opened.** `readFile()` used `fileExists`, which is also false when a parent folder can't be traversed. So a log behind a folder with no permission read as missing. Peptides then used the stale UserDefaults copy or an empty log, and workouts used an empty log, and either could be backed up or saved over the file. Now, after a failed read, only `stat` returning `ENOENT`/`ENOTDIR`, or a folder at the log path, counts as missing. `EACCES`, `EPERM` and every other failure stay `.failed`, which gives `.notOpened`. This covers both stores, which share `DeviceLogFile`.
- **Lists that are there but aren't lists.** `PeptideLogSnapshot` turned a malformed `entries`/`vials`/`schedules`, or a malformed `held_aside` (or a list inside it), into `[]`, with `skipped == 0`. That meant no copy was made, and the next save and backup dropped those bytes. Now each malformed container counts as one record that couldn't be read. That runs the existing copy-aside guard, and the store is read-only if the copy fails. The readable lists are still shown. A list that is absent or `null` still reads as empty. The note says "1 saved peptide record couldn't be read" even though the container may have held more. The workout snapshot already decodes `workouts` with `try`, so a malformed list makes the whole file unreadable (copied aside, read-only if that fails). A test now pins this.
- **The peptide UserDefaults fallback in the backup.** `peptide.log.v1` passed `CloudBackupPolicy.include`, which caused three problems:
  - It was uploaded as a raw key beside the peptides archive, which already carries the same records.
  - A restore removed it whenever the backup lacked it: an older backup with no archive, or any backup made while the file was writable.
  - A restore wrote back the raw copy from the backup.
  On the phone, the store and the backup share `UserDefaults.standard`. So a restore whose peptide save then failed deleted the only copy on disk. `include` now returns false for `PeptideLogStore.defaultsKey` (made `nonisolated` so the policy can read the owner's constant). The key isn't uploaded, restored or removed by the generic loop. The peptide store alone owns it, and an older backup without the archive leaves peptides as they are.
- **Delete sheets.** The delete confirmations for vials and schedules now read `changeRefusal`, show it and stay open, as the save actions do.

| test | guard that makes it fail when disabled |
|---|---|
| `PeptideUnreadableLogTests.aLogBehindAFolderThatCantBeOpenedIsNotMissing` and `WorkoutLogStoreTests.aLogBehindAFolderThatCantBeOpenedIsNotMissing` (parent folder chmod 000; restored in cleanup) | `stat` errno check in `readFile()` (old `fileExists` check fails both) |
| `aListThatIsntAListIsSetAsideBeforeASaveDropsIt`, `aListThatIsntAListAndCantBeSetAsideIsNeverWrittenOver` (object `vials`, string `schedules`, array `held_aside`, object `held_aside.entries`) | malformed-container count |
| `absentListsAreEmptyAndNothingIsSetAside` | (absent, `null` and partial `held_aside` stay fine) |
| `WorkoutLogStoreTests.aWorkoutsListThatIsntAListIsSetAside` | (existing throwing decode; passes before and after) |
| `PeptideBackupAndResetTests.restoreLeavesThePeptideFallbackInTheSharedUserDefaults` (one UserDefaults suite for store and service; restore with a failing file save, and an older backup) | `CloudBackupPolicy.include` exclusion |
| `deletingAShownVialOrScheduleIsRefusedWhileTheLogIsReadOnly` | (store refusal the views read; the SwiftUI change can't run in the Linux harness and is verified only by the CI build) |

The harness runs as uid 1000 (not root), so `chmod` takes effect.

## Codex round 2 fix

- **The editor's keep-open decision had no effective test.** Removing both view fixes left every test passing, because the test pinned only the store's refusal and not what the views act on. The decision now lives in the store. `saveVial`, `deleteVial`, `saveSchedule` and `deleteSchedule` return why the log refused the change (`String?`, nothing changed), or nil when the change was made. This follows `correct` and `void`. The vial and schedule editors only do `if let refusal = store.…(…) { errorText = refusal; return }; dismiss()` for both save and delete, and no longer read `changeRefusal` after the call. The behavior is unchanged: on a refusal, `canChange()` sets `persistError` to `readOnly.refusal`, the same string `changeRefusal` returned.

| test | guard that makes it fail when disabled |
|---|---|
| `PeptideUnreadableLogTests.deletingAShownVialOrScheduleIsRefusedWhileTheLogIsReadOnly` (read-only store: each of the four calls returns the refusal; vials, schedules and file bytes unchanged) | each of `deleteVial`, `deleteSchedule`, `saveVial`, `saveSchedule` hard-wired to return nil on refusal fails it (checked one at a time) |
| `PeptideLogStoreTests.vialsAndSchedulesAreSavedAndFiltered` (writable store: the calls return nil and the vial and schedule are saved, then removed) | (a call that always refuses fails it) |

**What this doesn't cover:** the SwiftUI wiring itself (showing `errorText` and not calling `dismiss()` when the returned value isn't nil) is covered only by the CI build, not by any test. There is no XCUITest for these sheets.

## Not changed / open

- **Extra copies.** A version-3 log with skipped records gets a new copy-aside file at each launch until a save drops those records. Workouts already do this.
- **Other fields that fail to decode.** A malformed `omitted` or `syringe_scale` still reads as 0 or nil, and the next save drops it. These are a count and a setting, not records, so it was left as it is.
- Not built by Xcode. Proof needs a CI run on the pushed SHA.
