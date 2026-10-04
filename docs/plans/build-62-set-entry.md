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
tall canvases expose complete headers and planned rows at both text sizes.

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

### Original 62a–62h naming and local checks

A concurrent process committed the initial additions as 2ce8d044e and
renamed them 70–77, then added the HOLD card in cfa6e5c1d. Preserve those
commits and tests. The original session request's 62a–62h entry points are
added separately using the same fixture/render helper, with an additional
62d-pre-exhaustion-hold image for the explicit HOLD reason. No existing
test or shot is replaced. 62i-undo-toast is omitted for the expiry reason above.

Unit commit 5deb50985 covers actual calendar selection before the dated
week builder and reduction load/RIR defaults through rest-entry logging.
The requested Linux harness completed with 99 tests in two suites after an
initial run aborted when generated build files disappeared. An extracted
fixture executable satisfied all nine fixture assertions and encoded all
seven new bridge response paths. Swift syntax parsing passed; iOS type
checking and rendered images remain pending CI and human approval. This
session did not push. See /workspace/r62/ios3-verification.md for the handoff.
