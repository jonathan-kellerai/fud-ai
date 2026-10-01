# AGENTS.md — JL Physical (jonathan-kellerai/fud-ai)

> PROPOSED. This file has not been committed. It needs Jonathan's approval before it is added to the repo root.
> Sources:
> - `/workspace/jeffrey-study/METHODS.md` (Jeffrey Emanuel's practices)
> - Tomas Vykruta's "Timeless constraints" (https://x.com/tvykruta/status/2105122130908074219, https://x.com/tvykruta/status/2105306637904863429)

# Timeless constraints (not a checklist)

When two principles collide, pick the one that cuts future cost in THIS codebase.

HARD RULE: refactor to the principle FIRST, then change behavior.

1. Separation of Concerns — one kind of work per part (UI / domain / persistence / infra). Root principle.
2. Encapsulation / Information Hiding — small stable contract; hide internals.
3. High Cohesion + Loose Coupling — change-together lives together; independents talk narrow.
4. DRY — one authoritative representation of each piece of *knowledge* (not every similar line). Avoid over-DRY.
5. KISS — simplest design that works; complexity is the long-term tax.
6. Single Responsibility — one reason to change.
7. Depend on Abstractions — policy doesn’t depend on details; both depend on contracts.
8. YAGNI — no speculative features, frameworks, or “later” hooks.
9. Composition over Inheritance — assemble pieces; don’t grow fragile hierarchies.
10. Open/Closed (with discipline) — extend at stable boundaries; only where change showed up twice.

Honorable: Law of Demeter · fail fast / illegal states unrepresentable · optimize for deletion · Unix do-one-thing + compose.

Treat as constraints. Violate slogans when judgment says so.

## Rule 0 — The human decides
- Jonathan's explicit instruction overrides everything in this file.
- The following never happen without his explicit, per-instance approval:
  - TestFlight or App Store submission (`testflight-deploy.yml`, Xcode Cloud archive)
  - store metadata pushes (`store-automation`)
  - deleting files or branches
  - force-push
  - changing secrets or signing material
  - production Neon writes beyond the documented bridge contract

## Rule 0.5 — Honesty beats green
- **Never weaken a gate to pass it.** That covers deleting or skipping tests, loosening assertions, adding `-only-testing` exclusions, `--no-verify`, `[skip ci]`, raising thresholds, or regenerating goldens or screenshots to match new output without review.
- A reported failure is a success. A hidden failure is the worst outcome.
- Never self-certify. "Done" means CI on this exact commit SHA is green and the reviewer has signed off. Cite the run URL and SHA.

## Roles
| Role | Who | Does | Never |
|---|---|---|---|
| Coder | Claude Code | plans, edits, writes tests, commits on a feature branch | merges to main or releases |
| Reviewer | Codex | fresh-eyes review of each PR against this file; cross-review with plan | edits the PR it reviews |
| Compiler / tester / screenshotter | GitHub Actions `iOS Build CI` | build, unit tests, Visual QA screenshots | — |
| Release approver | Jonathan | TestFlight / App Store | — |

There is no Xcode on the agent box. **Never claim something compiles, passes, or looks right without a CI run on that SHA.** Read results from the run logs and the `visual-qa-screenshots` and `visual-qa-xcresult` artifacts.

## Timeless constraints (Vykruta, adapted)
See **Timeless constraints (not a checklist)** above for the governing principles and hard rule. The app-specific applications and invariants below refine that guidance.

- Refactors and behavior changes never go in one diff.
- A refactor PR changes no behavior. Tests, goldens, and screenshots must be identical. If a step changes behavior, the refactor has a bug.

The principles:
1. **Separation of concerns.** Models/Stores own domain logic and persistence. Services own I/O (AI, HealthKit, the Neon bridge). Views only display.
2. **Encapsulation.** Read another module's state through its API.
3. **Cohesion and coupling.** One rule change should touch one module.
4. **DRY for knowledge, not for lines.** Grep before writing logic, and keep one home for each formula, threshold, unit conversion, or format. Don't abstract coincidental similarity.
5. **KISS and YAGNI.** No speculative flags, hooks, or frameworks.
6. **Single responsibility.** If you describe a type with "and", split it.
7. **Depend on contracts.** Domain code takes and returns plain values and never imports SwiftUI.
8. **Composition over inheritance.**
9. **Open/closed** only where change has already happened twice.
10. Also: Law of Demeter, fail fast, make illegal states unrepresentable, optimize for deletion.

Hard invariants:
- **One owning module per domain.** Workout logging lives in `StrengthWorkoutStore` and its models. Nutrition math, peptide math, the bridge client, and recon math each have one owner. Consolidate a scattered domain before you add to it.
- **Never duplicate logic.** On the second use of some logic:
  1. Move it to the owner.
  2. Switch the original callers, with tests green and no behavior change.
  3. Then build the new use.
- **No business logic in SwiftUI views.** Views never compute calories, volume, 1RM, rest durations, or classifications.
- **Gates, not promises.** A rule that matters is enforced by a test, a CI step, or a lint, not by this file alone.

## Workflow
1. **Plan before code.**
   - Any change bigger than a bug fix starts as `docs/plans/<topic>.md`.
   - The plan states the problem, the evidence (Alexandria evidence ids, Tier A or B, for UX claims), the acceptance criteria, the tests, and any screenshots expected.
   - Codex reviews the plan in a fresh session until a round yields only marginal changes.
2. **Break the work into small, self-contained tasks.** Each task carries its own tests, and the task graph has no cycles.
3. **Refactor-first PRs**, then behavior PRs (see **Timeless constraints (not a checklist)** above).
4. **Code first, batch-verify.**
   - Push early. CI on the branch is the build.
   - On red, fix **compile errors first**: a partial pass before an early abort is a lying green.
   - A task is closed only by a green run on its SHA. Cite the run URL.
5. **Review loop.** After each PR, Codex runs a fresh-eyes review. A cross-review against the plan and a random-exploration bug hunt also run regularly. Stop when all three come back clean.
6. **UI polish** happens only on working features.
   - Use the Visual QA screenshots on the Pro and small devices.
   - Check the accessibility matrix: Dynamic Type up to AX5, VoiceOver labels and identifiers, Reduce Motion, 44pt hit targets, light and dark mode.
7. **Performance.** No optimization without a measured hotspot (an Instruments trace or a CI timing). Make one change at a time and prove the behavior is unchanged.

## Testing
- Prefer real inputs over mocks. A new `Mock`/`Fake`/`Stub` type needs a written justification.
- Every behavior change ships tests for the happy path, edge cases, and errors, and is added to the `-only-testing` list in `ios-build.yml` if needed. **Never remove entries from that list.**
- Golden screenshots or outputs change only in a PR labelled `goldens-update`, with a before/after table that a reviewer approves.
- Neon bridge: contract tests follow `docs/NEON_TRAINING_BRIDGE.md`. The health check is `GET https://jl-workout-ingest.vercel.app/api/bridge/health`. No writes to production data from tests.

## Code hygiene
- No script-based mass edits or codemods. Edit deliberately.
- No file proliferation (`FooV2.swift`, `FooNew.swift`). Change the file in place.
- No backwards-compat shims for code that has no external users.
- New code must be Swift 6 concurrency clean: no new `@unchecked Sendable` or `nonisolated(unsafe)` without a comment explaining why.
- Treat compiler warnings as errors in new code.
- God files (e.g. `ContentView.swift`, about 338 KB on main) only shrink. Extract code isomorphically, never add new features into them.

## Git
- Branches are `feat/*`, `integ/*`, and `cursor/*`. Open PRs against main.
- No destructive git: no `reset --hard`, no force-push, no history rewrite on shared branches.
- Commit messages say *why*, and name the one concern touched.
- At the end of a session: commit, push, update the plan or task status, and write a handoff note with the CI run URLs.
