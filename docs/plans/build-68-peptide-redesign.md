# Build 68 — Peptides redesign: one person per phone, Today / Week / Vials

Base: `integ/build-68` @ 7f13e35cd (build 67). Binding design: `/workspace/peptide-redesign/BLACK_TEAM_DESIGN.md`
(§4 data sketch, §5 polish), with the overrides below.

## 1. Problem and evidence

Jonathan: *"The peptide section needs to be cleaned up just like we did with the settings. It is far too scattered
and hard to use. It needs to be like tracking a workout but instead of sets and reps it's draw size and timing.
There needs to be a simple weekly view. For reconstitution and vial tracking it needs to be far more intuitive."*

Later instruction (overrides the design doc): remove the person toggle and every hardcoded personal name. Each
install tracks only its own user's entries and vials, with no person field on new records or settings.

Evidence (all file-cited in design §1, build-61 screenshots): the Peptides root stacks totals, due list, daily log
and a "More" menu (Vials, Schedule & adherence, History, Recon Bench); the log sheet has two amount fields for one
draw; a vial's confirmation has no who/when; the History screen stacks a month calendar, totals, a chart and the log;
the Home card mixes four jobs and two people. The design's 5× error (Rev 2) shows mg must never be computed
outside one tested function.

## 2. Decisions (including conflicts resolved)

| # | Decision | Why |
|---|---|---|
| D1 | No person anywhere: `PeptideLogEntry`, `PeptideVial`, `PeptideUserSchedule`, `PeptideLogDraft` lose `person`. The toggle, `PeptidePerson`, `PeptidePersonMemory` and `ReconMath.peopleOrder/peopleNames/roster/onHandDefault` go. | Jonathan's override. |
| D2 | Legacy raw values are read in exactly one place, `PeptideLegacyProfile` (Models/PeptideTrackingModels.swift), with a comment. `"jonathan"`, empty or missing → the user's own. The second legacy value → held aside. | Hard rule: names only in migration decoding. |
| D3 | Held-aside records live in the save file (`held_aside`) and in backups until the user picks **Keep them in my log** or **Delete them** on a card at the top of Peptides ("Records from a second profile were found"). Delete asks once more. The choice empties the set and is saved; nothing to ask afterwards. | "Never silently dropped"; one-time choice. |
| D4 | Archive import never asks for a person. Records an old file tagged with the first profile (or none) join the user's log; records tagged with the second profile, or in a file's `held_aside`, join the same saved held-aside set as the launch migration, and the one-time Keep/Delete card handles them. An id already on the phone (log or held aside) is skipped, so re-importing holds nothing twice. An iCloud restore (which replaces everything, like a load) holds them aside too. | Brief: "old archives with a person field still import into the user's log"; Codex P1: import must not bypass the second-profile choice. |
| D5 | Storage stays the Codable file store (`version: 3`), not SwiftData. v1 and v2 saves upgrade on launch; the untouched bytes are copied aside first (`pre-local-*` for v1, `pre-v3-*` for v2). | Brief; §4 sketch is "records only". |
| D6 | Draw = existing `drawnVolume` + new `PeptideDrawUnit` (`units` / `mL`, raw values unchanged). New entries have no `dose`/`units`; legacy entries keep them (shown on detail only, labelled as typed in an earlier version). | Lossless load; no second amount field. |
| D7 | Snapshot at save on every new entry: `syringeScaleAtSave`, `vialConcentrationAtSave` (mg/mL, Double), `concentrationConfirmedAtSave`, `vialIDAtSave`. Never re-read. Old entries decode with nil/false (no backfill). | §4. |
| D8 | `PeptideMath.derivedMilligrams(draw:unit:scale:concentration:confirmed:)` is the only mg arithmetic. nil unless `confirmed` and a concentration; for a units draw also a scale. An mL draw needs no scale (the mL step is the draw itself). | §4 contract, extended to mL per brief. |
| D9 | Double, not Decimal, with `ReconMath.clean` rounding: every existing model and ReconMath helper is Double; the §4 test values are exact in binary. | Smaller, consistent diff. |
| D10 | Syringe scale is one setting owned by `PeptideLogStore` (saved in the peptide file and the archive, wiped by Delete Everything). Reached at **Peptides → Settings → Syringe scale**. | The Settings hub lives in the god file `ContentView.swift` (only shrinks) and More keeps seven rows on SE; a peptide settings screen is the smallest honest home. |
| D11 | A vial records `concentrationConfirmedAt` (who = this phone's user, shown as "You"). Editing a confirmed vial's amount or diluent clears the confirmation. The editor has no confirm toggle; step 3 of Reconstitute is the only way to confirm. | No person field; confirmation must match the numbers. |
| D12 | Recon Bench folds into Reconstitute: `ReconView.swift` is rewritten in place as the 3-step Reconstitute flow. Its dose calculator and dose calendar go (they computed and planned doses). No file is deleted. Its save is migrated, not wiped (D13). | Design §2; "never suggest/calculate doses"; Rule 0 (no file deletions). |
| D13 | Recon Bench's save holds per-profile cards (vial amount + diluent, plus dose/draw/per-week/on-hand calculator figures), dose plans and taken ticks. At launch, each card whose amount or diluent differs from the catalog's becomes an UNCONFIRMED vial (amount + diluent only; no mixed date, which Recon Bench never had; no dose/plan field); the second profile's are held aside. Untouched catalog cards, plans and ticks are not records and don't move. The untouched bytes are first kept as `peptide_log_v1.recon-bench-pre-v3-<stamp>.json` (removed by Delete Everything); then the original save is removed. A save with nothing to move is left untouched. | Codex P2: user-entered Recon Bench data must stay recoverable. |
| D13 | No mg on Today, Week, Home or their VoiceOver labels. §5's card label "0.5 milligrams by arithmetic" is dropped (it breaks the rule and is the 5× error). | Brief. |
| D14 | Schedule stays an optional row under Week. Its typed amount is no longer shown or edited (still saved, so nothing is lost); adherence %, streak and the rust missed list go from the schedule card. | "No target/planned dose fields"; §1 critique 66. |
| D15 | Personal-build gating is unchanged: the section has none today (More → Peptides is unconditional), and this build adds none. | Brief: don't change exposure. |
| D16 | Bundle and app-group identifiers (`com.jonathanbowe.*`) and the repo URL are signing/identity material and stay. | Rule 0. |

## 3. Screens

- **Peptides** (More → Peptides, Home → Open Peptides): segmented **Today / Week / Vials**, a Settings link, the
  second-profile card when needed, no sync UI, no inner "More".
- **Today**: one card per draw, like a finished set (compound, draw as entered, time, vial); full-width **Log a draw**
  in the scroll content. VoiceOver: "BPC-157, 50 units, 7:30 AM, vial BPC-157."
- **Log a draw** sheet: compound chips (vials + logged + Other), draw field EMPTY, unit chips units / mL (none picked),
  time = now, optional vial, site, notes, optional "This draw only" syringe scale; Review; Save.
- **Week**: per compound, 7 day cells (Mon–Sun) as entered, dash for none; `ViewThatFits` + `isAccessibilitySize`
  fallback to a stacked list; History list (by day) → entry detail; Schedule row.
- **Entry detail**: draw, time, vial, syringe scale at save, then mg steps one per line from the snapshot, or
  "Concentration not confirmed" / "Syringe scale not recorded"; trail in words; Edit / Void.
- **Vials**: Reconstitute a vial (primary), Add another kind of vial (blend), Import; cards with amount + diluent as
  typed, "Confirmed: You · date", remaining + bar only when confirmed, else "Remaining is not shown."; footer with the
  syringe scale.
- **Reconstitute**: Step 1 amounts, Step 2 "This is plain arithmetic on the two numbers you typed. It is not advice."
  + `10 mg ÷ 2 mL = 5 mg/mL`, Step 3 checkbox stamping `concentrationConfirmedAt`; Save vial.
- **Home card**: one summary line ("2 draws today · 1 vial low") + Open Peptides.

## 4. Commit sequence (one concern each)

Refactor stage (no behavior or pixel change; existing tests unchanged):
1. `refactor:` `PeptideRecordSet` groups entries, vials and schedules (snapshot, legacy migration, store apply/save).
2. `refactor:` `PeptideLogFile.keepBeforeUpgrade` takes the copy's label.

Behavior stage:
3. `behavior:` one person per phone; second-profile records held aside until kept or deleted (models, store v3,
   archive, legacy, math, minimal view edits, Recon Bench people removed, tests).
4. `behavior:` draws record the syringe scale and vial concentration at save; mg only on entry detail
   (`derivedMilligrams`, the 9 §4 tests, syringe-scale setting).
5. `behavior:` Reconstitute replaces Recon Bench; vial confirmation records when.
6. `behavior:` Peptides is one screen: Today / Week / Vials (log sheet, week grid, history, entry detail, vials).
7. `behavior:` Home peptide card is one summary line.
8. `ci:` new suites in -only-testing, the diagnostic grep and the passing-suite loop.
9. `test-harness:` Visual QA peptide shots for the redesign [goldens-update].

## 5. Tests (Swift Testing, real files in temp dirs)

- `PeptideDerivedMilligramsTests` (new): the 9 §4 tests verbatim in behavior, plus mL draws and reconstitute edge cases.
- `PeptideSecondProfileTests` (new): first-person migrate, keep, delete, choice persisted/one-time, nothing lost
  before choice (on disk and in the backup), relaunch idempotent, v2 → v3 copy set aside, restore holds aside;
  import of a mixed old archive holds the second profile aside (keep, delete, no re-prompt, re-import idempotent,
  backup/restore round-trip).
- `ReconBenchMigrationTests` (new): typed mixes → unconfirmed vials, catalog cards and plans don't move, second
  profile held aside, copy kept and original removed, plans-only and unreadable saves untouched, repeat run adds
  nothing, Delete Everything removes the copy.
- Updated: `PeptideLogStoreTests`, `PeptideMathTests`, `PeptideArchiveTests` (round-trip of the new fields; old
  archives with a person import their own records into the log and hold the second profile aside), `PeptideLegacyMigrationTests`, `PeptideBackupAndResetTests`,
  `PeptideNoNetworkTests`, `HomeV2Tests`, `ReconMathTests` (rows about people's rosters removed with the rosters).
- Linux harness `/tmp/r68-harness` (not committed) builds the pure models/store/migration/archive and runs the suites.

## 6. Visual QA

Removed: 68 (second person), 20/21/22/41 (Recon Bench screens). Changed: 52, 60–67, 69, 104, 105.
Added (eachSize, `referenceNow`, synthetic data): today, log sheet (empty draw), week, history, entry detail with
mg, entry detail without scale, vials, reconstitute steps 1–3, settings syringe scale, second-profile choice.

## 7. Risks

- No compiler here: views are `swiftc -parse` only. Riskiest spots are listed in the handoff.
- Deleting `person` touches every peptide caller; the test target must compile at each SHA.
- Remaining volume: a legacy units draw with no recorded scale is no longer assumed U-100, so its vial's remaining
  becomes "not shown" until the draw is edited. Honest, but visible.

## 8. As built (integ/build-68, not yet pushed or CI-verified)

Commits, in order: plan; `refactor` PeptideRecordSet; `refactor` pre-upgrade copy label; `behavior` one person per
phone + held-aside second profile; `behavior` draws + save-time snapshot + mg only on detail + syringe scale setting;
`behavior` Reconstitute replaces Recon Bench; `behavior` one screen Today/Week/Vials; `behavior` Home card one line;
`test` names out of ProgramCycleTests comments; `test-harness` VQA [goldens-update]; `ci` suites + names gate;
`refactor` vial-editor note (type-checker risk). Codex fixes: `refactor` PeptideRecordSet.newRecords; `behavior`
import holds the second profile aside (P1); `behavior` Recon Bench mixes move into Vials (P2, D13).

Deviations and choices:
- Vial confirmation stores only `concentrationConfirmedAt`; "who" is always this phone's user and shows as "You" (no person field).
- The syringe-scale setting lives at Peptides → Settings (gear on the Peptides screen), not the global Settings hub (D10).
- The edit sheet changes compound, draw, time, site and notes with a reason; it never changes the vial or the snapshot.
- Archive `format_version` stays 1: new keys are additive (`syringe_scale`, `held_aside`, entry `*_at_save`, vial `concentration_confirmed_at`); build 67 ignores them.
- ReconMath keeps its (now unused) calculator and catalog so the CI-gated self-test still runs (41 rows).
- Legacy units draws (no scale recorded) make that vial's remaining "not shown" instead of assuming U-100.

Save format (`version: 3`): `{version, entries, vials, schedules, omitted?, held_aside?: {entries, vials, schedules}, syringe_scale?}`.
Version 2 reads the same way (records tagged with the second profile are held aside) and is copied to
`peptide_log_v1.pre-v3-<stamp>.json` before the first version-3 save.

Deferred: delete ReconMath's unused calculator/catalog and its self-test (needs Jonathan's OK: it removes a CI gate);
the orphan `peptides.selectedPerson` UserDefaults key (harmless, wiped by Delete Everything); a reviewed CI run on
the pushed SHA and Codex review.

## Data source

The peptide assistant no longer writes to Neon (as of 2026-10-07). Peptides are app-only: every entry and vial is typed or imported on the phone, and nothing reads from or writes to a server.
