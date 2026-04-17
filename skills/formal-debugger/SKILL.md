---
name: formal-debugger
description: >
  Structured bug investigation using formal models for hypothesis-driven debugging. Builds scoped
  Alloy models (normative rules, data constraints, causal chains, observability) to generate
  distinguishing experiments and narrow the causality cone around a symptom. Use whenever the user
  reports a bug, incident, or unexpected behavior and wants rigorous investigation. Trigger on
  "investigate", "root cause", "debug this", "why does this happen", "find the bug", "postmortem",
  or any unexplained symptom. Valuable for: business-rule bugs, state machine errors, workflow
  inconsistencies, cross-service disagreements, investigations where the obvious explanation was
  already checked. Not for simple stack traces or typos — use when the problem space is large
  enough that unstructured search would waste time or miss the real cause.
---

# Formal Debugger

Requires `formal-modeling` skill. Hypothesis accepted only when no other compatible hypothesis
remains undistinguished. **Production first** — prefer `direct` production queries over
`interpreted` code reading at every step.

#### Step 0. Fix the symptom

Create `./investigations/<slug>/` (kebab-case from symptom) with four files:
1. `investigation-report.md` — final report (start with `## Symptom`)
2. `evidence-log.md` — append-only evidence log (PW1)
3. `hypothesis-log.md` — append-only hypothesis log (PW3)
4. `model-change-log.md` — append-only model change log (PW2)

Formal model files (`.dfy`, `.als`) also go here. Append entries as events happen, not after.

Pin down the symptom — ask and record: **What** (exact wrong behavior), **Where** (service,
endpoint), **When** (always? intermittent?), **For whom** (all users? specific?), **What is NOT
the symptom** (adjacent things that work). Assess severity: data exposure → security-critical,
financial impact → business-critical, data loss → data-integrity-critical, compliance (GDPR,
SOC2, PCI-DSS) → note explicitly. Write `## Symptom` + `**Severity:**` into the report.

#### Step 0a. Inventory tooling

Check `investigations/tooling-inventory.md` first (template at `<skill-dir>/tooling-inventory.md`).
Determine: production DB, logs, metrics, tracing, error tracking, live API, config, queues,
repo, CI/CD. Write `## Tooling` noting `direct` vs `inferred` per tool.

#### Step 0b. Verify the symptom

**S0-V — symptom verification required.** Confirm the symptom with at least one `direct` fact
(production DB query, log, or live API observation) before Step 1. `interpreted` sources (reports,
specs, prior investigations) must be re-verified against production. Append E1 to `evidence-log.md`.
Update `## Symptom` with `**Verified by:**` citing E1.

#### Step 1. Build the minimal model

Requires `formal-modeling` skill. Check production logs/traces for the actual execution path
before writing model code. Append findings to `evidence-log.md`.

**Default: create a formal model file** (`.dfy` for fast iteration, `.als` for counterexamples).
The verifier catches edge cases that narrative reasoning misses. Run it, don't just write it.

**Model skip (user-acknowledged).** Claude may propose to skip if reasoning is clear, but the
user must acknowledge. Explain what the model would verify and what edge cases are missed.
Log as `M1: Skipped (user-acknowledged)` with reason. TC28 is satisfied by the skip entry.

Model only the **nearest causal layer**. Build four layers:
1. **Normative** — business rule invariants, forbidden states, pre/postconditions
2. **Data** — field constraints, valid/invalid combinations, stale derived data
3. **Causal** — execution path to symptom, async/transaction boundaries, branch points
4. **Observability** — expected traces per hypothesis, source reliability

Append M1 to `model-change-log.md` with trigger, what was created, solver results.

#### Step 2. Generate hypotheses

Extract hypotheses from the model. Each **must** follow H1:
`[condition] -> [mechanism] -> [state change] -> [symptom]`.
For each, state the counterfactual (FZ1). Append `created`, `mechanism-stated`,
`counterfactual-stated` entries to `hypothesis-log.md`.

#### Step 3. Design distinguishing checks

For each hypothesis pair: what check distinguishes them? **Strong** = confirms one, excludes
another. **Weak** = compatible with multiple. Order by max information gain.

#### Step 4. Collect facts

Each fact gets a **reliability tag**:

| Source | Reliability |
|--------|-------------|
| Production DB query | `direct` |
| Production logs (<7d) | `direct` |
| Production logs (>7d) | `inferred` |
| Live API response | `direct` |
| Deployed config / env vars | `direct` |
| Repo code | `interpreted` |
| Git history (local) | `interpreted` |
| Prior reports / specs / docs | `interpreted` |
| Alloy model results | `inferred` |
| User verbal description | `interpreted` |
| Mobile app code | `unreliable-source` |
| Third-party docs | `interpreted` |
| User reports | `inferred` |

**Repo code is not production truth.** Always tag code reading as `interpreted`.

**F4** — Fix tasks: first fact must be `direct` production observation of current behavior.
**F3** — Dynamic data: collect (1) current value, (2) change history, (3) timeline coverage.
**F6** — Zero-result queries: list ALL sources, query each. Record `Absence sources: N/M`.
**F7** — Wrong values: trace WRITE paths, not read. Record `Analysis type: write-path`.
**F8** — Numeric discrepancy: compute exact locally before estimating. Record `Computation method`.
**F9** — Snapshot fields: check temporality before trusting. Record `Field temporality`.

Append E<N> entries to `evidence-log.md` immediately as facts are gathered.

#### Step 5. Update model with facts

Add confirmed facts as model constraints. Re-run solver. Append M<N> to `model-change-log.md`.

**Valid status transitions:**

| From | Allowed transitions |
|------|-------------------|
| `active` | `compatible`, `weakened`, `rejected`, `undistinguished` |
| `compatible` | `accepted`, `weakened`, `rejected`, `undistinguished` |
| `weakened` | `rejected`, `compatible` |
| `undistinguished` | `compatible`, `rejected` |
| `rejected` | terminal — no transitions |
| `accepted` | terminal — no transitions |

Append `status-changed` entries to `hypothesis-log.md` with evidence reference.

#### Step 6. Check diagnostic equivalence

If hypotheses explain the same facts and predict the same for all checks — do NOT accept any,
do NOT pick by "likelihood." Proceed to Step 7. Append `equivalence-checked` and
`observability-assessed` (FZ2) entries to `hypothesis-log.md`.

#### Step 7. Deepen the model

Expand only where undistinguished hypotheses live. Directions: depth (code), depth (data),
depth (type contracts — check types at call boundary when function returns default value),
breadth (observability), breadth (concurrency). Append M<N>. Go back to Step 2.

#### Step 8. Terminate or iterate

**Termination conditions** (ALL must be true):

1. Exactly one hypothesis `compatible` (U1)
2. Has mechanism — causal chain (H1)
3. Has counterfactual (H2/FZ1)
4. Counterfactual observable with current telemetry (FZ2)
5. Counterfactual verified absent against production
6. No diagnostically equivalent alternatives (U1)
7. Alternative mechanism considered (M2)
8. All cause classes reviewed — Model Coverage filled (M1)
9. `direct` evidence supports conclusion (PV1)
10. No stale `direct` evidence (F5)
11. Evidence log has ≥1 `direct` entry (PW1)
12. Model re-run after last fact integration if built (PW2)
13. `mechanism-stated` logged (PW3/H1)
14. `counterfactual-stated` logged (PW3/H2)
15. `observability-assessed` logged with "observable" (PW3/FZ2)
16. `alternative-considered` logged (PW3/M2)
17. `equivalence-checked` logged (PW3/U1)
18. Status entries: one `compatible`/`accepted`, rest `rejected` (PW3/U1)
19. First evidence in each production-first step is `direct`/`inferred` (TC19)
20. Reliability tags match source classification table (F1)
21. Status transitions follow valid transition table (no `rejected`→anything)
22. Fix tasks: first S4 evidence is `direct` (F4)
23. Dynamic data: evidence verifies current value + change history + timeline (F3)
24. Absence claims: ALL sources queried, single-source = `inferred` (F6)
25. Wrong values: write path identified, not just read path (F7)
26. Numeric: exact computation if replicable; residual >5% blocks termination (F8)
27. Snapshot fields: confirmed live for current-state use (F9)
28. Formal model exists with solver results, OR `M1: Skipped (user-acknowledged)` (PV2)

If any fails, iterate. Before acceptance, append `alternative-considered` + `status-changed`
to `hypothesis-log.md`. Assemble report: Symptom, Conclusion, Hypothesis History, Evidence Log,
Hypothesis Log, Model Change Log, Model Coverage, Remaining Uncertainties, Next Steps.

---

## Proof of work logs

Three append-only logs, written as events happen. PW1: evidence log needs ≥1 `direct` entry.
PW2: model log needs ≥1 entry if model built, re-run after fact integration. PW3: hypothesis
log needs TC13-18 events.

**Evidence entry format:** `E<N>: [description]` with Step, Collected at, Source, Reliability,
Raw observation, Interpretation, Integrated?, Hypotheses affected, Verification query.
**F6-F9 optional fields:** `Absence sources: N/M` + verdict (F6), `Analysis type: write-path` +
`Producer identified` (F7), `Computation method` + `Residual` (F8), `Field temporality` +
`Last written` (F9). These are the audit trail TC24-27 check at termination.

**F5 staleness:** `direct` evidence goes stale after deploy/migration. Re-verify before acceptance.
If investigation spans sessions, re-verify all prior `direct` evidence.

**Model entry format:** `M<N>: [description]` with Step, Trigger, What changed, Solver result.

**Hypothesis entry format:** `H<id>-<N>: [event]` with Step, Hypothesis, Event (created |
mechanism-stated | counterfactual-stated | observability-assessed | alternative-considered |
status-changed | equivalence-checked), Detail, Linked evidence.

**Pre-acceptance log checklist** (mirrors TC1-28):
1. Evidence log has `direct` entry (PW1)
2. Model log has entry if built; re-run after facts (PW2)
3. `mechanism-stated` logged (H1)
4. `counterfactual-stated` logged (H2)
5. `observability-assessed` = observable (FZ2)
6. Counterfactual verified via `direct` evidence
7. `equivalence-checked` logged (U1)
8. `alternative-considered` logged (M2)
9. One `compatible`/`accepted`, rest `rejected` (U1)
10. No stale `direct` evidence (F5)
11. Model Coverage table filled (M1)
12. First evidence per production-first step is `direct`/`inferred` (TC19)
13. Reliability tags match source table (F1)
14. Status transitions follow valid table (no `rejected`→other)
15. Fix tasks: first S4 = `direct` (F4)
16. Dynamic data: current value + history + timeline (F3)
17. Absence: `Absence sources N/M` with N=M (F6)
18. Wrong values: `write-path` + `Producer identified` (F7)
19. Numeric: `exact-local` + `Residual ≤5%` (F8)
20. Snapshot: `Field temporality: live` for current-state (F9)
21. Model skip: `M1: Skipped (user-acknowledged)` with rationale (TC28/PV2)

If any fails, iterate.

---

## Protocol rules

**H1** — Every hypothesis: `[condition] -> [mechanism] -> [state change] -> [symptom]`.
**H2** — State what observation would make it false. No counterfactual = too vague.
**T1** — Every check: which hypotheses does it distinguish? Compatible with all = zero value.
**U1** — Accept only if no other hypothesis is compatible. If undistinguished → deepen, don't pick.
**U2** — Multiple compatible hypotheses: keep all active, do not collapse.
**M2** — Before accepting, name ≥1 alternative mechanism.

**M1 — blind spot checklist** (all must be reviewed before acceptance):
Concurrency, Shared mutable state, Object lifecycle, Caching, Async boundaries,
External systems, Partial observability, Config/feature flags, Data migration,
Tenant isolation, Auth state, Deployment drift, Multi-artifact versions, Build pipeline divergence.

**F1** — Tag every fact by source reliability. Never tag `interpreted` as `direct`.
**F2** — Absence ≠ evidence of absence. Could it be absent from your view but present in production?
**F3** — Dynamic data: check (1) current value, (2) change history, (3) timeline coverage.
**F6** — Zero-result query: list ALL sources, query each. Conclude absence only when all agree.
**F7** — Wrong value: trace WRITE paths (INSERT/UPDATE), not read paths. Match value to producer.
**F8** — Numeric discrepancy: compute exact locally before estimating. Residual >5% = compute instead.
**F9** — DB field as current state: check temporality (live/snapshot/scheduled). Snapshot = `inferred`.
**PV1** — ≥1 `direct` fact must support acceptance. Code reading alone is insufficient.
**PV2** — Formal model required. Skip only with user acknowledgement + documented tradeoff.
**FZ1** — State counterfactual for each hypothesis.
**FZ2** — Unobservable counterfactual blocks acceptance. Deepen observability, don't assume true.
**FM1** — ≥1 `direct` fact before building model. Sequence: verify → code → hypothesize → model → verify fix.

---

## Practical guidance

- **Always model.** A 20-line Dafny model beats 2000 words of prose. Start small, grow on demand.
- **Facts > structure.** One reliable fact eliminating a hypothesis class beats an elaborate model.
- **Name hypotheses consistently** (H1, H2, H3). Track rejections — they prove thoroughness.
- **User prompts are high-value checks.** Execute them immediately — the user's domain intuition
  targets blind spots the protocol misses. After each major conclusion, ask: "What would the user
  check that I haven't?"
- **Observe before reasoning.** Compute exact values (F8), query all tables (F6), trace write
  paths (F7), verify field liveness (F9) — don't reason where you can observe.

## Bundled files

- `tooling-inventory.md` — Template for tooling inventory. Copy into the project's
  `investigations/` directory and fill in. The skill reads it at Step 0a to avoid
  re-enumerating tools each investigation.
