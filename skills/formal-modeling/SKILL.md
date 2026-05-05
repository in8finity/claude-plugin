---
name: formal-modeling
description: >
  Write, run, and interpret Alloy 6 formal models for software systems, business processes, and skill/workflow design.
  Use this skill whenever the user asks to model, verify, or prove properties about state machines, lifecycle flows,
  data invariants, API contracts, integration boundaries, permission systems, or business rules. Also trigger when the
  user mentions Alloy, formal methods, formal verification, model checking, counterexample, temporal logic, or
  wants to "prove" something about their system. Use even for seemingly simple state-machine questions — the solver
  catches edge cases that humans miss. This skill applies to any domain: SaaS, e-commerce, fintech, DevOps, or business process design.
---

# Formal Modeling with Alloy 6

You help users write Alloy 6 models that verify real-world software and business logic, then run them through a
local Java (or Docker fallback) pipeline and interpret the results. Formal modeling catches design bugs — race
conditions, invariant violations, impossible states — before they become production incidents.

**You drive the process.** Don't wait for the user to ask "what's next" — proactively push through
each step, present decisions with clear options, explain trade-offs, and keep momentum. After each
step, summarize what was done, show the result, and present the next decision the user needs to make.
The user's role is to make decisions; your role is to execute steps and surface decision points.

## When to reach for a formal model

Formal modeling pays off when the system has **states, transitions, and invariants that must hold across all
possible interleavings** — not just the happy path. Typical triggers:

| Signal in conversation | What to model |
|------------------------|---------------|
| "users can be in state X or Y" | State machine with transitions |
| "this should never happen" | Safety assertion (`check`) |
| "what if they cancel and resubscribe" | Lifecycle scenario with `run` |
| "the DB has a unique constraint but..." | Data invariant across operations |
| "we need to integrate system A with system B" | Cross-system contract |
| "the webhook might arrive before/after..." | Temporal ordering with `var sig` |
| "how does the cache stay consistent" | Cache-coherence invariant |
| "the permission model allows..." | Access-control policy verification |
| "the workflow goes step1 → step2 → ..." | Business process state machine |
| "which roles see which fields in which states" | Role×State×Field access matrix |
| "the email has an approve button but..." | CTA validity checking |
| "who gets notified when X happens" | Notification recipient sets |
| "the pipeline has steps that depend on..." | Pipeline DAG with dependency assertions |
| "the index might be stale after step X" | Artifact versioning + freshness guards |
| "how do we know the verification actually checked" | Proof of work (evidence requirements) |
| "orders over $10k need dual approval" | Equivalence classes (range partitioning into behavior-triggering tiers) |
| "different SLA tiers get different..." | Equivalence classes (replace continuous values with discrete behavior classes) |

If the user describes a workflow, lifecycle, or set of rules with more than 3 states or 2 interacting
entities, suggest formal modeling even if they didn't ask for it. UX-layer verification (field access,
notification CTAs, role-based visibility) and AI pipeline verification (step dependencies, stale
caches, hollow verification) are especially high-value — these bugs are hard to catch with unit
tests because they require checking all combinations exhaustively.

## Modeling styles: when to use what

Each style serves a different verification need. Choosing the wrong style wastes effort —
a temporal model for a permission matrix is overkill, and a static model for a lifecycle
flow will miss ordering bugs.

### 1. Static (snapshot) models

**Best for:** Data invariants, configuration validity, permission matrices, pre/post-condition pairs.

**Strengths:** Simple to write (30-50 lines), fast to run, easy to interpret. Alloy generates
concrete instances showing exactly what satisfies or violates the constraints. Dafny proves
the same properties for ALL inputs (unbounded), but you lose the visual counterexamples.

**Weaknesses:** Cannot express "X happens before Y" or "eventually reaches state Z." If the
problem involves ordering or reachability, a static model will silently miss those bugs.

**Alloy advantage:** Instance generation — `run` shows a concrete configuration that satisfies
the constraints. Useful for showing stakeholders "here's what a valid state looks like."

**Dafny advantage:** Unbounded proofs — proves invariants hold for any number of entities,
not just within scope N. Port to Dafny when confidence beyond bounded scope matters.

Good for:
- Data invariants (uniqueness, referential integrity, mutual exclusion)
- Configuration validity
- Permission matrices
- Pre/post-condition pairs ("before upgrade" + "after upgrade")

```alloy
sig User { deleted: one Bool }
sig Subscription { owner: one User, status: one SubStatus, obsolete: one Bool }

-- Invariant: no live subscription for a deleted user
fact NoLiveSubForDeletedUser {
  all u: User | u.deleted = True =>
    no s: Subscription | s.owner = u and s.obsolete = False
}

-- Verify the invariant holds after re-registration
check MyAssertion { ... } for 6
-- Find a concrete example satisfying a scenario
run MyScenario { ... } for 4
```

### 2. Temporal (trace) models — Alloy 6

**Best for:** State machines, protocol verification, lifecycle flows, concurrent actors, liveness properties.

**Strengths:** Alloy 6's built-in `always`/`eventually`/`until` operators make temporal properties
natural to express. The solver explores all possible interleavings within scope — finds race
conditions and deadlocks that unit tests miss.

**Weaknesses:** Larger models, slower to run (combinatorial explosion with scope). Temporal Alloy
models are the hardest to port to Dafny — you must manually encode traces as sequences and
write inductive proofs instead of using temporal operators.

**Alloy advantage:** Native temporal logic, trace visualization (states shown sequentially with
change markers), counterexample traces that show the exact sequence of events leading to a violation.

**Dafny advantage:** If ported, proofs are unbounded — proves the property holds for traces of
ANY length, not just within N steps. But the porting cost is high (encode `always` as `forall i`,
`eventually` as `exists i`, frame conditions become explicit `ensures`).

**When Alloy is clearly better:** Exploration phase — "show me a trace where the system deadlocks."
**When Dafny is worth the effort:** The model stabilizes and you need CI-grade guarantees.

Model sequences of state transitions over time. Good for:
- State machine correctness (reachability, deadlock freedom)
- Protocol verification (handshake, retry, timeout)
- Lifecycle flows with concurrent actors
- "Eventually" and "always" properties

```alloy
sig User {}
var sig ActiveUser  in User {}   -- mutable set: who is alive
var sig DeletedUser in User {}

sig Sub {
  txn_id: one TxId,
  var owner  : lone User,       -- mutable field (var on field, not standalone sig)
  var status : lone SubStatus
}
var sig ExistingSub in Sub {}
var sig ObsoleteSub in Sub {}

fact Init { no ActiveUser and no DeletedUser and no ExistingSub
  and all s: Sub | no s.owner and no s.status }

-- Frame helpers: group unchanged state
pred frameUsers { ActiveUser' = ActiveUser and DeletedUser' = DeletedUser }
pred frameSubs  { ExistingSub' = ExistingSub and ObsoleteSub' = ObsoleteSub
                  and owner' = owner and status' = status }  -- owner/status are var fields
pred stutter    { frameUsers and frameSubs }

pred register[u: User] {
  u not in ActiveUser + DeletedUser
  ActiveUser' = ActiveUser + u
  DeletedUser' = DeletedUser
  frameSubs                         -- subs unchanged
}
pred subscribe[u: User, s: Sub] {
  u in ActiveUser and s not in ExistingSub
  ExistingSub' = ExistingSub + s
  ObsoleteSub' = ObsoleteSub
  owner'  = owner  ++ (s -> u)     -- ++ for surgical relation update
  status' = status ++ (s -> Active)
  frameUsers                        -- users unchanged
}

fact Transitions { always (
  stutter
  or (some u: User | register[u])
  or (some u: User, s: Sub | subscribe[u, s])
  or (some u: User | softDelete[u])
)}

-- Safety: deleted user never owns a live sub
check NoZombieSub { always (all u: DeletedUser |
  no s: ExistingSub - ObsoleteSub | owner[s] = u) } for 5
-- Liveness: find the full lifecycle trace (nested eventually = ordered steps)
run FullLifecycle {
  some u: User, s: Sub |
    eventually (u in ActiveUser                           -- step 1: register
    and eventually (s in ExistingSub and owner[s] = u     -- step 2: subscribe
    and eventually (u in DeletedUser                      -- step 3: account deleted
    and s in ObsoleteSub)))
} for exactly 1 User, exactly 1 Sub, exactly 1 TxId, 8 steps
```

### 3. UX / access-control verification (static)

**Best for:** Role-based permissions, field visibility, notification CTAs, access matrices.

**Strengths:** Exhaustively checks every role x state x field combination — catches "dead button"
bugs where a CTA appears in an email but the user can't actually perform that action. Alloy's
relational algebra is ideal here: `canWrite[r, t, f]` reads naturally.

**Weaknesses:** Combinatorial — models grow with the number of roles, states, and fields. Not
suited for temporal properties (use style 2 for "who can do what in which order").

**Alloy advantage:** Relational modeling is Alloy's sweet spot. A role x state x field predicate
in Alloy is 5 lines; the same in Dafny requires manually encoding each combination. Counterexamples
show the exact role/state/field triple that violates the policy.

**Dafny advantage:** Minimal for this style. The relational algebra doesn't translate well, and
the visual counterexamples matter more than unbounded proofs (permission matrices are finite).

**Recommendation:** Keep UX models in Alloy. The exploration value (counterexample = dead button)
far outweighs any benefit from unbounded Dafny proofs.

Model the full permission and notification layer as a static snapshot. Verifies that every
role × state × field combination behaves correctly, and that notification CTAs are valid.

```alloy
-- Role × State × Field access predicate
pred canWrite[r: Role, t: Task, f: Field] {
  r = Admin
  or (r = Manager and (editable[t.state] or (t.state = Active and f in activeAllowed)))
  or (r = Owner and f not in internalOnly and editable[t.state])
  -- Viewer: no branch → always false
}

-- CTA validity: button in email → action available?
pred ctaValid[c: Cta, r: Role, t: Task] {
  (c = CtaView)
  or (c = CtaApprove and t_approve[r, t])
}

-- THE KEY CHECK: every CTA in every notification is valid
assert AllCtasValid {
  all tmpl: Template, r: Role, t: Task |
    t.state in triggerStates[tmpl]
    implies all c: templateCtasFor[tmpl, r, t] | ctaValid[c, r, t]
}
check AllCtasValid for 6  -- counterexample = dead button bug
```

See `references/ux-verification-example.als` for a complete 300-line example covering roles,
field access, transitions, notifications, CTAs, and gap assertions.

## Writing a model: two modes

**Guided mode** (default) — follow steps 0-7 below. Best for users new to formal modeling or
when the domain is complex enough to benefit from systematic pattern selection and example loading.

**Free mode** — write the model directly from the problem description, optionally consulting
patterns or examples. Useful when the modeler already knows Alloy well or the problem is simple
enough to model from first principles. Skip steps 1-7; go straight to writing.

**Both modes converge at step 8** (boundary review). The downstream pipeline (run → interpret →
reconcile → iterate) is identical. The quality gate at step 8 ensures the model has:
- At least one `fact` (invariants)
- At least one `assert` + `check` (safety properties)
- At least one `run` (scenarios)

Guided mode also expects a `module` declaration and a documentation block comment. Free mode
doesn't require these — the model just needs to be structurally valid for the solver.

### Guided mode: step by step

At each step, present what you did and what you need from the user. Don't proceed silently.

0. **Clarify the prompt** — Assess prompt quality. **Do not proceed to modeling until the prompt
   has entities, states, and at least one rule.** If vague, block and ask:
   *"I need a few things before I can model this: What are the states? Who are the actors?
   What should never happen? Can you describe a concrete scenario you're worried about?"*
   If clear, confirm: *"I see N entities, M states, and these rules: ... Does this match?"*
1. **Identify entities** — List what you found: *"I identified these entities: User, Subscription,
   Plan, PlatformId. Am I missing anything?"*
2. **Identify states** — Present the enum: *"Status values: Pending, Active, Inactive, Canceled,
   Disabled. Are there others? Is 'Suspended' a real state or did I invent it?"*
3. **Identify relations** — Show the field map: *"User owns Subscription, Subscription has status
   and plan. Is the owner relation one-to-one or one-to-many?"*

   After identifying entities/states/relations, **select patterns and examples before writing.
   Do not write the model until at least one domain-specific pattern is selected:**
   - Consult `references/alloy-patterns.reference` and select at least one domain-specific pattern
     (not just Basics/Verification — pick from Structural, Temporal, UxAccess, DataConvert,
     or Pipeline based on the problem domain). **Block if no domain pattern selected.**
     *"For this problem I'm using patterns:
     Bool helper (#1), soft-delete lifecycle (#8), and equivalence classes (#47)."*
   - Load at most 2-3 reference examples matching the chosen style. Don't load all examples —
     pick the ones relevant to the modeling style (static → static-model-example.als,
     temporal → temporal-model-example.als, UX → ux-verification-example.als).

4. **Write invariants** — Explain each fact: *"I'm adding 3 invariants: (1) deleted user has no
   live subs, (2) at most one live record per platform ID, (3) only published plans can be active.
   Do these match your business rules?"*
5. **Write scenarios** — Propose run commands: *"I want to verify these scenarios: happy path
   (upgrade plan), cancellation, and single-platform constraint. Should I add any edge cases?"*
6. **Write safety properties** — Explain what each check proves: *"These 3 assertions verify:
   no zombie subs after delete, obsolete records can't be active, upgrade preserves uniqueness.
   What else should never happen?"*
7. **Choose modeling style** — The style must match the problem. Don't proceed with the wrong one:
   - If the problem needs temporal ordering or liveness → **must use Temporal**.
     *"Your problem involves ordering (X before Y) and liveness (eventually reaches state Z).
     This needs a temporal model with `var sig` and `always`/`eventually`."*
   - If the problem needs role × state × field access or CTA checking → **must use UxLayer**.
     *"Your problem is about who can see/edit what in which state. This needs a UX/access
     control model with a `canWrite` predicate, not a state machine."*
   - Otherwise → **Static** is the default.
   *"I'm choosing [style] because [reason]. Want me to proceed, or does this need a different
   approach?"*
8. **Review model boundaries** — This is the quality gate. Before running, verify two things:

   **First, check minimum quality.** The model cannot proceed to the solver without these.
   Block and fix if any are missing:
   - Has at least one `fact` (invariants that constrain the system)
   - Has at least one `assert` + `check` (safety properties to verify)
   - Has at least one `run` (scenarios to explore)
   If in guided mode, also require: `module` declaration and doc comment at top.
   *"Before I run this, I'm checking the model meets minimum quality: [facts: yes,
   assertions: yes, scenarios: yes]. All gates pass."* — or — *"The model is missing
   run commands. I'll add scenario X before proceeding."*

   **Second, present the boundary table** and ask for sign-off:
   *"Here's what the model covers and what I left out. For each element I explain
   what we gain or lose. Please review and tell me if you want to add or remove anything."*

   **Suggest inclusions** — elements the user didn't mention but that affect correctness:
   - "Your state machine has 5 states, but the code also has a `Suspended` state — should we model it?
     If excluded, the model can't detect transitions into/out of Suspended."
   - "You mentioned roles Owner and Admin, but there's also a Viewer role with restricted access.
     Including it lets us verify read-access isolation; excluding it means we assume Viewer is safe."
   - "The workflow has a retry mechanism with exponential backoff. Including retry adds a transition
     loop; excluding it means the model assumes every operation succeeds on first attempt."

   **Suggest exclusions** — elements that add complexity without verification value:
   - "The notification template system has 15 templates but only 3 carry action CTAs. We can model
     just the 3 CTA-bearing templates and stub the rest as informational. This cuts scope by 80%
     while still verifying every actionable button."
   - "Timezone conversion is complex but can be axiomatized (see pattern 26) instead of implemented.
     The model proves properties about the conversion without computing actual hours."
   - "The audit log is append-only and has no effect on state transitions. Excluding it loses nothing."

   **Explain the difference** — for each boundary decision, state what changes:
   - What assertions become possible or impossible
   - What counterexamples the model can or can no longer find
   - What scenarios become reachable or unreachable
   - Whether the exclusion is safe (no false confidence) or risky (hides real bugs)

   Use gap assertions (pattern 40) to document risky exclusions — write an assertion you *know* would
   fail if the excluded element were added, and comment it as a known boundary.

   **Output format** — present the boundary analysis as a table:
   ```
   | Element          | Decision | Impact if included                        | Impact if excluded                    |
   |------------------|----------|-------------------------------------------|---------------------------------------|
   | Suspended state  | Include  | Can verify suspend/resume transitions     | —                                     |
   | Viewer role      | Include  | Can verify read isolation                 | —                                     |
   | Retry mechanism  | Exclude  | Adds transition loop + backoff states     | Model assumes first-attempt success   |
   | Audit log        | Exclude  | Append-only, no state effect              | Safe — no verification value lost     |
   | TZ conversion    | Stub     | Axiomatize (pattern 26) instead of impl   | Proves properties without clock math  |
   | 12 info templates| Exclude  | Only 3 carry CTAs; stub rest              | Cuts scope 80%, CTA checks preserved  |
   ```
   The user can then sign off on the boundaries before you run the model.

8b. **Abstract-boundary primitive check** — When an invariant in the model is enforced at
   runtime by a primitive that lives BELOW the model — at a database, kernel, network, or
   external-service boundary — the abstract model collapses what the implementation does in
   multiple steps into a single atomic predicate. The bug class this hides:
   *the primitive the boundary actually exposes is weaker than the precondition the model
   demands.* The model passes; production violates the invariant.

   **When to write a primitive-strength sub-model** — at least one of these is true:
   - A model precondition is enforced by an external storage operation (CAS, transaction,
     foreign-key constraint, conditional write).
   - A model precondition is enforced by a kernel/network primitive (lock acquisition,
     socket auth, replay-protection token).
   - The implementation does **two or more reads** of the boundary state for one logical
     operation, and the primitive's success guarantee is on identity (pointer/version),
     not on the predicate the model checks.
   - The model uses a single-step transition like `commitClaim` whose precondition refers
     to mutable state held outside the process.

   **When to skip** — the model's invariant is purely about in-process state, OR the caller
   does exactly one atomic boundary call and trusts its return value, OR the boundary is
   already known-strong (e.g. a serializable transaction wrapping the entire critical section).

   **What to write.** A short standalone `.als` file (≈80 lines) with five named ingredients —
   see `references/primitive-strength-template.als` for the parameterized blank, and
   `references/primitive-strength-example.als` for a fully-runnable worked example
   (TOCTOU on a CAS-protected head — the bug pattern from hashharness-pm 0.6.4):

   1. **Boundary state** — what the boundary tracks (head pointer, row version, lock state).
   2. **Primitive** — what the boundary actually guarantees, stated literally. Not what you
      wished for. Not what the docs imply. *What the wire/syscall returns.*
   3. **Caller pattern** — every read your code performs, in order. If the caller does
      N>1 reads, model all N reads explicitly.
   4. **Adversary** — between any two caller steps, what other actors can do. Default = anything.
      Understating the adversary makes the assertion artificially pass — be honest.
   5. **Strength assertion** — `caller-pattern-with-primitive ⟹ abstract-precondition`.
      Counterexample = primitive too weak for this caller. Holds = wiring is sound.

   **Read the verdict like this:**
   - **Buggy → counterexample, fixed → holds.** Most useful outcome. The fix you proposed
     (e.g. thread the first read through to CAS) closes the gap; the model proves it.
     Apply the fix, re-reconcile against code in step 9b.
   - **Both fail.** The primitive is too weak even when used correctly. The fix has to move
     to the boundary itself (e.g. switch to a CAS-with-status-check, or wrap in a transaction).
   - **Both hold.** Either the primitive is already strong enough (good — explicitly note it
     in the boundary review), OR your adversary is too tame. Re-examine ingredient #4: can
     other writers really not interleave between your reads? If the adversary is in fact tame
     under operational constraints (single writer, lock held), document that in the boundary
     review as a load-bearing assumption.

   Persist the strength sub-model alongside the main model (e.g. `system-models/{domain}-strength.als`).
   It feeds into reconciliation (step 9b): if buggy fails, the source artifact's call pattern
   is the FixSource verdict; if both fail, the boundary's primitive is the FixSource verdict.

8c. **Retry-loop fairness check** — When the protocol contains a retry path that re-evaluates
   candidate selection on each iteration, single-step assertions (`always all t | lone (Committed
   & task.t)`) cannot observe the loop. They prove safety at every state, including states where
   N>0 candidates exist and zero progress is being made. The bug class this hides:
   *the candidate-selection function is shared across actors and deterministic, so two workers
   compute identical results and collide indefinitely.*

   **When to write a retry-loop sub-model** — at least one of these is true:
   - The protocol has a retry loop with a `--max-retries` style bound, after which a worker
     gives up silently.
   - Candidate selection (which task to attempt next) is determined by a sort key that's
     visible to all workers (priority, age, ID).
   - Multiple actors poll the same store and race for the same resources.
   - The proof obligation is *liveness* ("eventually one worker claims something"), not
     just safety ("at most one worker holds a claim").

   **When to skip** — the protocol is single-actor, OR the selection function is intentionally
   randomized, OR fairness is enforced by an external scheduler (e.g. the queue server itself
   distributes tasks rather than letting workers self-select).

   **What to write.** A short standalone `.als` file modeling the candidate-selection
   primitive — see `references/retry-loop-example.als` for a fully-runnable worked example
   (deterministic collision via shared `(context_priority, created_at)` sort, the bug pattern
   from hashharness-pm 0.6.4). Five named ingredients, paralleling the primitive-strength model:

   1. **Sort key** — the *actual* production sort, not "some total order." If your code sorts
      by `(priority, created_at)`, the model sorts by `(priority, created_at)`. The bug lives
      in the specific tuple, not in abstract orderings.
   2. **Selection function** — `selectNext(pool, skipSet)` returns the first-by-sort element
      of `pool − skipSet`. Model it as a constraint, not a lookup.
   3. **Candidate pool** — what each worker sees as runnable. Default = the same view shared
      by all workers, modeling pollers reading the same store at the same wall clock.
   4. **Buggy caller** — empty or non-updating skip-set. Models the "re-list, re-sort,
      re-pick" loop that re-selects the contested task on every retry.
   5. **Fixed caller** — skip-set captures CAS-loss history. Modeled as a single
      post-resolution snapshot: W2.skipSet = {W1.selected}.

   **Read the verdict like this:**
   - **Buggy → counterexample, fixed → holds.** The fix you proposed (track skip-set across
     iterations) closes the gap; concrete counterexample shows the collision pattern.
     Apply the fix, re-reconcile against code in step 9b.
   - **Buggy holds.** Either your selection function is non-deterministic (rare) or your
     adversary model is too tame. Re-examine the candidate pool — are workers really reading
     the same view at the same time? In production, yes.
   - **Fixed fails.** The proposed fix isn't sufficient. Common cause: the skip-set is
     scoped to one iteration but cleared between calls, so a multi-call worker re-picks
     the same task on a fresh invocation. Either widen the skip-set's lifetime or push
     fairness to the server (priority-aware dispatch).

   **Tier guidance.** This is the *medium* tier from the proposer's three-tier framing:
   model the actual sort key and produce a concrete counterexample. Cheap tier (just an
   abstract `Iteration` sig) catches "could starve" but not "deterministically does."
   Expensive tier (TLA+ port with fairness constraints) is overkill for most protocols —
   skip unless you genuinely need to prove "every runnable task is eventually claimed,"
   which Alloy's bounded checking can't certify.

   Persist the fairness sub-model alongside the main model (e.g.
   `system-models/{domain}-fairness.als`). Tie it back into reconciliation (step 9b) the
   same way as 8b: counterexample → FixSource on the call pattern, both-fail → FixSource
   on the candidate-selection primitive itself.

9. **Run → Interpret → Re-run loop** — Execute the model using `bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh /path/to/model.als` via the Bash tool. Then proactively present results:
   - All checks pass: *"All N assertions hold. Here's what each one proves: [list]. The model found
     no counterexamples — your invariants are consistent within scope M. Want to increase scope
     for stronger confidence, or move to reconciliation?"*
   - Counterexample found: *"Assertion X found a counterexample. Here's the scenario: [trace].
     This means [explanation]. Two options: (1) the model is wrong and we fix it, or (2) this is a
     real bug in your system design. Which is it?"*
   - After editing: **always re-run before re-interpreting.** Previous output is stale.
10. **Reconcile against source artifacts** — **Do not iterate or fix the model until
   reconciliation is complete. Completion means the reconciliation report has been written
   to `./system-models/reports/{domain}-reconciliation.md` — verify the file exists before
   proceeding.** Proactively start reconciliation:
   *"The model is stable. Now let's check if it matches your actual system. Which sources should I
   compare against?"* Then present the selection table:
   *"Code (always included), Spec, Tests, Docs — which of these exist and should I check?"*

   After the user selects, produce the cross-source consistency table and present it.
   **For each discrepancy, explain the direction clearly** — don't just say "FixModel",
   explain what it means in context:

   *"I found 3 discrepancies. For each one, I'll explain what's different and which
   direction the fix goes:*
   *1. Code has a 'Suspended' state the model doesn't — the team shipped this intentionally,
      so the model needs to catch up. → **FixModel (align to code)***
   *2. Code allows Finance to void invoices, but the spec says Admin only — this looks like
      a code bug, the model correctly enforces Admin-only. → **FixSource (code has a bug)***
   *3. Code tracks SLA deadlines, model doesn't — we chose not to model this.
      → **Exclusion (intentional scope boundary)***
   *For item 1, should the model track what the code does, or what the spec says it should do?
   These may differ."*

   Real systems have multiple sources of truth that may contradict each other — the formal model
   is the tool that resolves these contradictions.

   **Multi-source cross-check**: for each system property (state, transition, invariant, role), collect
   what each source artifact says about it, then compare against the model:

   ```
   | Property        | Code says      | Spec says       | Tests cover | Model asserts     | Verdict        |
   |-----------------|----------------|-----------------|-------------|-------------------|----------------|
   | Order states    | 5 states       | 6 (+ Suspended) | 4 tested    | 5 (no Suspended)  | Spec drift     |
   | Cancel → Ship   | blocked (guard) | not mentioned   | not tested  | assert: impossible | Code correct   |
   | Refund needs Pay| no guard (!)   | required         | tested      | assert: required   | Code bug found |
   ```

   Each cell gets one of five outcomes. **Present each outcome with its direction** so the user
   understands what will change and which artifact is treated as the source of truth:

   - **Aligned** — all sources agree with the model. No action needed.

   - **FixSource** — the model captures the *design intent* correctly, but a source artifact
     (code, spec, or docs) diverges from that intent.
     *Direction*: model stays, source changes. Present as:
     *"The model says [X]. The code does [Y]. The model represents the intended design.
     → Fix the code/spec to match the model. This is a bug in the source, not the model."*

   - **FixModel** — a source artifact reflects the *current reality* that the model doesn't
     capture yet. This can mean two very different things — **always clarify which one**:
     - **FixModel (align to code)** — the code changed intentionally, and the model should
       track the new behavior. *"The team shipped [X]. The model still describes the old
       system. → Update the model to reflect what the code actually does now."*
     - **FixModel (align to intent)** — the spec describes the intended behavior, but the
       model was written against the old spec. *"The spec was updated to require [X]. The
       model doesn't enforce it yet. → Update the model to match the new design intent."*
     Present the choice to the user: *"Should the model track what the code does (as-is)
     or what the spec says it should do (to-be)? These may differ."*

   - **Conflict** — sources contradict each other (code says X, spec says Y, model says Z).
     No single artifact is obviously correct. The model becomes the arbitrator: run both
     versions as scenarios, see which produces counterexamples. Present as:
     *"The code does [X], but the spec says [Y], and the model asserts [Z]. These three
     disagree. Which one represents the intended behavior? Options:
     (1) Code is correct — fix spec + model to match code
     (2) Spec is correct — fix code + model to match spec
     (3) Neither — we need to decide the right behavior first"*

   - **Exclusion** — source claims something the model intentionally doesn't cover.
     *"The code has [X], but we chose not to model it because [reason].
     → No fix needed. Documented as intentional scope boundary."*

   **Cross-artifact contradictions are the highest-value finding.** When code says 5 states but spec
   says 6, or when tests pass but the model finds a counterexample, you've found a real bug that
   no single-source review would catch. The formal model is the only artifact that checks ALL paths
   exhaustively — it's the ground truth against which everything else is measured.

   **Partial reconciliation**: not every project has all four source types, and not every
   reconciliation needs to check them all. Before starting, ask the user which artifacts to include:

   ```
   | Source artifact | Include? | Reason                                          |
   |----------------|----------|-------------------------------------------------|
   | Code           | Yes      | Always — the actual behavior                    |
   | Spec/RFC       | Yes      | Has state machine diagram we need to verify      |
   | Tests          | Skip     | Test suite is outdated, will rewrite after model  |
   | API docs       | Skip     | Auto-generated from code, not independent source  |
   | UML diagrams   | Yes      | Architecture team maintains these separately      |
   ```

   Skipped artifacts get a documented reason. The reconciliation report marks them as "not checked"
   rather than "aligned" — so the reader knows the gap exists. If a skipped artifact later turns out
   to matter, re-run reconciliation with it included.

   This step applies to any combination of: source code, API specs, test suites, README files,
   onboarding guides, UML diagrams, database schemas, Terraform configs, skill definitions.

   **Persist the report:** After producing the reconciliation report, write it to
   `./system-models/reports/{domain}-reconciliation.md` using the Write tool. This is mandatory —
   reports must survive beyond the conversation.

10b. **Enforcement audit** — After reconciliation shows properties Aligned, verify that the source
   artifact *enforces* each rule at the decision point, not just *mentions* it somewhere.

   **Why this step exists:** Models verify structural properties. Source artifacts guide behavior.
   If a model proves "X is impossible" but the source text says "consider X" instead of "X is
   required," the model is correct and the system is still broken. The reconciliation looks green
   but the real-world protocol has a hole. This matters most when the source artifact is
   instructions for an LLM or a human protocol — executable code enforces by construction,
   but natural language enforces only by precision of phrasing.

   **For each Aligned assertion, check four things:**
   1. **Decision point location** — Where in the source is the gate? A termination checklist,
      acceptance criteria section, API contract, pre-commit hook? Not a background section,
      not a "see also" reference — the actual point where proceed/block is decided.
   2. **Listed at the gate** — Is the assertion present at that decision point? A rule mentioned
      in section 3 but absent from the checklist in section 8 is not enforced.
   3. **Language strength** — Is the phrasing imperative or advisory?
      - **Gate language** (enforces): "must", "requires", "blocks", "cannot proceed unless",
        "assert", "check", "reject if not"
      - **Advisory language** (does not enforce): "note", "consider", "should ideally",
        "flag for review", "be aware that", "recommended"
      If the model has a hard gate but the text uses advisory language, the text is weaker
      than the model — the rule exists but won't actually prevent the violation.
   4. **Completeness at the gate** — Could a reader (or LLM) following *only* the decision-point
      checklist miss this assertion? If the checklist has 6 items but the model has 10 assertions,
      4 are unenforced regardless of whether they appear elsewhere in the document.

   **Three-level enforcement verdict** for each Aligned property:
   - **Enforced** — rule is at the decision point, uses gate language, reader can't miss it.
     *This is the only level that actually prevents the violation the model proves impossible.*
   - **Mentioned but unenforced** — rule appears in the source but not at the decision point,
     or uses advisory language. The reconciliation says "Aligned" but the protocol has a hole.
   - **Missing from gate** — rule is proven by the model, doesn't appear at the decision point
     at all. Highest risk — the model is right, the system will still allow violations.

   **Present enforcement findings to the user:**
   *"All N assertions are Aligned (the text mentions every rule). But of those N:*
   *- K are Enforced at the decision point with gate language*
   *- M are Mentioned but not at the gate — they appear in section X but not in the checklist*
   *- P are Missing from the gate entirely*
   *The M + P items mean a reader following the checklist could miss these rules.
   Should I add them to the checklist with imperative language?"*

10b-A. **Gate artifact check** — After confirming a rule is Enforced (present at the decision
   point with gate language), verify that the artifacts the gate inspects exist in the format
   it expects. A gate without auditable inputs is a gate that checks claims, not evidence.
   A gate that says "evidence log must contain X" is only enforceable if the evidence log
   entry format actually has a field for X.

   **For each Enforced rule, trace the audit chain. Block if any link is missing:**
   1. **What does the gate check?** (e.g., "all sources were queried for absence claims")
   2. **Where is that data recorded?** (e.g., a specific field in the evidence log entry)
   3. **Does the recording format include that field?** (e.g., is there an `Absence sources: N/M` field?)
   4. **Does the collection step say to record it?** (e.g., does the upstream checkpoint say "record in the entry"?)

   If any link is missing, the gate is **structurally unenforceable** — it uses imperative
   language ("must contain") but there's no artifact to inspect. This is harder to spot than
   a missing gate because the gate text looks correct.

   **Three failure modes:**
   - **Missing field** — the log/entry format has no field for what the gate checks.
     *Fix: add the field to the format.*
   - **Missing recording instruction** — the format has the field, but the collection step
     doesn't tell the operator to fill it in.
     *Fix: add "record in the entry: [field]" to the collection step.*
   - **Ambiguous field** — the format has a field that could contain the data, but it's not
     specific enough to audit deterministically (e.g., "Source" could mean the query source
     or the absence-verification source list — these are different).
     *Fix: add a dedicated field with unambiguous semantics.*

   **Present as a table:**

   ```
   | Gate condition | Checks for          | Recorded in | Field exists? | Recording instruction? | Verdict       |
   |----------------|---------------------|-------------|---------------|------------------------|---------------|
   | TC25 (F6)      | all sources queried | E<N> entry  | Absence: N/M  | Step 4 F6 checkpoint   | OK            |
   | TC26 (F7)      | write path traced   | E<N> entry  | ???           | ???                    | Missing field |
   ```

   This closes the gap between "the rule is at the gate" and "the gate can actually fire."
   Include this table in the enforcement report written to disk.

   **When to run this step:**
   - After reconciliation shows all properties Aligned
   - Especially when the source artifact is LLM instructions, human protocols, checklists,
     or runbooks (not executable code — code enforces by construction)
   - When the source has a clear "gate" structure (acceptance criteria, termination conditions,
     pre-flight checklist, review template)

   **When to skip:**
   - Source is executable code (enforcement is structural — if the code has the check, it runs).
     But run the **enforcement-map check** instead (see step 10b-B) — code structure can drift
     between commits, and the prose audit can't catch a gate that quietly disappeared in a refactor.
   - Source has no gate structure (e.g., a design doc with no decision points)

   **Persist the report:** After producing the enforcement audit, write it to
   `./system-models/reports/{domain}-enforcement.md` using the Write tool. This is mandatory —
   reports must survive beyond the conversation.

10b-B. **Enforcement map (mechanical audit)** — When the source is executable code, the prose
   enforcement report is not enough on its own. Prose can lie about code without anything noticing.
   Generate a companion `system-models/reports/enforcement.yaml` that maps each verified property
   to the mechanical evidence of its enforcement: model assertion names, code call sites, exit
   codes, spec phrases, test names. The bundled checker walks the YAML and fails CI if any
   claimed gate is missing — so a refactor that drops a gate becomes a build failure on the
   next commit, not a discovery six months later.

   See `references/enforcement-map.reference` for the full schema and authoring guidance.
   The minimum viable entry is the property name plus one model assertion plus one code gate;
   add more as you trace them. Empty fields are honest — they say "we proved this, we don't yet
   know everywhere it's enforced."

   **Two gate kinds, complementary.** `code_gates` is file-listed: "this file calls X" —
   catches *deletion* of a check during refactor. `closure_gates` is closure-based: "every
   call site of protected primitive Y, anywhere in the project, must be preceded by gate Z
   in the same enclosing function" — catches *silent additions* (a new file produces the
   protected event but nobody added it to the file list). Use both. Whenever the model
   protects a primitive whose every call must be checked (status writes, lock acquisition,
   permission gates), declare a `closure_gates` entry; the AST walker discovers new call
   sites automatically and demands the gate. Supported languages: `python` (stdlib, no
   extra dep) and `bash` (requires `bashlex`). See `references/enforcement-map.reference`
   §"Closure gates" for when the lexical-scope limitation matters and how to pair the two.

   Run the checker:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh \
     --check-enforcement system-models/reports/enforcement.yaml
   ```

   Add `--check-coverage` to also flag any model `check Foo` that has no enforcement entry —
   this catches "the model proves X but no one wrote down how X is enforced."

   **When to use:** any project whose source includes executable code (Python, TS, Go, Java, …).
   Skip when the source is purely instructions/protocol — step 10b-A's prose audit already covers
   that case structurally.

   **When to write the entry:** alongside adding `check Foo` to the `.als` file, not after.
   The enforcement map should grow with the model, not be bolted on at the end.

   **The map is a checklist, not a checker.** The mechanical script proves anchors still
   resolve (terms exist, asserts are defined, files are present) — it does not judge
   whether the cited language actually enforces the property. That judgment is yours
   during the step 10b audit. The YAML's primary job is to make sure you **don't miss
   a property**: walk every entry as the audit's iteration loop. For each one, read the
   assertion, read the cited code/text gates, and judge enforcement (Enforced /
   Mentioned-unenforced / Missing-from-gate / Counter-evidence). Don't audit from
   memory and don't grep ad hoc — both risk skipping a property the YAML already
   enumerates. (This is exactly the bug class that motivated the YAML in the first
   place: an LLM-written prose audit "remembered" four enforcement sites but missed
   the fifth.)

   **The map is open-ended.** Before declaring the audit complete, scan for enforcement
   points the YAML doesn't yet know about — code/tests/skill text changes can
   introduce new gates that need entries. Specifically check:

   - **Code or tests changed since the YAML was last touched?** Run
     `git log --since=$(stat -f %Sm system-models/reports/enforcement.yaml) --name-only`
     over the project's source roots. For each new or modified file: does it gate,
     reject, or assert anything the model proves? If yes, add or extend an entry.
   - **SKILL.md / spec text changed?** New imperative clauses ("must", "MANDATORY",
     "blocks", "do not proceed unless") that aren't covered by an existing entry's
     `must_mention` are unaudited. Either add a phrase to the relevant entry or
     create a new entry.
   - **Model has new `check Foo`?** Run `verify.sh --check-enforcement <yaml>
     --check-coverage` — any flagged check is a property the model proves but the
     YAML doesn't audit. Resolve before completing the audit: add an entry, or
     mark it as an intentional gap with a YAML comment (the way `IterationNotALoop`
     is documented in `formal-modeling/self-models/enforcement.yaml`).

   A static YAML against an evolving codebase becomes a false-completeness signal —
   the auditor walks 13 entries, says "all enforced," and never sees the 14th gate
   added last week. Discovery is part of the audit, not a separate task.

**Do not proceed to iterate (fixing model or source) until both reconciliation and enforcement
audit are complete. Completion means both report files exist on disk:**
- `./system-models/reports/{domain}-reconciliation.md`
- `./system-models/reports/{domain}-enforcement.md`
**Verify both files exist before proceeding to iterate.** If any Enforced verdict has an
incomplete gate audit chain (missing field, missing recording instruction, or ambiguous field),
block iteration and fix the chain first — otherwise the gate will pass claims without evidence
after the fix.

**After reconciliation + enforcement audit, present the next decision explicitly.** Summarize
the directions so the user sees at a glance what will change and where:

*"I found N discrepancies:*
*- X where the model needs updating (M align to code, K align to spec intent)*
*- Y where source artifacts have bugs (model is correct)*
*- Z intentional exclusions (documented, no action needed)*
*For the FixModel items, I need to know: should the model track what the code does today
(as-is), or what the spec says it should do (to-be)? These may differ for items A, B.*
*Two options for the overall deliverable:*
*(1) I produce a gap report and we stop here — useful for architecture reviews or handoffs.*
*(2) I fix the model and source artifacts, re-run, and we iterate until everything aligns.*
*Which do you prefer?"*

**Stopping at the report.** Not every reconciliation needs to proceed to iteration. The gap report
itself is often the deliverable — a structured list of discrepancies with outcomes (FixSource /
FixModel / Exclusion) and a reconciliation plan. This is valuable for:
- **Architecture reviews** — "here are the 5 places our spec diverges from the verified model"
- **Compliance audits** — "these assertions pass, these are documented exclusions, these need fixes"
- **Handoff documents** — "the model proves X, Y, Z; the code claims A, B, C; here's where they differ"
- **Decision records** — "we chose not to model X because Y; here's the gap assertion documenting it"

When the user wants a report rather than fixes, produce a **reconciliation report** in the format below.
The report must be human-readable but with precise references to both model elements and source artifacts.

**Reconciliation report format:**

```markdown
# Reconciliation Report: [model name] vs [source artifacts]

## Summary
- Checks: N pass / M total
- Scenarios: X SAT, Y UNSAT
- Source artifacts compared: [code, spec, tests, docs, ...]
- Discrepancies found: K (A Aligned, F FixSource, G FixModel, C Conflict, H Exclusion)
- Enforcement (Aligned items): E Enforced, U Mentioned-unenforced, P Missing-from-gate

## Cross-Source Consistency

| Property | Code | Spec | Tests | Docs | Model | Verdict |
|----------|------|------|-------|------|-------|---------|
| [name]   | [what code says, file:line] | [what spec says] | [covered?] | [what docs say] | [assertion name] | Aligned/FixSource/Conflict |

## Discrepancies

### 1. [Short description of the claim]
- **Source**: [where the claim appears — file:line, spec section, code function]
- **Outcome**: FixSource | FixModel (align to code) | FixModel (align to intent) | Conflict | Exclusion
- **Direction**: [plain-language explanation of what moves where]
  - FixSource example: *"Model is correct (design intent). Code at line 42 is wrong → fix code."*
  - FixModel example: *"Code changed intentionally (team shipped X). Model is stale → update model to match code."*
  - Conflict example: *"Code says X, spec says Y. User decides which is intended behavior."*
- **Model evidence**:
  - Assertion: `AssertionName` — [pass/fail, what it proves]
  - Scenario: `ScenarioName` — [SAT/UNSAT, what it demonstrates]
  - Fact: `FactName` — [what structural constraint applies]
- **Source evidence**: [quote from code/spec/text that contradicts or matches]
- **Impact**: [what changes if this is fixed vs left as-is]
- **Recommended action**: [specific fix — "change line 14 to..." or "add assertion..." or "document as exclusion because..."]

### 2. ...

## Boundary Review

| Element | Decision | Model reference | Source reference | Impact |
|---------|----------|-----------------|-----------------|--------|
| [name]  | Include / ExcludeSafe / ExcludeRisky / Stub | `sig Name`, `fact Name` | file:line | [what changes] |

## Gap Assertions (documented exclusions)

| Gap | Assertion | Why excluded | Risk level |
|-----|-----------|-------------|------------|
| [name] | `GapAssertionName` | [rationale] | Safe / Risky |

## Remaining gaps (not yet modeled)
- [element]: [why not modeled, what it would take to add, what risk remains]

## Enforcement Audit (for natural-language source artifacts)

| Assertion | Verdict | Decision point | Gate language? | Notes |
|-----------|---------|---------------|----------------|-------|
| `AssertionName` | Enforced / Mentioned-unenforced / Missing-from-gate | [section/checklist where the gate is] | [quote: "must X" vs "consider X"] | [what to fix] |

**Summary**: K/N enforced, M mentioned-unenforced, P missing from gate.
Unenforced items need to be added to [decision point] with imperative language.
```

Each entry in the report links in two directions:
- **To the model**: assertion name, scenario name, fact name, sig name — so the reader can find the
  exact Alloy code that verifies (or fails to verify) the claim.
- **To the source**: file path + line number, spec section, code function name — so the reader can
  find the exact text/code that makes the claim.

This bidirectional traceability is the core value: a stakeholder can follow any discrepancy from the
natural-language claim to the formal proof (or gap), and back.

### Modeling conventions

- **Bool helper:** Use `abstract sig Bool {}` / `one sig True, False extends Bool {}` for nullable booleans.
- **Scoping:** Use `for N` to bound the search space. Start small (`for 4`), increase (`for 6`, `for 8`) once assertions pass at small scope.
- **Cardinality hints in `run`:** Use `for 4 but 2 User, 1 Plan, ...` to guide the solver toward interesting instances.
- **Module declaration:** Start every file with `module ModuleName`.
- **Documentation:** Put a block comment at the top explaining what the model covers, what code it maps to, and what gaps exist.

### Common patterns from production models

Read `references/alloy-patterns.reference` for the full pattern catalog extracted from production use. Key categories:

**Basics:** Bool helper, enum states, nullable fields (`lone`), pure functions (`fun`), set comprehension (`{ x: T | pred }`), relation lookup (`Cache.index[key]`), Int constraints with ranges.

**Structural:** Soft-delete lifecycle, partial unique index (`lone` for UNIQUE WHERE), disjoint subtypes for mutual exclusion, cross-system integration, cache consistency, pair symmetry (`<=>`), acyclic chains (`^next`), ordered enum chains (comparison without Int), event sigs (operation snapshots).

**Temporal:** `var sig` state machine, relation override `++` for surgical updates, frame condition composition (group unchanged state into reusable frame preds), stutter step, nested `eventually` for ordered multi-step scenarios.

**UX / Access Control:** Role×State×Field access matrix (`canWrite[r, t, f]`), CTA validity checking (button in email → action available?), notification recipient sets (who gets notified per transition), template→trigger state mapping (templates only fire in relevant states).

**Data Conversion & Time-Series:** Axiomatic data conversion (timezone/format via axioms, not implementation), data format mismatch verification (encoding bugs, double-offset), DB column type semantics (`timestamptz` vs `timestamp`, `::date` cast hazards), singleton lookup maps (ternary relation for global functions), effect bags (typed contribution sets replacing Int accumulation), sliding window verification (proving records fall inside/outside time windows under shifts).

**Pipeline & Build:** Pipeline DAG verification (step dependencies satisfied by earlier producers), artifact versioning & staleness detection (mutable artifacts, stale reads), freshness guards (snapshot consumers must verify cache currency), proof of work (verification steps must produce specific evidence), total order with `util/ordering`.

**Verification:** Before/After scenario predicates, scoping with `exactly` keyword, concurrency/advisory lock modeling, **gap assertions** (intentionally failing checks that prove architectural flaws exist), **resolved choice** (model OR-dependencies as a decision that picks one option, then constrain conditionally), **equivalence classes** (replace continuous ranges with discrete behavior-triggering classes to avoid Int overflow while verifying all boundary combinations), **compositional verification** (split sequential models into segments joined by interface predicates — assume-guarantee reasoning for fast independent checks with end-to-end confidence on demand).

**Alloy 6 Essentials:** `util/ordering` alias convention (`open as ord`), temporal invariants (`always { inv }`), `until`/`releases` operators, `disj` quantifier for distinct pairs, module parameterization for reusable libraries, `seq` sequences for indexed collections, inductive invariant structure (init + preservation), `expect` annotations on run/check commands.

## Model output location

By default, write user models to **`./system-models/`** relative to the project root (the working
directory where the skill was invoked). Create the directory if it doesn't exist. This keeps
formal models co-located with the project they describe, separate from application code.

```
project-root/
├── src/                    # application code
├── system-models/          # ← formal models live here
│   ├── orders.als          # e.g., order lifecycle model
│   ├── permissions.als     # e.g., RBAC verification
│   ├── pipeline.als        # e.g., data pipeline DAG
│   └── reports/            # ← reconciliation & enforcement reports
│       ├── orders-reconciliation.md
│       ├── orders-enforcement.md
│       └── permissions-reconciliation.md
├── ...
```

Naming convention: use the domain name as the file name (`orders.als`, `permissions.als`,
`billing.als`). If a model is split into modules for solver performance, use a shared prefix
(`orders.als`, `orders_temporal.als`, `orders_boundary.als`).

The user can override this location — if they specify a path, use it. But when no path is given
and no existing `.als` file is found for the domain, default to `./system-models/`.

## Report output location

**MANDATORY:** Always persist reconciliation and enforcement reports to disk — do not leave them
only in the conversation. Write reports to **`./system-models/reports/`** (create the directory
if needed). This ensures traceability survives beyond the conversation.

**File naming:** `{domain}-reconciliation.md` and `{domain}-enforcement.md`
(e.g., `orders-reconciliation.md`, `permissions-enforcement.md`).

**When to write:**
- After step 9b (Reconcile) — write the reconciliation report
- After step 10b (Enforcement audit) — write the enforcement report
- After iteration (step 10) that changes outcomes — overwrite the report with updated results

**When to update:**
- If the model is re-run and reconciliation is re-done, overwrite the existing report
- Add a `Last updated:` timestamp at the top of each report

**Report header** — prepend this to every persisted report:

```markdown
<!-- Generated by formal-modeling skill — do not edit manually -->
<!-- Model: {model-path} | Sources: {source-list} | Date: {date} -->
```

Reports use the same format documented in the reconciliation report format section above.
The persisted file is identical to what is shown in the conversation — the file IS the report,
not a summary of it.

## Running models

**MANDATORY:** You MUST always run models through the bundled scripts using the Bash tool.
Never skip execution or claim the JAR/solver is unavailable — the scripts handle all
downloads, caching, and fallbacks automatically. If execution fails, show the error output
to the user; do not substitute your own review for solver output.

The skill bundles two verification pipelines and a unified runner:

```bash
# Unified runner — routes by file extension
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh /path/to/model.als   # → Alloy pipeline
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh /path/to/model.dfy   # → Dafny pipeline

# Self-verification — checks the skill's own models
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh --self --dafny   # fast: ~12s, unbounded proofs
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh --self --alloy   # thorough: ~2:30, counterexamples
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh --self --both    # both pipelines

# Direct runners (when you need full formatted output)
bash ${CLAUDE_SKILL_DIR}/scripts/alloy_run.sh /path/to/model.als
bash ${CLAUDE_SKILL_DIR}/scripts/dafny_run.sh /path/to/model.dfy

# Enforcement-map check (mechanical audit; see step 10b-B)
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh --check-enforcement \
  system-models/reports/enforcement.yaml
bash ${CLAUDE_SKILL_DIR}/scripts/verify.sh --check-enforcement \
  system-models/reports/enforcement.yaml --check-coverage
```

### When to use Alloy vs Dafny

| Use case | Tool | Why |
|----------|------|-----|
| **Exploring a new domain** | Alloy | Generates concrete instances, shows counterexamples |
| **Finding design bugs** | Alloy | Counterexample display shows exactly what breaks |
| **CI/pre-commit verification** | Dafny | 15x faster, unbounded proofs |
| **Proving properties for ALL inputs** | Dafny | Not bounded by scope N |
| **Generating verified executable code** | Dafny | Compiles to C#/Java/Go/JS |
| **Reconciling against source** | Alloy | UNSAT cores explain WHY assertions hold |

The default workflow: **model in Alloy first** (explore, find edge cases, show stakeholders),
then **port to Dafny** for CI-grade verification if the model stabilizes.

**Don't replace Alloy with Dafny — they complement each other.** Alloy excels at design
exploration: finding edge cases, generating counterexamples, verifying business rules before
coding. Dafny excels at implementation verification: proving code correct, generating verified
executables, enforcing contracts in production code.

Combined workflow:
1. Model in Alloy — find all edge cases, verify invariants within scope
2. Port critical invariants to Dafny — prove them unbounded
3. Generate executable Dafny code — compile to target language with proofs intact

See `references/alloy-dafny-comparison.reference` for detailed syntax and concept mapping between the two tools.

### Alloy prerequisites
- **Java 17+ JDK** (preferred) — `brew install openjdk@17` on macOS, `apt install openjdk-17-jdk` on Ubuntu.
  The script auto-detects Java from common locations (Homebrew, JAVA_HOME, system paths).
  JDK is needed for compiling `AlloyRunner.java`; if you modify the runner, you need `javac`.
- **Docker** (fallback) — if no local Java 17+ is found, the script falls back to `eclipse-temurin:17-jdk`
  in Docker. Also useful if you need to tweak `AlloyRunner.java` without installing a local JDK.
- **curl** and **python3** must be available
- First run downloads the Alloy 6 JAR (~20 MB) and extracts classes (~66 MB); subsequent runs are cached in `.alloy/` next to the script

### What the pipeline does

1. Detects local Java 17+ or falls back to Docker
2. Downloads the latest Alloy 6 JAR from GitHub releases (cached in `.alloy/alloy.jar`)
3. Extracts OSGi bundle classes for classpath access (cached in `.alloy/extracted/`)
4. Compiles a custom `AlloyRunner.java` that executes ALL `run` and `check` commands
5. Runs the model, piping output through `alloy_format.py`

### Reading the output

The formatter produces structured output for each command:

**For `run` commands:**
- **Instance found:** Shows ATOMS table (entity instances), FIELDS table (relations as tuples), and WITNESSES (skolem/scenario variables)
- **UNSAT:** No satisfying instance exists — the scenario constraints are contradictory. Loosen constraints or increase scope.

**For `check` commands:**
- **No counterexample:** The assertion holds for all instances within the scope. This is the desired result.
- **COUNTEREXAMPLE FOUND:** The assertion is violated. The output shows the specific instance that breaks it — this is a bug in your model or your system design.

**For temporal traces:**
- States are shown sequentially with `◄` markers on changed fields
- Loop-back point indicates where the infinite trace cycles
- `~` prefix marks variable (mutable) sigs

### Interpreting results

| Output | Meaning | Action |
|--------|---------|--------|
| `run` → instance | Scenario is possible | Verify it matches expected behavior |
| `run` → UNSAT | Scenario is impossible | Check if constraints are too tight |
| `check` → no counterexample | Property holds (within scope) | Increase scope to build confidence |
| `check` → counterexample | Property violated | Fix the model or flag the design bug |

When a counterexample appears, trace through it step by step with the user. Explain which atoms exist, what their relationships are, and why the assertion fails. This is often the most valuable output — it reveals edge cases the team hasn't considered.

### Dafny prerequisites
- **Dafny** — `brew install dafny` on macOS, `dotnet tool install --global dafny` on Linux.
  Includes Z3 SMT solver automatically.
- **python3** — for the output formatter

### Dafny pipeline

`dafny_run.sh` runs `dafny verify --log-format text` and pipes through `dafny_format.py`.
Output shows per-lemma results:

```
  ✓  DependenciesSatisfied                         00:00:00.166
  ✓  AllDependenciesSatisfied                      00:00:00.059
  ✗  BrokenInvariant                               00:00:00.012
     ✗ model.dfy:42  a postcondition could not be proved
       ensures forall s: Step :: stepRequires(s, a) ==> ...

  Lemmas: 31/32 proved (1 FAILED)
```

Key differences from Alloy output:
- **No instances/counterexamples** — Dafny proves or disproves, doesn't generate examples
- **Per-lemma timing** — shows which proofs are expensive
- **Source line context** — error messages point to exact postcondition that failed
- **Resource count** — Z3 rlimit units (deterministic, reproducible)

### Alloy → Dafny translation patterns

| Alloy | Dafny | Notes |
|-------|-------|-------|
| `abstract sig` + `one sig` | `datatype` | Direct mapping |
| `fact` | `predicate` + `requires` | Facts become function preconditions |
| `assert` + `check` | `lemma` + `ensures` | Unbounded proof, not bounded check |
| `run` (instance generation) | explicit witness in lemma body | Must construct the example manually |
| `util/ordering[Step]` | `function stepIndex(s): nat` | Total order via integer index |
| `requires: set Artifact` | `predicate stepRequires(s, a)` | Relation as binary predicate |
| `producedBy: one Step` | `function producedBy(a): Step` | Total function |
| `var sig` (temporal) | `seq<State>` + inductive lemmas | Manual encoding of traces |
| `always P` | `forall i :: P(trace[i])` | Quantifier over trace indices |
| `eventually P` | `exists i :: P(trace[i])` | Existential over trace |
| `for N` (scope) | N/A | Dafny proves for ALL inputs |

## Workflow integration

### For software features
1. **Before coding:** Write an Alloy model of the state machine / data invariants
2. **Run checks:** Verify safety properties hold; find counterexamples early
3. **Run scenarios:** Generate concrete examples that serve as test cases
4. **Document:** The model itself is documentation — add it to the repo alongside the code
5. **Iterate:** As the design evolves, update the model and re-verify

### When the system changes (re-verification)

Models describe a system at a point in time. When the team ships changes — new states, new roles,
new transitions, refactored logic — the existing model may silently drift from reality. All checks
still pass, but they verify the **old** system.

**Automatic drift detection**: when a user invokes the skill and an `.als` model already exists
in the project, check whether the source files it describes have changed since the model's last commit:

```bash
# Find the model's last commit timestamp
MODEL_COMMIT=$(git log -1 --format=%H -- path/to/model.als)

# Find source files modified after that commit
git diff --name-only $MODEL_COMMIT..HEAD -- src/ spec/ tests/ docs/
```

If any files appear in the diff, the model may be stale — switch to Reverify mode automatically.
If no diff, the model is current — offer a fresh run on a new domain or skip re-verification.

This detection also works at trigger time: if the user asks about a domain and an `.als` file for
that domain already exists, check the diff before deciding FreshRun vs Reverify.

Re-entry path:
1. **Detect drift:** Run git diff between the model's last commit and HEAD for the source files
   the model describes. If any changed, the model needs re-verification.
2. **Re-run boundary review (step 8):** Read the current source system alongside the existing model.
   Ask: "What changed? Which entities/transitions/invariants in the model no longer match the code?"
3. **Re-run the model (step 9):** Even if nothing looks wrong, re-run — the solver may find
   counterexamples in the unchanged assertions applied to the new system state.
4. **Reconcile (step 10):** Compare model assertions against the current system. For each
   discrepancy, present the direction clearly:
   - *FixSource*: "Model captures the intent correctly; this source artifact has a bug."
   - *FixModel (align to code)*: "Code changed intentionally; model needs to catch up."
   - *FixModel (align to intent)*: "Spec updated; model should enforce the new design."
   - *Exclusion*: "Source has this, but we intentionally don't model it."
5. **Produce report or iterate:** Either stop with a gap report or proceed to fix the model.

This is NOT the same as "iterate" (step 10 in the normal flow). Iterate fixes the model based on
counterexample feedback within the same session. Re-verification is a new entry point — the system
moved, the model didn't, and someone needs to catch up.

### For business processes
1. **Map the process:** Identify states, transitions, actors, and rules
2. **Model in Alloy:** Each actor is a sig, each step is a transition pred
3. **Verify properties:** "Can a customer be charged twice?" "Can an order ship without payment?"
4. **Share counterexamples:** Show stakeholders concrete scenarios where rules break

### For skill/workflow development
1. **Model the skill's state machine:** What states can the workflow be in? What transitions are valid?
2. **Verify completeness:** Can every state be reached? Is every state reachable from the initial state?
3. **Check safety:** Are there impossible/illegal state combinations?
4. **Generate test cases:** Use `run` scenarios as acceptance criteria

### For AI/LLM pipelines and skills

This is the meta use case — formal modeling improves the quality of the AI agents and skills themselves.
Multi-step AI pipelines (RAG, extraction, summarization, cross-referencing) are especially prone to
subtle dependency and consistency bugs that unit tests miss because each step works correctly in
isolation but the pipeline as a whole has ordering violations, stale data, or hollow verification.

1. **Model the pipeline as a DAG:** Each step is a `Step` sig, each file/artifact is an `Artifact` sig.
   Wire `requires`/`produces` relations. Use `util/ordering[Step]` if steps are strictly sequential.
2. **Assert dependency satisfaction:** `all s: Step, a: s.requires | lt[a.producedBy, s]` — no step
   reads an artifact from the future.
3. **Track mutable artifacts:** If a step mutates an artifact after it was cached/indexed, model
   `ArtifactVersion` sigs and detect staleness. Common in pipelines where an enrichment step writes
   to a vector DB, then a later step modifies the source files — the index is now stale.
4. **Require freshness guards:** Assert that every consumer of a cached artifact has a
   `FreshnessCheck` sig that compares the cache against the authoritative source.
5. **Enforce proof of work:** Verification steps in AI pipelines can produce plausible-looking
   "all passed" reports without actually grounding against source data. Model `ProofOfWork` sigs
   that require specific evidence (source quotes, per-item tables, pass/fail).
6. **Find counterexamples:** "Can we reach step N without the grounding audit running?"
   "Can links be produced without reading the source file?" The solver answers definitively.

See patterns 32-36 in `references/alloy-patterns.reference` for complete examples.

## Reference files

- `references/alloy-patterns.reference` — Modeling patterns catalog extracted from production use (read when writing a model)
- `references/static-model-example.als` — Static model: subscription states, invariants, plan upgrade
- `references/temporal-model-example.als` — Temporal model: subscription lifecycle traces with `var` fields
- `references/ux-verification-example.als` — UX verification: roles, field access, notifications, CTA validity, gap assertions
- `references/data-conversion-example.als` — Data conversion: axiomatic timezone, wire-format mismatch, DB column types, effect bag
- `references/pipeline-example.als` — Self-verification: this skill's own pipeline (copy of skill_pipeline.als — 42 checks, 16 runs, 13 steps, guided/free modeling modes with quality gate, prompt clarification, example selection by style, 7 critical decisions, 5 reconciliation outcomes incl. Conflict, partial reconciliation with source selection, multi-source cross-check, bidirectional report traceability, enforcement audit, boundary analysis, system-evolution drift, staleness, freshness, proof of work)
- `self-models/skill_pipeline.als` — Core pipeline model (49 checks, 19 runs — step ordering, dependencies, staleness, reconciliation, enforcement audit, Conflict outcome, report persistence, gate audit chain, report staleness)
- `self-models/skill_pipeline_boundary.als` — Boundary decisions module (2 checks, 1 run — isolated, no step/artifact overhead)
- `self-models/skill_pipeline_quality.als` — Quality gate module (3 checks, 3 runs — isolated, guided vs free mode)
- `self-models/skill_pipeline_decisions.als` — Critical decisions module (7 checks, 9 runs — isolated, style/pattern/drift/runtime)
- `self-models/skill_pipeline.dfy` — Dafny port of pipeline model (82 lemmas, unbounded proofs, iteration loop convergence)
- `references/ecommerce_orders.dfy` — Dafny port: e-commerce orders (12 lemmas)
- `references/feature_flags.dfy` — Dafny port: temporal feature flags (14 lemmas)
- `references/static-model-example.dfy` — Dafny port: subscription states (3 lemmas)
- `references/ux-verification-example.dfy` — Dafny port: UX/access control (10 lemmas)
- `references/data-conversion-example.dfy` — Dafny port: timezone axioms (11 lemmas)
- `references/dafny-patterns.reference` — Dafny modeling patterns catalog (46 patterns: basics, structural, state machine, temporal, access control, data conversion, pipeline, proof techniques)
- `references/alloy-dafny-comparison.reference` — Alloy vs Dafny: concept mapping, syntax translation, porting effort, error messages
- `scripts/verify.sh` — Unified runner: routes .als/.dfy, self-verification mode
- `scripts/alloy_run.sh` — Alloy execution pipeline (bash)
- `scripts/alloy_format.py` — XML instance formatter (python3)
- `scripts/dafny_run.sh` — Dafny execution pipeline (bash)
- `scripts/dafny_format.py` — Dafny output formatter (python3)
