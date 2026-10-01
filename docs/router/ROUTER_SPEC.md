# JL Physical: "Jev router" spec

Shared decision layer that asks TypeSafe's **Jev** (a decision-only "System One" model) cheap, fast questions **before, or instead of**, expensive LLM calls.

- **Target branch:** `cursor/settings-reorg`. Head read for this spec: `d856c2862` ("Show every More row above the iPhone SE tab bar."), 2026-09-28.
- **Prerequisite:** the **Estimate Check** (`/workspace/typesafe-provider/SPEC.md`) has landed. The router **reuses** its `TypeSafeClient`, `TypeSafeSettings` (Keychain key, endpoint direct / Vercel AI Gateway, model), its toggle, and its tests' URLProtocol stub. It never duplicates them.
- **Path convention:** paths are relative to `ios/calorietracker/` unless they start with `ios/` or `.github/`. Line numbers (`~L…`) are from `d856c2862` and will drift, so locate code by **symbol**.
- **Evidence tags:**
  - **[DOC]** TypeSafe or Apple documentation
  - **[OBS]** observed in the repo at `d856c2862`, or by probing the API without a key
  - **[ASM]** assumption or design choice (tune later)
  - **[UNK]** unknown

---

## 0. What Jev can and cannot do (constraints for every use)

| Fact | Tag |
|---|---|
| Only two endpoints: `POST /v1/systemone` with body `{state, model, questions}`, and `GET /v1/models` returning `{"models":[{name,description,release_date}]}`. Auth is `Authorization: Bearer <key>`. | DOC |
| `questions` is a **map** name → question. Answers come back keyed by the same names. | DOC (openapi `SystemOneRequest.questions`, `additionalProperties`) |
| `noul`: `{type, instructions, criteria?:{true,false}}` → `{"type":"noul","noul":p}`. **No confidence field.** | DOC |
| `choice`: `{type, instructions, criteria: map option → description \| object \| array \| null}`, max **255 options** → `{choice, confidence, probabilities}`. | DOC |
| `score`: `{type, instructions, criteria: [levels]}`, 2–10 levels → `{score (probability-weighted, may be fractional), confidence, probabilities, legend}`. | DOC |
| `instructions` and `state` may be JSON objects. Instructions can refer to fields in backticks. | DOC |
| Text only: no images, no generation of text or numbers. Weak at numbers, counting and numeric representations ("keep arithmetic in code"). Literal-minded; indirection hurts. English is best. | DOC (models, jaggedness doc) |
| Latency claim 70–500 ms. Price $0.042 per 1M input tokens, output free. 1,200 req/min, 250k tok/s ("adjusting dynamically"). Context 64k tokens (32k for state plus the longest question). | DOC (vendor claims, not measured by us) |
| Max number of questions per request; allowed characters in choice option keys. | UNK. Keep ≤ 8 questions per request and use `[A-Za-z0-9_-]` keys. |
| Vercel AI Gateway with provider fallbacks configured may return `confidence: 0` / `probabilities: {}` for choice answers. | DOC (Vercel). Our gates treat this as "not confident" → fallback. |
| Gateway behaviour for `score` / `noul` in that fallback mode. | UNK. Treat `confidence == 0` as not confident. |

Design rules that follow:
1. All arithmetic (thresholds, ratios, unit math, e1RM, quantity parsing) stays in Swift. Jev only makes semantic choices among options we built.
2. Every Jev answer passes a Swift gate (probability, confidence, margin). On anything else we fall back to **today's behaviour**.
3. Jev never writes data and never triggers logging. Every accepted decision leads to an existing review or confirmation screen.

---

## 1. Router core (commit 1)

### 1.1 Files (new)
The Xcode project uses `PBXFileSystemSynchronizedRootGroup` [OBS], so no `project.pbxproj` edits are needed.
```
Models/JevRouterSettings.swift
Services/JevRouter/JevRouter.swift            // actor: gating, budget, cache, circuit breaker, telemetry
Services/JevRouter/JevDecisionCache.swift     // in-memory LRU + TTL
Services/JevRouter/JevRouterTelemetry.swift   // local counters + last-N decision log
Services/JevRouter/JevText.swift              // normalization, fingerprints, fuzzy scores
Services/JevRouter/JevGates.swift             // pure accept/reject functions
Views/JevRouter/JevRouterSettingsSection.swift
Views/JevRouter/JevRouterStatsView.swift
```

### 1.2 Reuse, don't duplicate
- **Client:** `TypeSafeClient(baseURL:apiKey:session:timeout:retryDelaysNs:)`, `systemOne(_:)`. Request and response types: `TypeSafeRequest`, `TypeSafeQuestion` (`.noul/.choice/.score`), `TypeSafeJSON`, `TypeSafeResponse`, `TypeSafeAnswer`, `TypeSafeError` (from SPEC.md §3.7).
- **Retries:** the router passes `retryDelaysNs: []` for budgeted uses.
  - Verify the landed client treats `retryDelaysNs.count` as the retry count, so an empty array means no retry.
  - If it always retries once, make that minimal change and add a test. It must not change Estimate Check behaviour, which keeps `[500_000_000]`.
- **Settings:** `TypeSafeSettings.endpoint`, `.model`, `apiKey(for:)` (Keychain accounts `typesafe.apiKey.direct` / `typesafe.apiKey.vercelGateway`), `TypeSafeEndpoint.baseURL`.
  - Add **one** property, `static var hasCredentials: Bool`: the key for the current endpoint is non-empty and `model` is non-empty.
  - Redefine `isConfigured` as `enabled && hasCredentials`. The semantics stay the same, the code is just factored.
- **Toggle:** the Estimate Check keeps `typesafe.estimateCheck.enabled`. The router gets its own master toggle (below). Either toggle reveals the shared Service / API Key / Model / Test key rows.
- **Stub:** unit tests reuse the `TypeSafeStub` URLProtocol pattern from `TypeSafeEstimateCheckTests`.
  - Move it to `calorietrackerTests/Support/TypeSafeStub.swift` (internal) if both suites need it.
  - Add a `delay` option (the handler returns after `DispatchQueue.global().asyncAfter`) to test budgets.

### 1.3 Settings (`enum JevRouterSettings`, UserDefaults)
| Key (literal) | Default | Meaning |
|---|---|---|
| `jevRouter.enabled` | false | Master toggle for uses 1–5 |
| `jevRouter.killSwitch` | false | **Global kill switch.** No Jev call from any use, **including the Estimate Check**. It also works as a launch argument (`-jevRouter.killSwitch YES`) through the UserDefaults argument domain [DOC Apple], which is useful for QA and UI tests. |
| `jevRouter.use.mealMatch.enabled` | true | Use 1 |
| `jevRouter.use.tierRouting.enabled` | **false** | Use 2 (changes which model answers, so it is opt-in) |
| `jevRouter.use.coachIntent.enabled` | true | Use 3 |
| `jevRouter.use.exerciseMatch.enabled` | true | Use 4 |
| `jevRouter.use.plausibility.enabled` | true | Use 5 |
| `jevRouter.tier.allowOnDevice` | false | Use 2: may route to on-device Gemma |
| `jevRouter.tier.cheapTextModel` | "" | Use 2: user-picked cheaper model id for the **same** text provider ("" = no cheap tier) |
| `jevRouter.stats.v1` | – | Telemetry JSON (local only) |
| `jevRouter.exerciseAliases.v1` | – | Use 4 persistent alias cache (local only) |

```swift
enum JevUse: String, CaseIterable, Codable, Sendable {
    case mealMatch, tierRouting, coachIntent, exerciseMatch, plausibility, estimateCheck
}
extension JevRouterSettings {
    /// Single gate every consumer calls before building candidates (cheap, sync).
    static func isActive(_ use: JevUse, credentials: JevCredentials? = JevCredentials.current) -> Bool {
        guard !killSwitch, credentials != nil else { return false }   // everything off without a key
        if use == .estimateCheck { return TypeSafeSettings.enabled }
        return enabled && isUseEnabled(use)
    }
}
```
- **Everything off without a key:** `JevCredentials.current` is nil unless `TypeSafeSettings.hasCredentials`.
  - It is an in-memory snapshot `{endpoint, apiKey, model}`. It refreshes when `TypeSafeSettings.didChangeNotification` fires (**new**: post it from the TypeSafe key, endpoint and model setters) and on `scenePhase == .active`, so the Keychain is not read on every tap.
  - Tests inject credentials directly and **never touch the Keychain** (CI's Keychain returns -34018 [OBS]).
- **`deleteAllData()`:** removes every `jevRouter.*` key and clears the in-memory cache and decision log. Call it next to `TypeSafeSettings.deleteAllData()` in ContentView's delete-all-data handler.
- **Cloud backup:** `CloudBackupService.snapshotValues()` backs up **every** UserDefaults key that `CloudBackupPolicy.include` allows [OBS, `Services/CloudBackupArchive.swift`].
  - Add `if key.hasPrefix("jevRouter.stats") || key.hasPrefix("jevRouter.exerciseAliases") { return false }` so telemetry and caches stay on the device.
  - Toggles may be backed up.
- **Key tests:** add every literal to `SettingsKeyPreservationTests.storageKeyConstantsStillMatchTheirLiterals`.

### 1.4 `actor JevRouter`
```swift
struct JevCredentials: Equatable, Sendable { let endpoint: TypeSafeEndpoint; let apiKey: String; let model: String }
struct JevCallPolicy: Sendable { var budget: Duration; var retryDelaysNs: [UInt64]; var cacheTTL: TimeInterval }
enum JevSkipReason: String, Codable, Sendable {
    case killSwitch, noKey, useDisabled, circuitOpen, busy, timeout, keyRejected, rateLimited,
         overloaded, network, invalidRequest, invalidResponse, server, cancelled
}
enum JevOutcome: Sendable {
    case answered(TypeSafeResponse, fromCache: Bool, latencyMs: Int)
    case skipped(JevSkipReason)
}
actor JevRouter {
    static let shared = JevRouter()
    init(credentials: @escaping @Sendable () -> JevCredentials? = { JevCredentials.current },
         isActive: @escaping @Sendable (JevUse) -> Bool = { JevRouterSettings.isActive($0) },
         session: URLSession = .shared,
         cache: JevDecisionCache = JevDecisionCache(capacity: 256),
         telemetry: JevRouterTelemetry = .shared,
         now: @escaping @Sendable () -> Date = { Date() })
    /// `build` receives the model id from settings (e.g. "jev-latest" or "typesafe-ai/jev").
    func ask(_ use: JevUse, cacheKey: String?, preview: String,
             policy: JevCallPolicy? = nil,
             build: @Sendable (String) -> TypeSafeRequest) async -> JevOutcome
    /// Consumers report what they did with the answer (for stats + debug view).
    func report(_ use: JevUse, _ decision: JevDecision)
}
enum JevDecision: Sendable {
    case accepted(label: String, confidence: Double?, llmCallsAvoided: Int)
    case localShortcut(label: String, llmCallsAvoided: Int)      // decided in Swift, no Jev call
    case fellBack(JevFallback)                                   // lowConfidence, none, skipped(reason), guardRejected
    case userOverride                                            // "Estimate with AI instead", "Ask Coach instead", "Save anyway"
}
```
`ask` algorithm:
1. If `!isActive(use)`, return `.skipped(.killSwitch / .noKey / .useDisabled)`.
2. Cache lookup by `"\(use)|\(endpoint)|\(model)|\(cacheKey)"`. On a hit, return `.answered(fromCache: true)`.
3. Circuit breaker [ASM]:
   - 3 consecutive `timeout / network / overloaded / server` → open for 5 min.
   - `keyRejected` → open until the credentials change.
   - `rateLimited` → open for `Retry-After` (capped at 60 s), else 30 s.
   - While open → `.skipped(.circuitOpen)`.
4. Concurrency cap [ASM]: at most 2 in-flight calls. A third one → `.skipped(.busy)`, never queued (a queued decision would miss its budget anyway).
5. Build `TypeSafeClient(baseURL: endpoint.baseURL, apiKey:, session:, timeout: budget + 0.25 s, retryDelaysNs: policy.retryDelaysNs)`.
6. **Race** `client.systemOne(build(model))` against `Task.sleep(for: policy.budget)` in `withThrowingTaskGroup`.
   - The first to finish wins and the loser is cancelled. Budget expiry → `.skipped(.timeout)`.
   - `URLRequest.timeoutInterval` is an idle timeout, not a total one, hence the race [DOC Apple].
7. Map `TypeSafeError` → `JevSkipReason`. `CancellationError` → `.skipped(.cancelled)`, which is not counted as a failure.
8. On success: store in the cache (TTL from the policy), record latency and `usage.input_tokens`, and append a decision record.

Default policies [ASM, tune with a real key]:

| Use | Budget | Retries | Cache TTL |
|---|---|---|---|
| 1 mealMatch | 800 ms | none | 24 h (in memory, the key includes a candidate fingerprint) |
| 2 tierRouting | 500 ms | none | 1 h |
| 3 coachIntent | 700 ms | none | 1 h |
| 4 exerciseMatch | 800 ms | none | memory 24 h; confident answers also persisted as aliases (§5) |
| 5 plausibility | 600 ms | none | 1 h |
| 6 estimateCheck | **10 s** (unchanged, runs async behind a visible screen) | `[500 ms]` (unchanged) | 1 h |

### 1.5 Cache (`JevDecisionCache`)
- An in-memory LRU with 256 entries and a per-entry TTL. It stores `TypeSafeResponse` only (no request text).
- **Key:** the use-specific normalized input plus a fingerprint of the candidate set, hashed with SHA-256 (CryptoKit). Plain text is never used as a key.
- **Normalization** (`JevText.normalize`):
  - fold case, diacritics and width (`folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)`);
  - map non-alphanumerics to spaces, collapse whitespace, trim.
  - Numbers are **kept**: "2 eggs" and "3 eggs" must not share a decision.
- Cleared on credential or model change, on `deleteAllData`, and by "Reset stats".

### 1.6 Telemetry (local only) and the debug view
`JevRouterTelemetry` (`@Observable @MainActor final class`, `static let shared`, injectable `UserDefaults` for tests):
- **Per-use counters:**
  - `requests` (network), `cacheHits`, `localShortcuts`, `accepted`
  - `fallbacks[JevFallback]`, `skipped[JevSkipReason]`, `userOverrides`
  - `llmCallsAvoided`, `inputTokens`
  - `latencyBuckets` in ms: `[≤100, ≤200, ≤400, ≤800, ≤1600, >1600]`
  - `since: Date`
- **Derived:**
  - p50/p95 latency (bucket upper bounds, so approximate);
  - **net LLM calls avoided** = `llmCallsAvoided − userOverrides` (uses 1, 3, 4);
  - estimated Jev spend = `inputTokens × $0.042 / 1M` [DOC price].
- **Persistence:** stored as JSON under `jevRouter.stats.v1`. Writes are debounced (at most once per 5 s and on `scenePhase` background). Excluded from cloud backup (§1.3). Never sent anywhere.
- **Decision log:** a ring buffer of the **last 50** `JevDecisionRecord {date, use, preview, result, confidence?, latencyMs?, source: network|cache|local|skipped, reason?, resolvedModel?}`.
  - **In memory only**, gone after relaunch.
  - `preview` is at most 40 characters of the user's own text, shown only on this device.
  - `os.Logger(subsystem:…, category: "JevRouter")` logs only use, outcome and latency. Text is logged with `privacy: .private`. **Never log the key.**
- **"Router stats" row:** Settings → More → Food & AI → **Advanced AI** → "Jev Router" section → `NavigationLink("Router stats")` → `JevRouterStatsView`.
  - Summary line: "Saved ~N AI calls · p50 X ms · ~$0.000Y Jev spend".
  - One card per use with its counters.
  - "Recent decisions (this session)" list (the debug view, identifier `jevRouter.stats.decisions`).
  - "Reset stats" (a destructive-style button with confirmation).

### 1.7 Settings UI
- **AI Providers card** (added by the Estimate Check, `TypeSafeSettingsSection.swift`):
  - Retitle the subsection header to **"TypeSafe Jev"**. Keep the existing identifiers.
  - Add a second toggle **"Jev router (faster, cheaper AI)"** (`settings.jevRouter.enabled`).
  - Show Service / API Key / Model / Test key when **either** toggle is on.
  - Update the info text: "Jev makes quick yes/no and multiple-choice decisions so the app can skip or shrink AI calls. It only receives text (never photos). Nothing is logged without your review."
- **Advanced AI page:**
  - Add a new section after "Instructions" (`if settingsCategory == .advancedAI`, ~L5940), header `IronInfoSectionHeader(title: "Jev Router", infoTopic: .jevRouter)` (new `AISettingsInfoTopic` case).
  - Show the section when `TypeSafeSettings.hasCredentials && (router || estimate check on)`.
  - Rows:
    - per-use toggles: "Match typed meals to saved meals", "Coach shortcuts", "Model tiers", "Exercise matching", "Plausibility checks";
    - under "Model tiers": "Allow on-device Gemma" (disabled, with a subtitle, when `!Gemma4LocalModelManager.isCurrentDeviceSelectable`) and "Cheaper text model" (a picker over `selectedTextProvider.textModels` plus "None");
    - **"Pause all Jev calls"** (the kill switch, `settings.jevRouter.killSwitch`);
    - **"Router stats"**.
  - Identifiers: `settings.jevRouter.<use>`, `settings.jevRouter.stats`.

### 1.8 Core tests: `calorietrackerTests/JevRouterCoreTests.swift`
Swift Testing, `@Suite(.serialized)`. Use an ephemeral `URLSession` with `protocolClasses = [TypeSafeStub.self]`, injected credentials, and a `UserDefaults(suiteName:)` for telemetry. **No Keychain.**
1. `killSwitchMakesZeroRequests` (and `killSwitch` also blocks `.estimateCheck`).
2. `noCredentialsMakesZeroRequests` for every `JevUse`.
3. `budgetExceededReturnsTimeoutQuickly`: the stub delays 2 s, the budget is 300 ms. Expect `.skipped(.timeout)` in under 1 s, and `skipped[.timeout] == 1`.
4. `cacheHitAvoidsSecondRequest`: the same key twice → 1 request, `cacheHits == 1`.
5. `circuitOpensAfterThreeFailures`: three 529s (no retry) → the 4th call is `.skipped(.circuitOpen)` with 0 new requests. It closes after the injected clock moves 5 min.
6. `keyRejectedOpensCircuitUntilCredentialsChange` for both 401 and 403 [OBS].
7. `requestShapeIsDocumented`: POST `{base}/v1/systemone`, `Authorization: Bearer test-key`, the body has `state`, `model`, and `questions` as an object. Repeat with the gateway base `https://ai-gateway.vercel.sh/typesafe` and model `typesafe-ai/jev`.
8. `gatesRejectGatewaySentinels`: `confidence 0, probabilities {}` → `JevGates.acceptChoice` returns nil.
9. `telemetryPersistsAndResets`, `decisionLogKeepsLast50`, `statsNeverContainKeyOrPreview` (the persisted JSON contains neither `"test-key"` nor preview text).
10. `backupPolicyExcludesRouterStats` (`CloudBackupPolicy.include("jevRouter.stats.v1") == false`).

### 1.9 Pure gates (`JevGates`) [ASM thresholds]
```swift
static func acceptChoice(_ a: TypeSafeAnswer?, minP: Double, minConfidence: Double, minMargin: Double,
                         reject: Set<String> = ["none"]) -> String?
// needs case .choice, choice ∉ reject, confidence ≥ minConfidence, probabilities[choice] ≥ minP,
// probabilities[choice] − second-highest ≥ minMargin; empty probabilities → nil
static func noulAtLeast(_ a: TypeSafeAnswer?, _ p: Double) -> Bool      // case .noul(x) && x ≥ p
static func scoreIfConfident(_ a: TypeSafeAnswer?, minConfidence: Double) -> Double?
```

---

## 2. Use 6: the Estimate Check as a router consumer (commit 1)

- **Hook:**
  - `TypeSafeEstimateChecker.liveCheck(_:)` (`Services/TypeSafeEstimateChecker.swift`, from SPEC.md §3.8) now calls `JevRouter.shared.ask(.estimateCheck, cacheKey: <normalized name|kcal|grams|items>, preview: input.name, build: { makeRequest(for: input, model: $0) })`, then the unchanged pure `verdict(for:response:)`.
  - `check(_:client:model:)` stays for the existing tests.
- **Candidates:** none (it is a checker). **Questions:** unchanged: `plausible` (noul), `calorie_band` (choice, 6 options), `density` (choice, 5 options) [SPEC.md].
- **Thresholds:** unchanged (noul < 0.30, band mass < 0.25, confidence ≥ 0.5, ±2 levels) [ASM].
- **Fallback:** `.unavailable` → no badge (unchanged).
- **Budget:** 10 s with one retry, unchanged, because the check runs behind an already-visible review screen.
- **New behaviour:**
  - The kill switch, the circuit breaker, telemetry and the decision log now apply.
  - **Skip the check when the result came from a use-1 saved-meal match**: those macros were already reviewed by the user.
- **Cache:** 1 h by normalized input, so re-presenting the same review sheet doesn't repeat the call.
- **Telemetry:** `accepted` with label `ok` / `looksOff:<band>`; `userOverride` when "Re-estimate" is tapped. No LLM calls avoided: this use *adds* a Jev call and may add one re-estimate.
- **Privacy:** unchanged: food name, item names, grams, and the user's note. Never photos.
- **Tests:**
  - the 13 existing `TypeSafeEstimateCheckTests` must pass unchanged;
  - add `estimateCheckHonorsKillSwitch` and `estimateCheckRecordsTelemetry` in `JevRouterCoreTests`.

---

## 3. Use 1: typed-meal match to saved meals and recents (commit 2)

**Goal:** "chicken burrito bowl" typed or spoken → the user's saved "Chicken burrito bowl" with its stored macros, **with no LLM call**. The user still reviews it before logging.

### Hook
- `ContentView.startTextAnalysis(_:)` (~L2177) [OBS]. Both `TextFoodInputView(onSubmit:)` (~L1557) and `VoiceInputView(onSubmit:)` (~L1573) call it after setting `currentFoodSource = .textInput`.
- Inside the existing `analysisTask = Task { … }`, **before** `GeminiService.analyzeTextInput(description:)`, add:
  ```swift
  if !bypassSavedMatch, let match = await SavedMealMatcher.match(description, store: foodStore) { presentSavedMatch(match, description); return }
  ```
- Add a `bypassSavedMatch: Bool = false` parameter.
- The loading sheet (`presentFoodLogLoading(.analyzingText)`) is already on screen, so the ≤ 800 ms decision needs no new UI.
- `presentSavedMatch` mirrors the `RecentsView(onReview:)` closure (~L1803):
  - Extract its long `GeminiService.FoodAnalysis(name:calories:…)` mapping into `extension GeminiService.FoodAnalysis { init(savedEntry: FoodEntry) }` and use it in both places. This is a pure refactor.
  - Set `currentEmoji`, `currentFoodSource = entry.source`, `retryRequest = nil`, and a new `@State savedMatchContext: SavedMatchContext?` (`{entryName, originalDescription}`).
  - Then call `presentFoodResult(analysis)`.
  - Photos: don't attach the saved entry's photos (`currentImages = []`). It's a typed log. [ASM]
- `FoodResultView` gets one defaulted parameter, `savedMatch: SavedMatchBanner? = nil`.
  - It shows a compact row: "Matched your saved meal · *Chicken burrito bowl*", with the button **"Estimate with AI instead"** (`foodReview.savedMatch.estimateInstead`).
  - That button calls `startTextAnalysis(original, bypassSavedMatch: true)` and reports `.userOverride`.
- Pass `estimateCheck: .off` when `savedMatchContext != nil` (use 6 rule).
- Serving size and quantity stay editable as they are for Recents today.

### Candidate construction (Swift, `Services/JevRouter/SavedMealMatcher.swift`)
1. **Pool:** `foodStore.favorites` + `foodStore.frequentGroups(days: 90).map(\.template)` + `foodStore.recentEntries(days: 30)` [OBS, `Stores/FoodStore.swift`].
   - Dedupe by `"\(name.lowercased())|\(calories)"` (the same key `frequentGroups` uses).
   - Drop empty names and `calories <= 0`.
   - Priority for ties: favorite > frequency count > recency.
2. **Input guards** (skip Jev and go straight to the LLM):
   - the description is longer than 200 characters or has more than 12 tokens;
   - it is empty after normalization.
3. **Filler stripping** (for matching only):
   - words: `i, had, ate, just, my, usual, the, a, an, some, for, today, breakfast, lunch, dinner, snack, log, please`;
   - `JevText.normalize` keeps numbers.
4. **Fuzzy prefilter:**
   - `score = max(tokenDice(input, name), trigramJaccard(input, name))`;
   - keep `score ≥ 0.35` and take the **top N = 8** [ASM];
   - zero survivors → **no Jev call** (`fellBack(.noCandidates)`), then the LLM as today.
5. **Code-side guards** (numbers stay in Swift, DOC jaggedness):
   - *Quantity guard:* if the input contains a number, fraction, or quantity word (`half, double, two, three, couple, large, small, extra, x2, 2x`) that is **not** in the candidate's name, drop that candidate. Stored macros describe one saved serving.
   - *Multi-item guard:* if the input contains ` and `, `,`, `+`, `&`, or ` with ` and the candidate name does not contain the same connector, drop the candidate.
6. **Exact shortcut:** exactly one survivor whose normalized name equals the normalized input → accept with **no Jev call** (`localShortcut`, `llmCallsAvoided: 1`).

### Jev question
```json
{
  "model": "<settings model>",
  "state": { "typed_meal": "chicken burrito bowl from chipotle" },
  "questions": {
    "meal": {
      "type": "choice",
      "instructions": {
        "task": "Which saved meal is the same food as `typed_meal`? Choose none if it is a different food, a different variety or brand, several foods, or clearly a different amount.",
        "typed_meal": "chicken burrito bowl from chipotle"
      },
      "criteria": {
        "m1": "Chicken burrito bowl (1 bowl)",
        "m2": "Chicken burrito (1 burrito)",
        "m3": "Steak burrito bowl (1 bowl)",
        "none": "None of these saved meals is the same food"
      }
    }
  }
}
```
- Option values are the saved name plus the human serving label (`selectedServingQuantity`/`selectedServingUnit` when present, else omitted). **No calories or macros are sent.**
- Keys are `m1…mN` mapped back in Swift (key-character rules are [UNK]).

### Threshold and fallback [ASM]
- Accept when `JevGates.acceptChoice(meal, minP: 0.80, minConfidence: 0.60, minMargin: 0.30)` returns `mK`.
- Otherwise (`none`, low confidence, gateway sentinel, timeout, error) → `GeminiService.analyzeTextInput` exactly as today. The only cost is ≤ 800 ms of extra wait in the worst case.

### Savings mechanism
Each accepted match skips **one** text-food LLM call (primary, plus a possible text fallback) and, in hosted mode, one `.textFood` quota unit. `analyzeTextInput` runs `runWithHostedQuota(.textFood)` [OBS]; the hook sits before it. Latency goes from multi-second LLM generation [ASM] to about 0.1–0.8 s (vendor claim [DOC] plus the network).

### Cache
Key: normalized input + fingerprint of `(key, name, calories)` for all N candidates, 24 h in memory. Negative results (`none`) are cached too.

### Telemetry
- `requests`, `localShortcuts`, `accepted` (with `llmCallsAvoided: 1`), `fallbacks[.none/.lowConfidence/.noCandidates/.guardRejected]`, latency.
- `userOverride` on "Estimate with AI instead".
- Record "logged after match" when `onLog` fires with `savedMatchContext != nil` (a precision proxy).

### Privacy
Sends the typed or transcribed text and up to 8 saved meal names with serving labels. **Never photos**: saved entries' image data is never read into the request. No macros, no profile. Voice audio stays on the device; only the transcript text is sent.

### Out of scope
`SiriLoggingService.analyzeAndLogFood` logs without review [OBS], so the router is **not** hooked there (it must never auto-log).

### Tests: `calorietrackerTests/JevMealMatchTests.swift`
1. `prefilterRanksAndCapsAtEight` (pure, 20 saved meals).
2. `fillerWordsIgnored` ("i had my usual oatmeal" → "Oatmeal" top).
3. `quantityGuardDropsMismatch` ("2 bowls of chili" vs "Chili" → no candidates → 0 requests).
4. `multiItemGuard` ("salad and a coke" vs "Caesar salad" → dropped).
5. `exactMatchMakesZeroRequests`.
6. `requestShape`: `questions.meal.type == "choice"`, criteria keys `m1…mN` plus `none`, and no `calories` / `kcal` digits from the saved macros anywhere in the body.
7. `confidentAnswerReturnsEntry`.
8. `lowMarginFallsBack` (0.55/0.40).
9. `noneFallsBack`.
10. `sentinelFallsBack`.
11. `timeoutFallsBackWithinBudget` (stub delay 2 s → nil in < 1.2 s).
12. `secondIdenticalCallUsesCache`.
13. `killSwitchAndNoKeyMakeZeroRequests`.
14. `savedEntryMappingMatchesRecentsReview` (`FoodAnalysis(savedEntry:)` copies name, macros, micros, `reviewServingReference`, `reviewServingUnitOptions`).

---

## 4. Use 3: Coach intent classification (commit 2)

**Goal:** Coach messages that are really "log this", "log my sets", "what's today's session?", or "how many steps?" are handled by existing local code. Only open chat reaches the LLM.

### Hook
`ChatView.send()` (`Views/ChatView.swift` ~L669) [OBS]. Insert after `chatStore.append(ChatMessage(role: .user, …))` and **before** `ChatService.sendMessage(...)`:
```swift
if image == nil, !bypassRouter, let handled = await CoachIntentRouter.route(text, context: …) { chatStore.append(handled.message); return }
```
Conditions:
- no image attached (photos never go to Jev);
- `text.count ≤ 300`;
- `JevRouterSettings.isActive(.coachIntent)`.

Everything else goes through `ChatService.sendMessage` unchanged. That includes the hosted branch (`AIModeSettings.isHosted` → `hostedCoachMessage`, ~L55) and on-device providers.

### Questions (one request, shared `state`)
```json
{
  "state": { "message": "how many steps have I done today?" },
  "questions": {
    "intent": {
      "type": "choice",
      "instructions": "What does the user want from this one message to their fitness coach app?",
      "criteria": {
        "log_food": "Record food or drink they ate or are eating, e.g. 'log 2 eggs and toast', 'I just had a latte'",
        "log_sets": "Record a finished workout or sets, e.g. 'bench 3x8 at 80 kg', 'log a 30 minute run'",
        "program_question": "Ask what their training program says: today's or the next session, or rest days",
        "steps_question": "Ask about their step count or step goal",
        "open_chat": "Anything else: advice, questions about trends or nutrition, feelings, or several requests at once"
      }
    },
    "program_detail": {
      "type": "choice",
      "instructions": "If the message asks about the training program, what exactly?",
      "criteria": { "today_session": "What to train today", "next_session": "The next session or rest day", "other": null }
    },
    "steps_detail": {
      "type": "choice",
      "instructions": "If the message asks about steps, which period?",
      "criteria": { "today": null, "yesterday": null, "last_7_days": "This week or the last seven days", "goal": "Their daily step goal", "other": null }
    }
  }
}
```
Only the current message is sent. No chat history, profile or health data [ASM: short follow-ups like "yes" will classify as `open_chat`, which is the safe default].

### Threshold and fallback [ASM]
- `intent` passes `acceptChoice(minP: 0.85, minConfidence: 0.60, minMargin: 0.40, reject: ["open_chat"])`.
- For `program_question` or `steps_question`, the matching detail must pass `acceptChoice(minP: 0.70, minConfidence: 0.50, minMargin: 0.30, reject: ["other"])`.
- Anything else, or the local handler failing (no program cached, HealthKit error), → `ChatService.sendMessage` as today.

### Local handlers (existing code) [OBS]
| Intent | Handler | Local reply |
|---|---|---|
| `steps_question` | `StepsTrackingService.shared.fetchTodaySteps()` / `fetchYesterdaySteps()` / `fetchLast7Days()` (`Services/StepsTrackingService.swift`), goal `StepsGoal.current` (`Models/StepsGoal.swift`) | "You're at 6,420 steps today, 64% of your 10,000 goal." Numbers are formatted in Swift. On throw → LLM. |
| `program_question` | `ActiveProgramCache.load()?.body` + `TrainingProgramSchedule.resolve(_:on:)` → `ResolvedTrainingDay .session/.rest/.upcoming` (`Models/TrainingProgram.swift`); exercise names from `body.days[dayIndex]` | "Today: Upper A (Bench press, Row, …)." / "Rest day. Next: Lower B on Thu." With no cached program → LLM. |
| `log_food` | Home text flow `ContentView.startTextAnalysis(_:)` (which benefits from use 1) | An assistant bubble "I'll open the food review so you can check it first" with a **"Log food"** button. |
| `log_sets` | Legacy text logger `WorkoutTextView` → `GeminiService.analyzeWorkout` → review → `StrengthWorkoutStore.addTextWorkout` (`Views/WorkoutTextView.swift`) | An assistant bubble with a **"Log workout"** button that presents `WorkoutTextView(selectedDate: .now, unit:, bodyWeightKg:, onAdded:, initialDescription: text)` as a sheet **from ChatView**. ChatView already has `StrengthWorkoutStore` in its environment [OBS]. Add a defaulted `initialDescription: String? = nil` that pre-fills and auto-runs `analyze()` once. That path then uses use 4. |

- **Food handoff (new plumbing):** add `@Observable final class RouterHandoff { var pendingFoodText: String? }` injected at the app root.
  - "Log food" sets it.
  - ContentView observes it with `.onChange`, sets `selectedTab = .home` (`AppTab`, ~L236), `currentFoodSource = .textInput`, `startTextAnalysis(text)`, and clears it.
  - This mirrors the existing `consumePendingLaunchRoutes()` pattern.
- **Never logs by itself:** both buttons open the existing review screens.
- **Chat model:** `ChatMessage` gets optional `routerAction: RouterChatAction?` (`.logFood(String)`, `.logWorkout(String)`, `.localAnswer`) with a default of `nil`. The synthesized `Codable` decodes a missing optional as `nil`, so stored chats stay compatible. Add a test for that.
- **Bubble UI:** local bubbles show a small caption "Answered on device · **Ask Coach instead**" (`coach.router.askCoach`).
  - "Ask Coach instead" calls the original `ChatService.sendMessage` path with `bypassRouter: true` and reports `.userOverride`.
  - Local replies stay in history as assistant messages, so later LLM turns see them [ASM].

### Savings mechanism
Each locally handled message skips **one Coach request**. That request can include up to 6 tool rounds (`ChatService.maxToolRounds = 6`) [OBS], so `llmCallsAvoided: 1` is conservative. Hosted users also save Coach quota. `log_food` and `log_sets` still run the food or workout LLM later unless uses 1 or 4 short-circuit it, so they count `llmCallsAvoided: 1` (the Coach turn) only.

### Cache
Normalized message → response, 1 h.

### Telemetry
Per-intent `accepted` counts, `fallbacks`, `userOverride` (Ask Coach instead), latency.

### Privacy
Sends the message text only. Never images: routing is skipped whenever an image is attached. Never history, profile, weights or foods.

### Tests: `calorietrackerTests/JevCoachIntentTests.swift`
1. `requestHasThreeChoiceQuestionsAndOnlyMessageInState`.
2. `stepsTodayRoutesLocal` (inject a `StepsProvider` protocol; `StepsTrackingService` conforms).
3. `programTodayUsesSchedule` (inject a `TrainingProgramBody` fixture → "Upper A").
4. `logFoodProducesActionNotEntry` (no `FoodStore` mutation).
5. `openChatReturnsNil`.
6. `lowConfidenceReturnsNil`.
7. `detailOtherReturnsNil`.
8. `imageAttachedSkipsJev` (0 requests).
9. `longMessageSkipsJev`.
10. `timeoutReturnsNil`.
11. `healthKitErrorFallsBackToLLM`.
12. `chatMessageDecodesWithoutRouterAction` (legacy JSON).

---

## 5. Use 4: exercise-name matching (commit 3)

**Goal:** simple workout text such as "bench 3x8 80kg, pullups 3x10, run 20 min" is resolved to real library ids **in Swift + Jev**, skipping both LLM calls in `GeminiService.analyzeWorkout`.

### Where names are matched today [OBS]
- `GeminiService.analyzeWorkout(description:date:unit:library:)` (~L302) makes **two** `callAI` calls:
  1. `WorkoutTextDraft.searchPrompt` → `searchQueries`
  2. `WorkoutTextDraft.prompt(... library ...)` → `WorkoutTextDraft.parse(_:library:)`
- Both run inside `runWithHostedQuota(.workoutAI)`.
- The candidate catalog is built by `WorkoutTextDraft.candidates(description:library:)` (keyword scoring, top 60).
- Validation is `WorkoutTextDraft.planned(library:)`.
- Callers: `WorkoutTextView.analyze()` (~L172), and (new) the Coach `log_sets` handoff.
- The **JL program logger** `ProgramV2WorkoutLogView` uses fixed program exercise names and has **no free-text parsing** [OBS], so use 4 doesn't apply there.
- The library search UI uses `ExerciseLibraryService.filtered(...)` with `ExerciseSearchMatcher.matches` (token AND plus an alias table) [OBS].

### Hook
At the top of `GeminiService.analyzeWorkout`, before `runWithHostedQuota`:
```swift
if let draft = await WorkoutFastPath.draft(description: description, date: date, unit: unit, library: library) { return draft }
```
The fast path only runs when `description` is a raw first-turn description. `WorkoutConversation.requestDescription()` returns JSON once follow-ups exist [OBS], so skip when the trimmed text starts with `{`.

### Candidate construction (Swift, `Services/JevRouter/WorkoutFastPath.swift`)
1. **`WorkoutLineParser` (pure).**
   - Split on newlines, `;`, and `, ` when followed by a letter.
   - Each line must fully match one of these patterns (case-insensitive), with units `kg|kgs|lb|lbs`:
     - `<name> <S>x<R> [@|at] [<W>[unit]] [@<rpe>|rpe <rpe>]`
     - `<S>x<R> <name> [...]`
     - `<name> <S> sets? (of|x) <R> [reps] [at <W>[unit]]`
     - `<name> <M> (min|mins|minutes)` (timed)
   - Max 8 lines, 12 sets per line, and the limits from `planned()`.
   - **Any unparsed token, date word (`yesterday`, weekday names), or unknown unit aborts the fast path** (→ LLM, which handles dates and clarifications).
   - Numbers are parsed in Swift only.
2. **Per-line candidates:**
   - `WorkoutTextDraft.candidates(description: nameFragment, library:)` `.prefix(12)`;
   - plus `ExerciseSearchMatcher.aliases[normalized]` and the persisted alias cache (`jevRouter.exerciseAliases.v1`, normalized fragment → id, only ids that still exist in `library`).
3. **Exact shortcut:** alias or cache hit, or the normalized fragment equals a normalized `item.name` → id with no Jev call.
4. The remaining unresolved lines (≤ 8) go into **one** Jev request with one question per line.

### Jev question (choice among real ids)
```json
{
  "state": { "workout": "incline db press 3x10 25kg\nlat pulldown 3x12" },
  "questions": {
    "ex_1": {
      "type": "choice",
      "instructions": {
        "task": "Which catalog exercise is `entry`? Choose none if it is not listed or if it could be several different variants (for example barbell vs dumbbell).",
        "entry": "incline db press"
      },
      "criteria": {
        "Incline_Dumbbell_Press": { "name": "Incline Dumbbell Press", "equipment": "Dumbbell" },
        "Incline_Dumbbell_Flyes": { "name": "Incline Dumbbell Flyes", "equipment": "Dumbbell" },
        "Barbell_Incline_Bench_Press_-_Medium_Grip": { "name": "Barbell Incline Bench Press - Medium Grip", "equipment": "Barbell" },
        "none": "Not listed, or unclear which variant"
      }
    },
    "ex_2": { "type": "choice", "instructions": { "task": "…", "entry": "lat pulldown" }, "criteria": { "…": "…" } }
  }
}
```
- Option keys are the real `ExerciseLibraryItem.id`s.
- Any id containing characters outside `[A-Za-z0-9_-]` is replaced by `e<n>` and mapped back, since the allowed characters are [UNK].
- Option values are objects `{name, equipment}` (DOC: objects are allowed).

### Threshold and fallback [ASM]
- Every line must pass `acceptChoice(minP: 0.75, minConfidence: 0.60, minMargin: 0.25)`.
- **All** lines must resolve, and the assembled `WorkoutTextDraft(date: StrengthWorkoutDate.key(for: date), exercises: …)` must pass `try draft.planned(library:)`.
- Units: explicit, else `unit`. Weight omitted → `""` (bodyweight). `intensity` is `"moderate"` for timed lines.
- Otherwise → the existing two-call LLM path, unchanged. It asks its own clarifications ("seated or standing?").
- The fast-path result goes to the existing `WorkoutTextReview`. **Nothing is saved without the user's Save.**

### Savings mechanism
A fully local parse skips **two** LLM calls (search queries + draft) and one `.workoutAI` hosted quota unit (the hook sits before `runWithHostedQuota`). Report `llmCallsAvoided: 2`. Latency drops from two sequential generations [ASM] to about ≤ 0.8 s, or 0 ms on alias or exact hits.

### Cache
- In memory: normalized fragment + candidate fingerprint → response, 24 h.
- **Persistent aliases:** confident accepts write `fragment → id` to `jevRouter.exerciseAliases.v1` (LRU, max 500, local only, excluded from backup, cleared by `deleteAllData`). An alias pointing to a deleted id is ignored and removed.

### Optional (same commit, behind the same toggle; skip if time-boxed)
- A "Did you mean …?" row when the library search (the view using `ExerciseLibraryService.filtered(..., searchText:)`, e.g. `WorkoutLogView` ~L1526) returns **zero** results for ≥ 3 characters.
- One `choice` over `candidates(description: searchText, library:).prefix(12)` + `none`, debounced 600 ms.
- It saves no LLM calls (UX only).

### Telemetry
`localShortcuts` (alias/exact), `accepted` (`llmCallsAvoided: 2` per fully local draft), `fallbacks[.parseFailed/.lowConfidence/.none/.validationFailed]`, latency.

### Privacy
Sends workout text and catalog names and equipment. No body weight, no history, never photos.

### Tests: `calorietrackerTests/JevExerciseMatchTests.swift`
1. Parser table: "bench 3x8 80kg", "3x10 pullups", "squat 5 sets of 5 at 100 kg", "run 20 min", "curls 3x12 @8" parse; "yesterday bench 3x8", "bench heavy", "bench 3x8 80 stone" abort.
2. `aliasHitMakesZeroRequests`.
3. `oneRequestForAllUnresolvedLines` (questions `ex_1`, `ex_2`; criteria keys are real ids plus `none`).
4. `allConfidentBuildsValidDraft` (`planned(library:)` passes, `exerciseID`s set, sets expanded, units kept).
5. `anyLineLowConfidenceFallsBack` (returns nil, no partial draft).
6. `noneFallsBack`.
7. `confidentAcceptPersistsAlias`, then `secondRunMakesZeroRequests`.
8. `staleAliasIgnored`.
9. `followUpJSONSkipsFastPath`.
10. `timeoutFallsBack`.

Use a small in-test library of `ExerciseLibraryItem(id:name:category:rawEquipment:)`.

---

## 6. Use 2: model tier routing (commit 3)

**Goal:** easy text requests go to the cheapest tier the user has already allowed: on-device Gemma, then a user-picked cheaper model, then the user's normal model. Hard ones stay on the strong (current) config.

### Tiers (only the user's own choices) [OBS for the APIs, ASM for the policy]
| Tier | Source | Eligible when |
|---|---|---|
| `onDevice` | `AIProvider.gemma4Local` (`apiFormat .liteRTLocal`) | `jevRouter.tier.allowOnDevice` **and** `Gemma4LocalModelManager.isCurrentDeviceSelectable` (eligible RAM **and** a verified, prepared install) [OBS] |
| `cheap` | Same provider, base URL and key as `AIProviderSettings.currentConfig(requiresVision: false)`, but `model = jevRouter.tier.cheapTextModel` | Non-empty, and the provider is not on-device |
| `strong` | `AIProviderSettings.currentConfig(requiresVision: false)` **unchanged** | Always (default and fallback) |

- The router **never switches provider or API key** and never enables a provider the user hasn't set up.
- Image requests, hosted mode (both call sites branch to hosted **before** reading the config [OBS]), and Apple Intelligence as a routed tier are out of scope. Apple Intelligence is an open question.

### Hooks
1. `GeminiService.callTextFoodAnalysis(prompt:description:)` (~L768): replace `let primary = AIProviderSettings.currentConfig(requiresVision: false)` with `let plan = await JevTierRouter.plan(.textFood(description), base: AIProviderSettings.currentConfig(requiresVision: false))`.
   - Try `plan.primary`. On error (not cancellation), retry once on `plan.strong` if it differs, then continue into the existing text-fallback chain unchanged.
   - `plan.primary` is a `RequestConfig`.
2. `ChatService.sendMessage` (~L98) `let config = AIProviderSettings.currentConfig(requiresVision: imageData != nil)`: only when `imageData == nil`, use `JevTierRouter.plan(.coachChat(text), base:)`.
   - `onDevice` is allowed for chat only when `needs_user_data` < 0.20, because the Gemma branch uses an "ON-DEVICE MODE" prompt **without tools** [OBS].
   - On error, retry once on `strong`, then continue into the existing fallback.
- **Skip Jev entirely** (0 calls) when no cheaper tier is eligible. That is the default: `tierRouting` is off, the cheap model is unset, and on-device isn't allowed.

### Questions
```json
{
  "state": { "request_type": "coach_chat", "text": "what's a good high protein snack?" },
  "questions": {
    "complexity": {
      "type": "score",
      "instructions": "How much reasoning does answering `text` need?",
      "criteria": [
        "Trivial: one common food, a greeting, or a one-line fact",
        "Simple: a few common foods with clear amounts, or a short general question",
        "Moderate: mixed or restaurant dishes, brands, or a question needing some reasoning",
        "Complex: many items, vague amounts, recipes, plans, or advice that depends on the person's history"
      ]
    },
    "needs_user_data": {
      "type": "noul",
      "instructions": "Answering needs the person's own logged data (weights, food log, workouts, program).",
      "criteria": { "true": "Needs their data", "false": "General knowledge is enough" }
    }
  }
}
```
Send `needs_user_data` only for `coachChat`. For `textFood`, the state is `{ "request_type": "food_text", "text": … }`.

### Decision (pure `JevTierRouter.decide`) [ASM]
- `s = scoreIfConfident(complexity, minConfidence: 0.60)`. If nil → `strong`.
- `s ≤ 0.6`:
  - `onDevice` if eligible (for chat, also require `noul(needs_user_data) < 0.20`);
  - else `cheap` if eligible;
  - else `strong`.
- `s ≤ 1.4` → `cheap` if eligible, else `strong`.
- Otherwise → `strong`.
- Text food on Gemma: only `s ≤ 0.6`. Gemma's food-estimation quality is [UNK].

### Fallback
Timeout (500 ms), error, or low confidence → `strong`, which is today's behaviour.

### Savings mechanism
No calls are avoided. The savings are **cost per call** (a cheaper model or free on-device) and **latency** (no network for Gemma, faster small models) [ASM]. Telemetry counts requests per tier and escalations (routed tier failed → strong).

### Cache
Normalized text + request type → response, 1 h.

### Privacy
Sends the request text only (typed meal or chat message). Never images: image requests are never routed.

### Tests: `calorietrackerTests/JevTierRoutingTests.swift`
1. `decide` table (score/confidence/noul × eligibility).
2. `noCheaperTierMakesZeroRequests`.
3. `gemmaNotSelectableFallsToCheap` (inject eligibility).
4. `chatNeedingDataNeverOnDevice`.
5. `lowConfidenceKeepsStrong`.
6. `timeoutKeepsStrong`.
7. `planNeverChangesProviderOrKey` (the cheap plan keeps provider/baseURL/apiKey and only the model differs).
8. `imageRequestAlwaysCloudTier`, `workoutParseEligibleForOnDevice`, `disabledRouterReturnsBase`.
9. Picker: `selectorTable`, `pickedAppleBypassesComplexityScore`, `pickedButUnavailableFallsBackToCloudWithNotice`, `pickedOnDeviceFailureEscalatesToCloudAndNotes`.

Test `JevTierRouter` with injected `base: RequestConfig` and eligibility closures (no `AIProviderSettings` / Keychain reads).

### Update: every cloud-mode AI path goes through `JevTierRouter.plan`
Request kinds: `textFood` (`food_text`), `coachChat` (`coach_chat`), `workoutParse` (`workout_parse`), `foodPhoto(caption:)` (`food_photo`), `coachPhoto` (`coach_photo`). Hosted mode still branches off first.

Order inside `plan`:
1. **Image requests** (`foodPhoto`, `coachPhoto`) return `base` with tier `strong`: on-device image input isn't available on iOS 26, so photos stay on the user's cloud vision provider. Zero Jev calls. When Model tiers or the picker is on, the decision is recorded as a `tierRouting` local shortcut ("image → cloud") so Router stats counts it.
2. **Settings → AI → On-device model** (`ai.onDeviceModel.choice`: `off` (default) | `appleFoundationModels` | `gemma4`). When set, the three text kinds use that model directly (no complexity score, no `needs_user_data` gate), with `strong = base`. If the model can't run now (Apple Intelligence off / model not ready, Gemma not downloaded and prepared), `base` answers and a one-line notice is stored (`ai.onDeviceModel.lastFallback`) for the picker screen. Recorded as `tierRouting` local shortcut "… (picked)" or `fellBack(skipped)`.
3. **Picker Off:** the Jev complexity score, exactly as above. Disabled tier routing returns `base`.

`JevTierRouter.run(plan)` is the shared escalation: try `primary`; if a cheaper or picked on-device tier throws, note the fallback (picked only), retry once on `strong`; if that fails, rethrow the primary error into each call site's existing text/image fallback chain. Workout clarifying questions are answers, not failures, so they never escalate.

---

## 7. Use 5: plausibility flags on sets and body metrics (commit 3)

**Goal:** catch typos and unit slips (80 → 800, kg vs lb, a 5 kg overnight "gain") with a **confirmation, never a block**. The math is in Swift; Jev only breaks ties in a grey zone.

### Swift rules (`Services/JevRouter/PlausibilityRules.swift`, pure) [ASM thresholds]
Flags are `strong` (always shown when the use is active) or `grey` (shown only if Jev says a mistake is likely).

**Sets.** Inputs: exercise name/id, load, unit, reps, prior sets for the same exercise.
- *Unit slip (strong):* load in kg ÷ reference load in kg is within ±8% of **2.2046 or 0.4536**. Suggest "Did you mean <x> kg/lb?".
- *Digit slip (strong):* ratio within `[8, 12]` or `[0.08, 0.125]`, with reps within ±3 of the reference.
- *Outlier:* `e1RM = load × (1 + reps/30)` (Epley) vs the best e1RM in the reference. Ratio > 1.35 → strong; 1.15–1.35 → grey.
- *Absolute (strong):* reps > 100, load > 500 kg (1,100 lb), or a load with an unknown unit.
- *In-session (grey):* the set load differs by more than 2× from the median of the other sets of the same exercise in this entry.
- **References by hook:**
  - `ProgramV2WorkoutLogView`: `previousSessionLoad(for:)` (last session's loads from `NeonBridgeService`, in lb) [OBS].
  - Legacy and text logger: `StrengthWorkoutStore.exerciseLiftHistory(itemID:name:before:limit: 20)` [OBS].
  - No reference → only the absolute and in-session rules apply.

**Body weight** (vs `WeightStore.latestEntry`, which is already the latest of `bodyWeightEntries`, i.e. excluding lean-mass entries [OBS], `days = max(1, calendar days between)`):
- unit slip (new ÷ last within ±5% of 2.2046 or 0.4536) → strong;
- `|Δ| ≥ 2 kg && |Δ|/days > 1.5 kg/day` → strong;
- `|Δ| ≥ 1.5 kg && 0.75 < |Δ|/days ≤ 1.5` → grey.

**Body fat** (vs the latest `BodyFatStore` entry): Δ ≥ 6 points within 14 days → strong; Δ ≥ 3 points within 14 days → grey.

**Measurements** (vs the latest value for the same site): ratio within ±5% of 2.54 or 0.3937 (inch/cm) → strong; change ≥ 20% within 30 days → strong; change ≥ 10% within 30 days → grey.

### Jev tie-breaker (grey flags only)
- Batch at most 5 flags, one noul question each. The state carries **relative facts computed in Swift**, not raw arithmetic for Jev to do (DOC jaggedness), and **no absolute body weight**:
```json
{
  "state": { "log": "strength workout" },
  "questions": {
    "flag_1": {
      "type": "noul",
      "instructions": {
        "task": "Is `entry` more likely a typing or unit mistake than a real result?",
        "entry": "Barbell bench press, 8 reps, about 25% heavier than their best set in the last 3 months; other sets today are about 20% lighter"
      },
      "criteria": {
        "true": "A typo, wrong unit, or number in the wrong field",
        "false": "A plausible real result, such as a personal record or normal day-to-day variation"
      }
    }
  }
}
```
- Body-metric entries are phrased the same way, for example "Body weight, up about 1.8% since yesterday, entered in the user's usual unit".
- **Show the grey flag** if `noulAtLeast(flag_k, 0.60)` [ASM].
- If Jev is inactive, times out (600 ms) or errors, grey flags are **not shown** and strong flags still are. This fails quiet, so no nagging.

### Hooks: confirm before saving, never block
| Save point | File / symbol [OBS] | Behaviour |
|---|---|---|
| JL program logger | `ProgramV2WorkoutLogView.saveButton` → `saveWorkout()` (`Views/ProgramV2WorkoutLogView.swift` ~L319/~L342) | On tap: evaluate `workoutSets` (≤ 600 ms incl. Jev; button spinner). With flags → alert "Double-check before saving" listing up to 3 ("Bench press set 2: 800 lb. Did you mean 80?"). Buttons: **Save anyway** (runs `saveWorkout()` unchanged) and **Edit**. No flags → save immediately. |
| Text / Coach workout | `WorkoutTextView.save()` (~L200), before `workoutStore.addTextWorkout` | Same alert. |
| Legacy logger | `WorkoutLogView.calculateBurn()` (~L613) | Same alert, optional. |
| Log weight | `LogWeightSheet` Save button (`Views/ProgressComponents.swift` ~L895, `onSave(selectedKg)`); caller `ContentView` ~L3901 | New defaulted param `previous: WeightEntry? = nil` (pass `weightStore.latestEntry`). With flags → alert "Save 95.0 kg?" (formatted in the user's unit) with **Save** / **Edit**. |
| Profile weight | `ContentView` `.editWeight` `WeightPickerSheet` closure (~L6174) | Same check before `weightStore.addEntry`. |
| Body fat | `LogBodyFatSheet` (`ProgressComponents.swift` ~L1549) | Same pattern. |
| Measurements | `MeasurementEditSheet` `onSave` (~L1725) | Same pattern, with the previous value for that site. |

- **Not hooked:** `SiriLoggingService.logWeight` (no UI to confirm in; never block), and imports or HealthKit sync.
- A reusable `View.plausibilityConfirmation(flags:onSave:onEdit:)` modifier keeps the alerts consistent.
  - Identifiers: `plausibility.alert`, `plausibility.saveAnyway`, `plausibility.edit`.
- **Savings mechanism:** none in LLM calls. This use is about **data quality**. It prevents bad sets and weights from skewing progress charts, suggested loads (`suggestedLoad(for:)` reuses last-session loads [OBS]) and Coach answers.
- **Cache:** fact text → response, 1 h.
- **Telemetry:** flags evaluated, strong/grey shown, Jev tie-breaks, **Edit** (likely true positive) vs **Save anyway** (`userOverride`), latency.
- **Privacy:** exercise names plus relative, rounded percentage facts. Body metrics are sent **only as relative change and unit words, never absolute values**. This is still health-adjacent, so it is in the info text and has its own toggle. Never photos.

### Tests: `calorietrackerTests/PlausibilityRulesTests.swift` (pure) + `JevPlausibilityTests.swift` (stubbed)
1. Unit slip: 176 lb vs history 80 kg, and 80 → 800.
2. Epley boundaries: 1.15, 1.35.
3. Absolute limits.
4. In-session 2×.
5. Weight rules across 1 day and 7 days, including unit slip.
6. Body fat.
7. Measurement cm/inch.
8. `greyFlagShownOnlyWhenJevSaysMistake` (noul 0.8 → shown, 0.3 → hidden).
9. `greyFlagHiddenOnTimeout`.
10. `strongFlagNeedsNoJevCall` (0 requests).
11. `stateHasNoAbsoluteBodyWeight` (the body contains no `kg`/`lb` number for weight flags).
12. `killSwitchNoFlagsAtAll` (everything off without a key; see open question 3).

---

## 8. Commit plan (for the coding agent)
1. **Router core + use 6 refactor:**
   - §1 (settings, actor, cache, telemetry, gates, settings UI incl. the Advanced AI section, Router stats view, backup exclusion, deleteAllData, key literals) + §2;
   - `JevRouterCoreTests`;
   - CI list;
   - Visual QA `test44SettingsAdvancedAIJevRouter` and `test45JevRouterStats` (seed stats through an injected telemetry instance, no network);
   - update `test43` if the card changed.
2. **Uses 1 + 3:**
   - §3 + §4;
   - `JevMealMatchTests`, `JevCoachIntentTests`;
   - Visual QA `test46FoodReviewSavedMatch` (`FoodResultView(..., savedMatch: .init(entryName: "Chicken burrito bowl"))`) and `test47CoachLocalAnswer`.
3. **Uses 2, 4, 5:**
   - §5–§7;
   - `JevTierRoutingTests`, `JevExerciseMatchTests`, `PlausibilityRulesTests`, `JevPlausibilityTests`;
   - Visual QA `test48PlausibilityAlert` (a pure view with preview flags).

If the Estimate Check already used 44+, take the next free numbers.

**CI** (`.github/workflows/ios-build.yml`, job `recon-math-tests`): append `-only-testing:calorietrackerTests/<Suite> \` for each new suite in the commit that adds it. Without this, CI only compiles them in visual-qa's `build-for-testing` [OBS].

---

## 9. Fact vs assumption summary
| Claim | Tag |
|---|---|
| API shapes, question types, 255-option cap, 2–10 score levels, `questions` as a map, no noul confidence, text-only, weak at numbers, price, rate limit, 64k context | DOC |
| 70–500 ms latency | DOC (vendor claim, unverified) |
| 401/403 auth errors with a `detail` object; no chat/messages endpoints | OBS (probe without a key) |
| Every hook point, symbol, store API, the CI job list, synchronized project groups, the backup-all-UserDefaults behaviour, no free-text parsing in `ProgramV2WorkoutLogView`, Gemma's no-tools prompt | OBS (`d856c2862`) |
| All budgets (800/700/600/500 ms), thresholds, top-N = 8/12, fuzzy cutoffs, circuit-breaker timings, in-flight cap, TTLs, plausibility ratios | ASM (tune with a real key and real logs) |
| Jev accuracy for meal matching, intent routing, exercise ids, complexity scoring, mistake detection | UNK (no benchmark for these domains) |
| Max questions per request, allowed option-key characters, Vercel gateway behaviour for score/noul and `/models` shape, whether `jev-latest` works through the gateway | UNK |
| API key format; access (waitlisted early access) | UNK / DOC |

## 10. Open questions
1. **Key access:** TypeSafe keys are waitlisted early access [DOC]. Is there a key, direct or Vercel AI Gateway? Gateway fallbacks can null the confidences, which disables most router decisions.
2. **Defaults:** ship the master router toggle off (proposed), and which uses start on? Tier routing is proposed off.
3. **Swift-only plausibility without a key:** the brief says "everything off without a key", but strong flags cost nothing. Allow them without a key?
4. **Thresholds** need tuning on real data: a small labelled set of typed meals, Coach messages and workout lines. Pin `jev-1.13.0` after tuning (docs recommend pinning).
5. **Coach handoffs:** is switching to the Home tab for `log_food` acceptable? Is the legacy `WorkoutTextView` (local diary) the right target for `log_sets`, given the JL program logger posts to Neon?
6. **Tier routing policy:** is a user-picked "cheaper model" acceptable? Should Apple Intelligence be a tier too? Is Gemma acceptable for simple Coach chat without tools?
7. **Privacy review:** plausibility sends relative health facts to a third party. Is that acceptable with its own toggle and info text?
8. **Non-English input:** Jev is best in English [DOC]. Gate on `NLLanguageRecognizer`, or trust the confidence gates?
9. **Stats placement:** Advanced AI is proposed. Or Food & AI?
