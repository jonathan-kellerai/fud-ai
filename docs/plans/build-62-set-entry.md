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
