# Build 63: every AI path through one router seam

Branch `integ/build-63` from `cursor/jl-physical-neon-bridge-366e` @ 5fa786358. Status: Codex-reviewed
(`/workspace/r63/codex-plan.log`), implemented with resolutions R1-R9 below; see **Status** at the end. Sources: yeet sheet build-63 section (`JL_PHYSICAL_YEET_SHEET_62_PLUS.md`
L136-149), r61 audit table (`/workspace/r61/ios-b-cc.log` "AI call path audit"), r61 double-fallback note
(`/workspace/r61/ios-fix-cc.log`, last paragraph). No UX claims are made, so no Alexandria evidence is needed;
Dynamic Type work (T9) follows the AGENTS.md accessibility matrix.

## Problem

1. `GeminiService` has three hand-copied "hosted → plan → key check → run → fallback → error" pipelines:
   `callWorkoutAnalysis` (GeminiService.swift:318-395), `callTextFoodAnalysis` (:855-911) and `callAI` (:954-1030).
   `callAI` takes `route: JevTierRequest? = nil` (:850, :958). Passing nil skips the router, and seven call
   sites do: :297 what-if, :536 label, :560 allergens, :621 nutrient goals, :734 goals, :812 weight trend,
   :1800 serving units. So the picker and Router stats miss them.
2. Two entry points have no callers anywhere in `ios/`, including tests, AppIntents, widgets and the share
   extension: `analyzeNutritionLabel` (:521) and `analyzeWeightTrend` (:751). The same is true of the
   single-image `extractAllergensFromLabReport(image:)` (:544); the only caller, ContentView.swift:7039, uses `images:`.
3. Build 61 grew ContentView.swift by a net 37 lines (+46/−9, `git diff --stat fdc5f2a 423fc3e5e`), even though god files are supposed to only shrink.
   The On-device model row and its state are at ContentView.swift:3993 (`@AppStorage`), :4199-4201
   (subtitle) and :4812-4817 (NavigationLink). The Weekly Challenge auto-delete section is at :5665-5681.
4. Double fallback. Take a picked on-device model whose text provider is on-device: `plan.strong` is
   the cloud text fallback (JevTierRouter.swift `cloudConfig`). If the escalation fails, `run` (:208) rethrows the primary error.
   The caller then asks `currentTextFallbackConfig(excludingPrimary: primary.provider)`, which excludes only the
   on-device provider, so the same cloud provider and model run a second time. The same thing happens in
   GeminiService (:885, :365, :997) and ChatService.swift:168. The cheap tier hits it too: when primary is the
   cheap model, a fallback equal to `base` is not excluded.
5. Hosted mode branches off before the router in all three pipelines (:333, :856, :960) and in
   ChatService.swift:54. No decision about this has been recorded.

## Resolutions after Codex review (binding; they override the text below where they differ)

- **R1** (P1 #1): `.never` is renamed **`.baseOnly`**: the picker and the classifier never change the config; the request
  uses the user's configured base exactly as today (the vision base for images). It does **not** force cloud, so goal
  calculation and the allergen/photo paths are byte-identical to today. ROUTER_SPEC documents that `.baseOnly` respects
  the user's own provider choice. Tested with cloud, Apple and Gemma bases (`goalCalculationNeverOnDevice`,
  `baseOnlyImagePathsKeepBase`).
- **R2** (P1 #2): when the double-fallback fix skips a fallback, the path's terminal-error policy runs on the
  escalation error first (workout `WorkoutTextError` surfaces directly), then the usual wrapping. `.strong` plans are
  unchanged. Tests: `skippedFallbackKeepsWorkoutTerminalError`, `strongPlanFallbackUnchanged`.
- **R3** (P1 #3): one integration branch and PR (the ship process), with refactor and behavior in separate commits,
  prefixed `refactor:`, `behavior:`, `test-harness:` or `docs:`. T7 is separate from T8; T9's helper extraction is
  separate from extending the cap.
- **R4** (P2 #4): Coach entry-point tests were **not** added. `ChatService.sendMessage` can't be driven through
  `AIRouteEnvironment` without a chat-specific transport seam for its tool loop, history and hosted Gemini path, which is
  a large ChatService refactor. Instead ChatService now shares `JevTierRouter.runWithFallback` with GeminiService, so the
  double-fallback rule has one home and its tests cover Coach's chain; Coach routing stays covered at plan level.
- **R5** (P2 #5): the CI grep gate is dropped; `.github` is untouched. The non-optional route on `routed` is the
  compile-time gate.
- **R6** (P2 #6): speech transcription (`SpeechService`) is listed as "excluded (STT, separate provider policy)" in the
  audit table. No code change.
- **R7** (P2 #7): T8 as planned; the AX2 cap stays on ContentView.swift:1511 (toolbar principal date) only. No new VQA
  scenarios in this build.
- **R8** (P2 #8): T10 does **not** pin VQA dates (determinism is build 64). `reductionWeek: 4` in `bundledV2()` is its
  own behavior commit; expected screenshot change `12-program-editor`. No overhead-extension exercise.
- **R9**: no files are deleted (ServingSizeInputView stays). Deleting the dead functions and their callerless helpers is approved.

## Decisions proposed (for Jonathan and Codex)

- **D7: Hosted mode is excluded from the router, explicitly.** The hosted Worker picks the model and meters
  every call on the server (`HostedAIService.swift:28-33`). The router's only lever is the client-side
  provider/model, so it has nothing to decide. A recorded "hosted" decision would inflate Router stats
  with non-decisions. Letting the on-device picker take hosted traffic would change quota semantics,
  which is a product call and out of scope. Enforcement: the seam's hosted branch is the only hosted
  dispatch in GeminiService, and a test proves that hosted mode never calls `plan` (T2). Known limitation,
  to be documented: the picker is ignored in hosted mode.
- **D8: Tier policy per path.** It is encoded as a new `JevTierRequest.onDevicePolicy` with values `.scored` | `.pickerOnly` | `.never` (renamed `.baseOnly`, R1).

| Path | Case → `requestType` | Policy | Why |
|---|---|---|---|
| text food / coach chat / workout | unchanged | `.scored` | unchanged |
| food photo / coach photo | unchanged | `.never` | unchanged (no on-device image input on iOS 26) |
| allergen lab report | `.allergenReport` → `allergen_report` | `.never` | image |
| serving units after a photo | `.servingUnitsPhoto(name)` → `serving_units_photo` | `.never` | image |
| serving units after text | `.servingUnits(name)` → `serving_units` | `.pickerOnly` | short JSON; fixes the r61 "ignores the picker" gap |
| meal what-if | `.mealWhatIf(name)` → `meal_what_if` | `.pickerOnly` | short prose, low stakes |
| optional nutrient goals | `.nutrientGoals` → `nutrient_goals` | `.pickerOnly` | user opted in; escalates on failure |
| goal calculation | `.goalCalculation` → `goal_calculation` | **`.never`** (deviates from suggested default) | see below |

  Reasons for `calculateGoals`: it writes the user's saved targets. Its prompt (formulas, profile and evidence pack, :689-731) can
  exceed the 4,096-token context of Apple Foundation Models. It also runs unattended at launch (calorietrackerApp.swift:498),
  where a failure would silently set the picker's "fell back" notice on every launch. The alternative, `.pickerOnly`, is a
  one-line change if Jonathan prefers it.
  `.pickerOnly` never calls the Jev classifier. With the picker Off, it returns `base`.
  The recording rule copies foodPhoto (JevTierRouter.swift:139-144): record a decision only when the picker is set
  or tier routing is enabled. So a user with the router off and the picker Off gets zero Jev calls, zero records and
  `base` unchanged, which means byte-identical requests. `text` carries only the food name or is empty. The preview falls back to
  `requestType`, the same rule the image branch uses, so no profile data reaches local telemetry.

## Tasks in commit order

Three PRs against the launch branch: **A** refactor/delete (T1-T3), **B** behavior (T4-T6), **C** deferred (T7-T10).
Each task is one commit with one concern. Arrows mark dependencies.

**T1: Delete dead AI entry points** (no behavior change). Delete `analyzeNutritionLabel`, `nutritionLabelJSONShape`
(:212, used only there), `addingFallbackServingUnits(to: NutritionLabelAnalysis, image:)` (:1750, used only there),
`analyzeWeightTrend`, and `extractAllergensFromLabReport(image:)`. **Keep** these, because tests use them:
`parseNutritionLabel` (ServingUnitFallbackTests:128, GeminiRequestConfigurationTests:130),
`NutritionLabelAnalysis`, `ServingUnitRepairPolicy.shouldRepair(NutritionLabelAnalysis)`
(GeminiRequestConfigurationTests:134) and `WeightForecast` (WeightAnalysisService, GoalEvidence).
Also found: `ServingSizeInputView` has no instantiation anywhere. Removing it means deleting a file, which needs
Jonathan's approval (Rule 0), so it is listed for him and **not** done here.
Acceptance: grep returns zero hits for the deleted symbols, CI builds green, and no test changes.

**T2: One seam for every GeminiService AI call** (refactor; → T1). In GeminiService:
```swift
struct AIAttempt { let provider: AIProvider?; let send: (_ prompt: String, _ json: Bool) async throws -> String } // provider nil = hosted
static func routed<T>(_ route: JevTierRequest?, images: [UIImage] = [],
                      terminal: (Error) -> Bool = { _ in false },
                      _ perform: (AIAttempt) async throws -> T) async throws -> T
```
- The steps run in today's order. Hosted → `perform(hostedAttempt)`, which sends the capped JPEGs plus `currentUserContext`
  (:960-967). Otherwise: base = `currentConfig(requiresVision: !images.isEmpty)`, then plan. A nil route →
  `JevTierPlan(primary: base, strong: base, tier: .strong)` without calling `plan` (identical to :970-973). Then the noAPIKey check, then
  `JevTierRouter.run`, then a fallback (image or text, chosen by whether there are images), then the existing
  `AIRequestErrorPolicy` / `AnalysisFallbackError` surfacing.
- JPEG encoding stays outside `run`, once and before the first attempt, exactly as at :978 today.
- `terminal` keeps the per-path rules isomorphic. callAI passes `imageConversionFailed`. Workout passes `is WorkoutTextError`,
  applied to both the primary and fallback errors (:364, :384). Text food passes nothing.
- `callAI(prompt:images:jsonResponse:route:)`, `callTextFoodAnalysis` and `callWorkoutAnalysis` become thin wrappers.
  Text food maps `attempt.provider == .appleIntelligence` to `OnDeviceFoodService`, as `dispatchFoodAnalysis` does now.
  Workout's `analyze(_ ask:)` takes `attempt.send` for both the hosted and cloud attempts.
- The only `dispatch(` and `HostedAIService.generate(` calls left in GeminiService are inside `routed`.
- Test seam: `AIRouteEnvironment`, a Sendable struct of `@MainActor @Sendable` closures (`isHosted`, `base`,
  `plan`, `textFallback`, `imageFallback`, `dispatch`, `hosted`). It is held in `@TaskLocal static var environment = .live`.
  It is not a Mock type: it follows the same closure-injection style as `JevTierRouter.plan`'s parameters. The
  justification is that CI cannot reach providers, Keychain keys or on-device models, while prompts and parsers
  still run for real.
- ChatService keeps its own plan/run because its tool loop and hosted Gemini path differ. T4 patches it.
Tests (new, in JevTierRoutingTests.swift, which is CI-listed, so private helpers stay reachable):
`seamHostedNeverPlans`, `seamNilRouteUsesBaseWithoutPlan`, `seamTextFoodPlansFoodText`,
`seamImageFallbackForImages`, `seamTerminalErrorSkipsFallback`, `seamWorkoutClarificationNeverFallsBack`, and
`seamPickedEscalationThenFallback_currentBehavior`. The last one pins today's attempts `[apple, X, X]`.
Every existing test stays unchanged.

**T3: Move the On-device model row out of ContentView** (refactor). Add `OnDeviceModelHubRow` to
`Views/OnDeviceModelPickerView.swift`, the same file as the screen it opens. It owns the `@AppStorage`, the subtitle,
the NavigationLink and `settings.onDeviceModel.picker`. ContentView loses :3993, :4199-4201 and :4812-4817 and gains one line.
**T3b** (separate commit): move the Weekly Challenge auto-delete section (:5665-5681) into
`WeeklyChallengeAutoDeleteSection(outcome:)` under Views/. Together these take about 27 lines out of ContentView.swift.
Acceptance: ContentView.swift byte size goes down, and the 55-picker and settings-hub VQA shots are pixel-identical.

**T4: No second try on an already-tried config** (behavior; → T2).
- Add a pure `JevTierPlan.attempted: [RequestConfig]`: `[primary]` when tier is `.strong`, otherwise `[primary, strong]`.
  Also add `JevTierPlan.alreadyTried(provider:model:baseURL:)`. "Same target" means the same provider, model and base URL,
  the identity rule AIProviderSettings already uses (AIProvider.swift:931-947).
- The seam and ChatService skip a configured fallback that `alreadyTried`. If the skipped fallback was the
  escalation target, they throw what a second try would have thrown, minus the redundant request:
  `AnalysisFallbackError(primary, strong, errorToSurface(primaryErr, strongErr))`. In chat this is `errorToSurface`.
  The strong error comes from a local captured in the non-escaping `perform`, so `run`'s contract does not change.
Tests: flip T2's pinned test to `[apple, X]` with fallbackName X. Add `fallbackDifferentFromStrongStillRuns` (`[apple, X, Y]`),
`cheapTierSkipsFallbackEqualToBase`, `strongPlanFallbackUnchanged` (`[base, Y]`), and
`alreadyTriedTable` (pure).

**T5: Route the five remaining paths** (behavior; → T2, T4).
- Add the new `JevTierRequest` cases and `onDevicePolicy` from D8. `hasImage` becomes `onDevicePolicy == .never && …`
  or stays per-case. Pick whichever keeps the image cases identical.
- `OnDeviceModelSelector.select`: `.never` → `.cloudOnly`, renamed from `.cloudForImage`. Its label comes from the request:
  images keep "image → cloud" and goals use "goals → cloud".
- `plan` `.router` case: `.pickerOnly` → if `isEnabled()`, report `.localShortcut(label: "fixed → your model")`.
  Either way, return `basePlan`.
- `routed(_ route:)` becomes **non-optional**. This is the compile-time gate: no GeminiService path can dispatch without a request.
- Call sites: :297 `.mealWhatIf(entry.name)`, :560 `.allergenReport` (images), :621 `.nutrientGoals`, :734 `.goalCalculation`,
  :1800 `image == nil ? .servingUnits(name) : .servingUnitsPhoto(name)`.
- CI gate: a step in `ios-build.yml`'s build job fails if `dispatch(provider:` or `HostedAIService.generate(` appears in
  GeminiService.swift outside `routed`, using a grep count. No entries are removed.
Tests, one per AI call path, driving the **public entry point** under `$environment.withValue` and asserting the
recorded `JevTierRequest.requestType` (plus `hasImage`):
`routeMealWhatIf`, `routeNutrientGoals`, `routeGoalCalculation`, `routeAllergenReport`, `routeTextFood`, and
`routeTextFoodServingRepair`. The canned reply has zero macros and malformed unit_options, so it records
`[food_text, serving_units]`. Also `routePhotoFood`, `routeAutoAnalyze`, `routeMultiPhoto`, `routePhotoServingRepair`
(records `serving_units_photo`), and `routeWorkoutParse` (text that misses the fast path).
Coach text and photo stay covered by the existing plan-level tests (`chatNeedingDataNeverOnDevice`,
`imageRequestAlwaysCloudTier`).
Policy tests: `pickerOnlySkipsClassifier` (`TypeSafeStub.requests` stays empty while routing is on),
`pickerOnlyHonorsPickedApple`, `pickerOnlyRouterOffPickerOffRecordsNothing` (byte-identical base),
`goalCalculationNeverOnDevice`, and an extended `requestTypes`.

**T6: Docs** (→ T5). In ROUTER_SPEC.md §6: an audit table where every row reads Yes or "excluded (D7)", the new
cases and policies, D7 and D8, and the double-fallback rule. This plan gets a status update.

**T7: One CTA/heading font token** (refactor). Add `IronTheme.heavyHeadline = Font.headline.weight(.heavy)` and use it in
IronPrimaryButtonStyle (IronTheme.swift:345). No pixel change.
**T8: Scale the fixed 17 pt heavy labels** (behavior, `goldens-update`; → T7). The sites are ContentView.swift:1511,
CCLaddersView.swift:340/366/619/627, PeptideHistoryView.swift:292, PeptidesView.swift:139 and ProgramV2WorkoutLogView.swift:361.
They are headings and labels, not CTAs. :1511 is the food-diary **toolbar principal** date. A principal title that scales
to AX5 can collide with the bar buttons, so that site gets `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`.
The reviewer can veto this and leave :1511 fixed.
**T9: Cap VQA canvases in one place** (test harness, `goldens-update`). Move the 5fa786358 cap into one
`VisualQACanvas.cappedMultiplier(_:)` helper. Apply it in both `render` functions (VisualQASnapshotTests.swift:917,
ProgressV2VisualQATests.swift:114) and delete the local copy at :1990-1995.
On the 17 Pro (2622 px tall), only canvases over 8000 px change: `43` (×4) and `p2-*` AX (×5), which go to ×3.0.
Every ×3 shot is 7866 px and stays under the cap. The six black renders show the top 7866 px of content instead.
Bottom content is cut off, which is the same trade-off 5fa786358 accepted.
**T10 (conditional): bundled reduction week.** Set `reductionWeek: 4` in `TrainingProgramBody.bundledV2()` (TrainingProgram.swift:461).
The dated builder is used: JLPhysicalTabView.swift:229 calls `programV2Day(for:on:)`. Findings:
- Week-3 curl +1 **already fires** for the bundled program, because `ProgramWeekRules` :50 doesn't depend on `reductionWeek`.
- The overhead-extension rule can never fire, because the bundled Day 2 (V3) has no "Overhead triceps extension (cable or DB)".
  Adding it means a V4 template change, which is out of scope and Jonathan's call.
- **Screenshot impact:** `12-program-editor` (bundled editor, VisualQASnapshotTests:134) would show reduction week 4
  in every size, on every date.
- `VisualQAFixtures.trainingDate` (:1518) starts from `.now`, so every shot that uses it renders reduction week if CI runs
  2026-10-19..25. That covers test49 (indirectly), the train and logger shots at :56, :69, :129, :142, :350, :512, :582,
  :619, :630, :640, :654 and :692, and the Home week card through HomeV2Cards.swift:808.
- Recommendation: do T10 only after a test-only commit pins `trainingDate` to start from 2026-10-05, which is what CI
  resolves today, so it is pixel-identical before 10-12. Both commits are `goldens-update` for `12`. Otherwise, defer T10.

## Acceptance (build)

- Every audit row reads Yes or "excluded (D7)", and every path has a JevTierRoutingTests case.
- With the router off and the picker Off, requests are unchanged: proven by `pickerOnlyRouterOffPickerOffRecordsNothing`
  and the T2 tests, which stay green through T5.
- ContentView.swift is smaller than at 5fa786358.
- CI is green on each commit SHA, and run URLs are cited in the handoff. Codex signs off on each PR.

## Risks (Swift 6.2 / Xcode 26; target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift 5 mode, approachable concurrency)

- **Exhaustive switches over `JevTierRequest`.** They are all in JevTierRouter.swift: `text`, `isChat`, `hasImage`, `requestType`
  (`isWorkout` uses if-case). `OnDeviceModelSelector.select` reads `hasImage`. `questions(for:)` reads the flags only.
  Outside those, no `switch` over it exists in app, tests, widgets or the watch app (grep for `JevTierRequest`). Associated values are `String`, which keeps the enum Sendable.
- **Renaming `.cloudForImage` breaks `selectorTable`.** The rename lands in T5, a behavior commit, with only that test edit.
  The alternative is to keep the name and widen its doc.
- **`@TaskLocal` needs a Sendable value.** The closures must be `@Sendable`, and test recorders must be `@MainActor` classes.
  If Sendable inference fights this, fall back to a MainActor `static var` that each test sets and restores. That is safe because the suite is
  `.serialized` and CI runs `-parallel-testing-enabled NO`.
- **Implicit MainActor everywhere.** `AIProviderSettings`, `OnDeviceModelState.current` and `JevTierRouter.plan` are all
  implicitly `@MainActor`. Don't add `nonisolated` to the seam. Don't add `Equatable` to `RequestConfig`, because it would be an
  isolated conformance under default isolation. Use `alreadyTried(provider:model:baseURL:)` instead.
- **`run`'s `perform` is non-escaping.** Mutating captured locals inside it (the T4 strong error) is legal. Escaping it would not be.
- **`AIAttempt.send` is a non-Sendable closure stored in a struct.** Keep `AIAttempt` non-Sendable. It never crosses an actor.
- **Test reach.** Private helpers in JevTierRoutingTests are file-private, so the new tests go in the same file, not an extension file.
- **T2 isomorphism hot spots:** order of plan vs. key check vs. JPEG encoding, workout's `WorkoutTextError` on both error
  paths, the text-food Apple branch, and hosted image capping. Each one has a T2 test.
- **Hosted metering is untouched.** `runWithHostedQuota` wraps the entry points outside the seam.

## Expected screenshot impact

| Commit | Shots |
|---|---|
| T1-T7 | none (T3 must be pixel-identical) |
| T8 | AX variants with those labels: 51/53 ladders, logger shots (4x, 49, build-62 logger), 60/67/68 peptides, food diary toolbar; default size expected identical (.headline = 17 pt) |
| T9 | the six black shots become real renders; nothing else |
| T10 | `12-program-editor` all sizes (+ any date-pinning diff, expected none) |

No golden is regenerated without a `goldens-update` PR and a before/after table.

## Status

Implementation in progress on `integ/build-63`; nothing pushed, no CI run yet. Commits are listed in the handoff.
"Done" requires a green `iOS Build CI` run on the exact SHA plus Codex sign-off (AGENTS.md Rule 0.5).
