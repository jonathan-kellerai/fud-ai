# Build 62: set entry continuation

Binding decisions and prior work: `/workspace/r62/PLAN.md`, R1–B3 through
58104659d. Requested behavior: `/workspace/set-logging-polish/SPEC.md` P1,
P2 and P4, mockups 03–05. Accessibility source: Apple HIG (SPEC S2, Tier A).
Mockups are the requested design, not independent UX evidence.

First isolate draft entry operations from layout without changing behavior.
Then commit B4 rows, B5 rest ownership, B6 next-set rest entry, B7 reorder
separately. No push. Preserve existing initializer contracts, expectations,
workflows and project files. The draft remains authoritative; reps > 0
means logged. Ghost and next-set edits remain transient until entered.

Acceptance: ghost counts follow dated exercise sets; 44 pt row controls;
typed values and keyboard navigation; exact indexed deletion undo for five
seconds; rest survives sheet dismissal with mute intact; next steps follow
session block order and A1/B1/A2/B2 order with explicit skip state; next
loads use existing within-session progression; reorder persists atomic
blocks and exposes pre-exhaustion/reduction explanations.

Verification: new tests extend the existing CI-listed suites. Linux harness
checks pure policies, persistence, undo, deadline arithmetic and sequencing.
iOS CI must check compilation/isolation, unchanged VisualQA tests, Pro and
SE rows at default/xxLarge/AX2, and pinned rest CTA at SE AX1/AX5. No golden
updates are authorized. CI/reviewer approval remains pending locally.

## Local implementation status — 2026-10-03

B4–B7 are implemented in separate commits: dafc45179, 92e48cb60,
2bc9be006, cd9e9daca. Preparatory refactors and focused follow-ups are
listed in `/workspace/r62/B4-B7-HANDOFF.md`. Final code commit:
69c74176c8c06aaa8f94a2cb0fdd51f626d048db.

The Linux pre-check passes **97 tests in the same two CI-listed suites**.
All new tests are extensions in new files; existing expectations and
VisualQA files remain byte-identical. The timer engine, workflows and
Xcode project also remain byte-identical to 58104659d. The logger is
668 lines (23 more than the starting file); new presentation lives in
Views/ProgramV2 and entry policy lives in Models.

The changed SwiftUI files pass syntax parsing only. An isolated Linux
model build also compiled Observation macros with default MainActor
isolation and Swift language mode 5. Its test executable did not link:
this toolchain's libswiftObservation.so has an unresolved runtime symbol.
That is not an additional passing test run. SwiftUI type checking,
RestTimerService protocol conformance on iOS, keyboard toolbar focus,
sheet lifetime, cue timing and SE/AX screenshots remain CI work.

No push, PR, release, golden regeneration or iOS CI run. There are no CI
run URLs or reviewer sign-off; this work is not certified complete.

## Additive Visual QA coverage — Jonathan's request, 2026-10-03

Jonathan authorizes new build-62 shots and fixtures as a human-owned
`goldens-update` change. Existing tests, shot names and expectations stay
unchanged. This supersedes the earlier statement that no new goldens are
authorized. No push is authorized in this session.

Use the real logger, WorkoutSetEntry, paused RestSession, read-only bridge
stub and TrainingProgramBody.programV2Day(for:on:). A Debug-only initializer
seeds the logger's existing state; the shipping initializer stays unchanged.
The fixture models live V4's added overhead extension, three base curl sets,
notes-based RIR, September 28 start and reduction week 4. Fixed ET dates and
tall canvases are intended to expose complete headers and planned rows at
both text sizes; CI images must confirm their visibility.

| Before | New review image | Acceptance |
| --- | --- | --- |
| No build-62 shot | 70-logger-set-rows | Logged/current/ghost rows, brass target chips, natural PR |
| No build-62 shot | 71-rest-next-set | Paused rest, S2 prefill, reference and +5 reason |
| No build-62 shot | 72-logger-reorder | Reorder mode, both move controls |
| No build-62 shot | 73-pre-exhaustion-note | Day 2 press last, 87.5 × 12/12/9 @ 2/1/0, hold note |
| No build-62 shot | 73b-pre-exhaustion-hold | Explicit Add Set after those three sets; paused rest card holds 87.5 and explains why |
| No build-62 shot | 74-week3-day2 | October 13, overhead extension three sets and week note |
| No build-62 shot | 75-week3-day3 | October 14, curl four sets and week note |
| No build-62 shot | 76-reduction-week-day | October 20 Day 2, reduced rows, 3–4 RIR and note |
| No build-62 shot | 77-rest-bar | Paused shared rest session pinned under logger |

78 Undo is conditional on deterministic presentation. Its live five-second
TimelineView uses wall time; the existing capture waits and variable simulator
latency cannot guarantee the toast stays visible. Skip it without changing
the app's expiry policy. Existing unit tests cover exact indexed Undo.

Check existing coverage before adding unit tests; add only missing cases in
the existing CI-listed suite extensions. Run the requested Linux harness.
iOS compilation and image generation require CI; Jonathan must approve the
new images and their before/after table. No local iOS certification.

### Additive coverage handoff — 70–77

VQA commits: 2ce8d044e (initial fixtures and eight tests), cfa6e5c1d
(natural PR and companion 73b HOLD card). Undo shot 78 remains omitted
because wall-clock expiry can race capture. Each render gets a fresh draft,
entry and driverless paused rest session retained in VisualQAGraveyard.
The pinned-bar fixture represents the returned-to-list state with that
same session; it does not automate dismissal or certify timer lifecycle.

Unit commits: 5deb50985 (calendar selection and reduction rest defaults)
and 41340fd9e (notes-based defaults through one-tap logging/reload, plus
week-3 arm ghost counts through logging/reload). Existing within-session
progression, pre-exhaustion and atomic reorder persistence tests cover
the remaining requested policies.

Requested Linux harness: **101 tests in two suites passed**, including
both unit commits. Swift 6.2 parsing with DEBUG enabled passed for the
logger and VQA suite; extracted fixture checks satisfied all nine
scenario assertion sets. These checks do not type-check SwiftUI, generate
images, or establish an iOS CI pass. The initial harness attempt failed
while its generated directory was being changed; the final complete run
succeeded. Logs: /workspace/r62/harness/build.log and test.log.

A concurrent stale session introduced duplicate 62a–62h aliases in
16d379ada; 11faacab9 reverts only those new aliases and stale notes to
honor Jonathan's current 70–78 numbering. No history was rewritten.
Every VQA byte present at starting SHA 9a5f7f314 is preserved. Changes
against that SHA are additive; no existing tests, shots, assertions,
workflow entries or goldens were changed.

Nothing pushed. No CI URLs or reviewer sign-off exist for this work.
Jonathan's approval of the new images remains pending under the
human-owned goldens-update review. Current handoff:
/workspace/r62/VQA-70-78-HANDOFF.md.

## Reviewer-finding fixes — 2026-10-03

Source: `/workspace/r62/review-last.md`. The supplied CI failure report says
build and unit tests passed on 9a5f7f314; it contains no compile failures
and no run URL. Jonathan explicitly assigned Codex the coder role, supplied
writable Git metadata, prohibited pushing, and required one concern per
commit. Those instructions govern this session.

Implemented findings 1–6:

- a430152ba separates field intent from row presentation without changing
  entry behavior; 60d6e6f9f persists positive typed ghost reps immediately,
  retains the editor for multi-digit input, and tests reload/save without ✓.
  The build-62 ghost-edit test now asserts immediate persistence instead
  of the behavior the reviewer identified as incorrect.
- 6b121ee13 moves history-set conversion into the bridge model without
  changing its behavior; 9cc1bf867 preserves optional RIR, original set
  order, exercise_position and planned_position through history edits.
  The round-trip test includes unknown and zero RIR, missing positions,
  and noncontiguous set orders.
- 866a55a8b records explicit field edits in optional draft metadata and
  refreshes untouched unfinished load/RIR from the current decision.
  Tests cover list/rest agreement at +5 and −5, legacy RIR 0 placeholders,
  and manual load, nil RIR and explicit zero RIR surviving refresh/reload.
- 54e72d6c7 rejects swaps when either participating block has logged sets,
  including any member of a superset; canMove and move share the guard.
  Tests preserve recorded positions while allowing unstarted blocks to move.
- 900ae3244 changes reduction Day 3 to 12 minutes steady, including its
  minimum prescription. Tests cover dated selection, display values, draft
  round-trip and conditioning payload; other weeks retain their prescription.
- d02385840 centralizes the three session-opening callers without changing
  behavior; 498fd764c resolves matching drafts to their saved programV2Day.
  Tests resume an October 13 draft on October 20 without rewriting week
  counts, RIR targets, load policy, session date or recorded sets, and cover
  new sessions plus different-day handoffs.
- 9635ad85b fixes the new regression fixture's attempted assignment to
  immutable exercise notes, found by the first Linux harness run.

Finding 7 is deliberately skipped under Jonathan's condition. Pre-build-62
SHA 423fc3e5e already contains VisualQASnapshotTests.test49SupersetPair
using bundledV2().days[3], test04WorkoutLogging using a bundled lifting day,
and bundled program responses in VisualQAFixtures.buildResponses().
Changing fallback counts or reductionWeek would affect existing VQA renders.
Neither the fallback nor those tests were changed.

Verification: `/workspace/r62/harness/build.sh` passed **110 tests in two
CI-listed suites** on implementation SHA 9635ad85b. Logs are
`/workspace/r62/harness/build.log` and `/workspace/r62/harness/test.log`.
The harness strips Observation and substitutes Linux service stubs; it
does not type-check SwiftUI or establish an iOS build. Swift 6.2 syntax
parsing with DEBUG enabled passed for all five changed views. Diff checks
found no whitespace errors and no changes to workflows, existing VQA
tests, or either original CI-listed test file. New cases extend existing
suites in build-62 test files; no pre-build-62 tests were modified.

No push, CI run on the fixed SHA, or reviewer sign-off. iOS compilation,
Visual QA artifacts and final review remain external gates. This handoff
records local implementation and verification, not certification of completion.
