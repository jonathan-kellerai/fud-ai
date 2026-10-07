# Build 69: AI sign-in, connection tests and a request log

Owner: Claude Code (coder). Reviewer: Codex. Branch: `integ/build-69` (base build 67, `7f13e35cd`).

## Problem

Jonathan (verbatim): "AI needs to support OAuth login, testing and error logs for troubleshooting issues with meal identification requests".

Today More > AI Providers only takes a pasted API key. When a meal photo fails, the user sees a friendly message, and nothing on the device records which provider and model answered, the HTTP status, or the body the provider sent back. Nobody can tell a bad key from a retired model from an unparseable reply.

## Evidence

All of it comes from primary vendor and standards documents (Tier A). No Alexandria run was needed. The full table is in `/workspace/r69/OAUTH_FACTS.md`.

- OpenRouter OAuth PKCE: https://openrouter.ai/docs/guides/overview/auth/oauth (fetched 2026-10-07).
  - `GET https://openrouter.ai/auth?callback_url=…&code_challenge=…&code_challenge_method=S256&state=…`
  - `state` comes back unchanged on the callback. It is not returned on deny or in headless mode.
  - Headless (display-code) mode: omit `callback_url` and add `key_label`. The page then shows the code for the user to paste, and PKCE is required.
  - Exchange: `POST https://openrouter.ai/api/v1/auth/keys` with `{code, code_verifier, code_challenge_method}` returns `{key}`.
  - Errors: 400 invalid method, 403 invalid code/verifier or expired (codes are single-use and live 10 min).
- RFC 7636 §4.1–4.2 and Appendix B: the verifier is 43–128 unreserved characters, and `S256` = BASE64URL(SHA256(ASCII(verifier))) without padding. The Appendix B vector is the unit test.
- Apple: `ASWebAuthenticationSession(url:callback:completionHandler:)` with `.customScheme` (iOS 17.4+; the app targets 17.6). `prefersEphemeralWebBrowserSession` and a presentation context provider are required.
- OpenAI, xAI, Anthropic and Gemini offer no app OAuth this app can legitimately use (see OAUTH_FACTS). They stay on API keys, with a one-line footnote. **Nothing is faked.**

## Design

### Separation of concerns

| Concern | Owner (file) | Kind |
|---|---|---|
| PKCE, auth URL, callback parsing, exchange request/response, pasted-code cleanup | `Models/OpenRouterOAuth.swift` | pure |
| Browser sign-in, random bytes, exchange I/O, storing/deleting the key | `Services/OpenRouterSignInService.swift` | I/O |
| "This OpenRouter key came from sign-in" flag | `AIProviderSettings` (`Models/AIProvider.swift`) | settings owner |
| Log entry value + kinds | `Models/AIRequestLogEntry.swift` | pure |
| Secret redaction | `Models/AIRequestLogRedactor.swift` | pure |
| Per-request trace (attempts, HTTP outcome, parsed flag) + task-local scope | `Services/AIRequestTrace.swift` | domain |
| Persistence + caps (200 entries, 512 KB, oldest dropped) | `Stores/AIRequestLogStore.swift` | persistence |
| Test connection / Test meal photo through the real paths | `Services/AIDiagnostics.swift` | service |
| Views | `Views/AIProviderAPIKeyRow.swift`, `Views/AIDiagnosticsSection.swift`, `Views/AIRequestLogViews.swift` | display only |

### Single choke point for the log

- `GeminiService.makeRequest` is the one HTTP function that every provider call (Gemini, OpenAI-compatible, Anthropic) goes through. It reports each HTTP outcome to the task-local `AIRequestTrace.current`: status, latency, and the error body (or, for a 200, a body snippet kept only in case parsing fails). When no trace is active (workouts, goals, coach and so on), it does nothing.
- `routed` (the one AI pipeline) marks each provider attempt (`beginAttempt(provider:model:)`). That covers the hosted, primary, fallback and no-key cases.
- The four meal-identification entry points open the scope: `analyzeTextInput`, `autoAnalyze`, and both `analyzeFood` overloads. The scope wraps the parse, so `parsed` is true only when a `FoodAnalysis` came back.
- Scopes don't nest. An inner scope joins the outer one, which lets the diagnostics "Test meal photo" scope own the entry it shows.
- Entries are redacted when created, before they are stored. The redactor covers:
  - `Authorization` / `x-api-key` / `X-goog-api-key` header lines and `Bearer …`
  - `sk-…`, `sk-or-…`, `sk-ant-…`, `xai-…` and `AIza…` keys
  - `key=`, `api_key=`, `apikey=`, `token=`, `access_token=` and `code_verifier=` query params
  - JSON string fields such as `"key"`, `"api_key"`, `"token"`, `"authorization"` and `"code_verifier"`
- The log lives in a file at `Application Support/ai-request-log.json`. It is never uploaded and never part of cloud backup.

### OpenRouter sign-in

- Callback: `fudai://openrouter-callback`. The `fudai` scheme is already registered in `Info.plist`, so the plist doesn't change. Both existing `onOpenURL` handlers ignore this host.
- The verifier is 32 bytes from `SecRandomCopyBytes`, base64url-encoded (43 chars). The challenge is the CryptoKit SHA-256 of the verifier, base64url-encoded. `state` is another 16 random bytes and is checked on the callback.
- The session uses `prefersEphemeralWebBrowserSession = false` and anchors on the key window.
- The returned key goes through `AIProviderSettings.setAPIKey(_, for: .openrouter)`, the same Keychain item (`apikey_OpenRouter`) the request path already reads. The request path is unchanged.
- UI states:
  - Signed out: a "Sign in with OpenRouter" button, the API key field (manual keys still work), and "Paste code".
  - Signed in: "Signed in with OpenRouter" plus a Sign out button, which deletes the Keychain item and clears the flag.
- Fallback: "Paste code" opens the headless URL (with `key_label`) in Safari, takes the pasted code (or a pasted callback URL), and exchanges it with the same verifier.

### Diagnostics

- **Test connection** sends a minimal plain-text prompt ("Reply with OK") through `AIRouteEnvironment.current.dispatch` with the Photo & Text config. That is the real provider client and the real `makeRequest`.
- **Test meal photo** runs the bundled synthetic `sample_meal_test` image through `GeminiService.analyzeFood(image:)`. That is the real meal path, including the router and fallback.
- Both show:
  - the latency (ms), provider and model, read from the trace
  - on success, the parsed foods and kcal
  - on error, the status and the redacted error body
- Both are written to the request log as kinds `connectionTest` and `sampleMealPhoto`.
- Error text uses `IronTheme.bloodText` or the secondary text color. Blood red (`IronTheme.blood`) is used only as a fill or stroke, never as text.

## Acceptance criteria

1. Choosing OpenRouter shows sign-in. Choosing xAI, OpenAI, Anthropic or Gemini shows the key field exactly as before, plus the footnote "Sign-in isn't offered by <provider>; use an API key".
2. A successful sign-in stores the key where `AIProviderSettings.apiKey(for: .openrouter)` reads it. Sign out removes it.
3. Every meal photo and text food request made through GeminiService adds one entry per provider attempt to the log, with timestamp, provider, model, kind, HTTP status, latency, redacted error body and parsed yes/no.
4. The log keeps at most 200 entries and 512 KB, dropping the oldest first, and survives relaunch.
5. The log screen lists entries newest first with a status chip. The detail screen has Copy and ShareLink. Clear log empties it.
6. The refactor commit is pixel-identical. Shot 30 and shot 43 don't change in that commit.

## Tests (Swift Testing, added to `ios-build.yml`: -only-testing, the diagnostic grep, and the passing-suite loop)

- `OpenRouterOAuthTests`: the RFC 7636 Appendix B vector, verifier length and alphabet, auth URL (callback and headless), callback parsing (code / error / state mismatch / missing code / wrong host), the exchange request body, response parsing (key / error / non-200), and pasted-code cleanup.
- `AIRequestLogRedactorTests`: each key pattern, headers, Bearer, query params, JSON fields, non-secret text untouched, truncation.
- `AIRequestLogStoreTests`: cap by count, cap by bytes, oldest first out, persistence round trip, clear, newest-first ordering, corrupt file → empty.
- `AIRequestTraceTests`: the parsed flag (success → last attempt parsed, failure → none), fallback produces two entries, a no-HTTP attempt (on-device/hosted), errors before any attempt, nested scopes join the outer scope, and entries are redacted.

These also build and run on Linux in a throwaway SwiftPM harness (`/tmp/r69-harness`, with a SHA-256 shim standing in for CryptoKit). CI is still the only proof for iOS.

## Visual QA (new file `VisualQASnapshotTests+AIDiagnostics.swift`, existing `capture`/`eachSize`, default + axL)

- 110 `ai-providers-openrouter-signed-out`
- 111 `ai-providers-openrouter-signed-in`
- 112 `ai-providers-xai-key-only`
- 113 `ai-test-result-success`
- 114 `ai-test-result-error`
- 115 `ai-request-log-list`
- 116 `ai-request-log-detail`

All of them use synthetic data at `VisualQAFixtures.referenceNow`, make no network calls, and write their logs to a temp file. The commit is labelled `[goldens-update]`.

## Task graph (one concern per commit)

1. docs: this plan
2. refactor: extract the Photo & Text API key row from `ContentView` into `AIProviderAPIKeyRow` (pure move, no pixels)
3. behavior: request log model, redaction and store (+ tests)
4. behavior: record meal identification requests at the HTTP choke point (+ trace tests); depends on 3
5. behavior: OpenRouter PKCE sign-in (+ OAuth tests); depends on 2
6. behavior: Test connection, Test meal photo and the request log screens; depends on 3, 4
7. ci: add the new suites to ios-build.yml; depends on 3–5
8. test: VQA shots [goldens-update]; depends on 5, 6

## Out of scope / deferred

- OAuth for OpenAI (needs a loopback redirect), Gemini (needs a GCP iOS OAuth client from Jonathan), xAI and Anthropic (not offered or prohibited).
- Logging non-meal AI calls (coach, workouts, goals). Adding one would mean opening a scope at that entry point.
- The OpenRouter key-hash deep links to logs and settings.
