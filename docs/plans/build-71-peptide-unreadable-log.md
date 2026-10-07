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
- **Backup.** `backupArchiveData()` is nil while changes are refused, so an empty archive is never backed up.
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

Each guard was disabled in turn in the Linux harness, and at least one listed test failed each time. With the folder check removed, `PeptideBackupAndResetTests.restoreThatCantBeSavedKeepsThePhonesPeptides` fails too.

## Not changed / open

- **The iCloud backup still loses its peptides while the log is read-only.** When `backupArchiveData()` (or the workouts' `backupData()`) is nil, `CloudBackupService` leaves the key out of the backup it uploads. That backup replaces the earlier one, so the earlier peptides (or workouts) in iCloud are dropped until a later backup. No empty archive is ever restored over the phone. Keeping the earlier value, or skipping the backup, would be a `CloudBackupService` change, and it isn't made here.
- **A newer-version peptide log still backs up as an empty archive.** `.newerVersion` keeps its old behavior: changes are shown, not saved, and they are backed up. That backup holds only what this app shows.
- Not built by Xcode. Proof needs a CI run on the pushed SHA.
