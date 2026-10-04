# CC ladder step form sheet (build 65)
Condensed from the approved `/workspace/cc-ladder-art/APP_PLAN.md` and `/workspace/cc-ladder-art/FORM_SPEC.md` (squat pilot). Base: `integ/build-65` @ `222b68801` (build 64). Paths are relative to `ios/calorietracker/` unless they start with `ios/`, `docs/` or `.github/`.

## Problem
The Ladders screen (`Views/CCLaddersView.swift`) names each Convict Conditioning step and its graduate-at target, but it never shows what the start and end positions look like. `CCStepRow` can't be tapped, and the workout logger's ladder finisher shows only a text hint. To check form, users have to leave the app.

## Scope
- **Art:** six ladders (PSH SQT PLL LGR BRG HSP), steps 1–10, with a start and an end image each: 120 vector image sets in `Assets.xcassets/CCLadderArt/` (Provides Namespace), named `<SERIES>-<NN>-<start|end>`. This commit adds the squat pilot (20 SVGs). The other 100 land before push.
- **Cues:** bundled `Resources/CCFormCues.json`, keyed `"<SERIES>-<NN>"`, with schema `{"start": [String], "end": [String], "altStart": String, "altEnd": String}`. The SQT entries come from FORM_SPEC. All 60 entries land before push. Cues are presentation copy. Names and targets still come only from the bridge.
- **Domain** (`Models/CCStepForm.swift`, Foundation only):
  - `CCStepArt.name(series:step:phase:)` gives `"CCLadderArt/SQT-03-start"`.
  - `CCFormCues` decodes the cues once from `Bundle.main`, and a lookup returns nil when an entry is missing.
  - `CCFormSelection` holds the series and step.
  - `CCLadderLogic` gains `stepInfo(_:in:)` and `formSelection(exerciseKey:exerciseName:in:)`.
- **View:** `Views/CCStepFormSheet.swift`, with `.presentationDetents([.medium, .large])` and IronTheme styling.
- **Entry points:**
  - On the Ladders screen, every `CCStepRow` becomes a button (same look) with the hint "Shows start and end positions".
  - `CCStepStatsPanel` gets a "Form" button for the current step.
  - In the logger, a "Form" button under the ladder hint opens the series at its current step.
- Out of scope: cues served by the bridge, a full-screen image zoom, and any change to ladder data or bridge calls.

## Refactor first (no behavior change)
1. Move `bookText` from `CCStepStatsPanel` (a view) to `CCLadderLogic.bookText(_:)`, because the sheet needs the same line.
2. Extract the series match inside `CCLadderLogic.loggerHint` into `CCLadderLogic.loggerSeries(...)`, because the logger's Form button needs the same mapping.

Existing tests and goldens must stay identical after both steps.

## Acceptance criteria
- Tapping a step row, or the Form button on the stats panel, opens the sheet for that series and step.
- The sheet shows:
  - the title "Step N · <bridge name>";
  - the graduate-at target from `CCLadderLogic.stepTargetLabel`, with the brass `flag.checkered` icon (`timer` for holds);
  - two or three start cues and two or three end cues;
  - the book line.
- Start and end images sit side by side. At accessibility type sizes, or below 340 pt of width, the sheet shows one image with a Start/End segmented picker. The crossfade is skipped when Reduce Motion is on.
- Previous and next chevrons have 44 pt hit areas, step through 1…10, and are disabled at the ends.
- A missing image asset shows an SF Symbol placeholder, and the cues and target still show. A missing cue entry hides that block and doesn't crash.
- VoiceOver:
  - each image is one element, with the label from `altStart`/`altEnd` and the trait `.isImage`;
  - the identifiers are `ccForm.SQT-03.start` and `ccForm.SQT-03.end`;
  - the picker reads "Start position" / "End position".
- The views contain no business logic. Mapping from logger exercise to series and step lives in `CCLadderLogic` and is tested.

## Tests (`ios/calorietrackerTests/CCLadderTests.swift`, already in the `-only-testing` list)
- `UIImage(named: CCStepArt.name(...))` is non-nil for every series × step 1…10 × start/end. This test fails until all 120 images land. That's intended: it's the "missing art fails CI" gate.
- `CCFormCues` has an entry for every series × step, with non-empty `start`, `end`, `altStart` and `altEnd`. It fails until all 60 entries land.
- Name formatting (zero padding, upper-casing), the cue key, and decoding of the schema, including a missing key.
- `bookText`, `stepInfo` past either end, and `formSelection` for a program exercise name, a step-name key, an unknown exercise and a nil response.

## Screenshots expected (`VisualQASnapshotTests`, new shots 85–94, default + axL, Pro + SE)
SQT-03, PSH-01, PSH-10, PLL-03, LGR-02, LGR-06, BRG-01, BRG-10, HSP-01, HSP-10. Each shot shows the sheet over the Ladders screen and is built from stub `CCSeriesState` data matching `lib/cc.ts` `CC_LADDERS` (no network). The new goldens need the `goldens-update` label and a reviewer-approved table. Existing shots change only where the new controls appear. Each change must be listed in the before/after table:
- 51 and 53 (Ladders): a Form button on each stats panel, and step rows at least 44 pt tall.
- 54 and any 70–77 logger shot that shows a ladder hint: a Form button under the hint.

## Risks
- **App size:** watch the compiled `.car` delta for 120 SVGs. If it exceeds about 1.5 MB, fall back to 64-colour PNGs (APP_PLAN).
- **Compiler and toolchain:** there's no Xcode on the agent box, so CI on the pushed SHA is the only compiler.
