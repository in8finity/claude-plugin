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

#### Step 0. Document the symptom

Create `./investigations/<slug>/` (kebab-case from symptom) with four files:
1. `investigation-report.md` — final report (start with `## Symptom`)
2. `evidence-log.md` — append-only evidence log (PW1)
3. `hypothesis-log.md` — append-only hypothesis log (PW3)
4. `model-change-log.md` — append-only model change log (PW2)

Formal model files (`.dfy`, `.als`) also go here. Append entries as events happen, not after.

**Blocking precondition (PW0-init).** Before proceeding to Step 0a, Claude MUST `Write` all
four files to disk with at minimum a top-level heading. Claude MUST NOT collect evidence,
read code, or run queries before these files exist on disk. Verify with a directory listing
and show it to the user. Stub files created retroactively do not satisfy this rule.

Pin down the symptom — ask and record: **What** (exact wrong behavior), **Where** (service,
endpoint), **When** (always? intermittent?), **For whom** (all users? specific?), **What is NOT
the symptom** (adjacent things that work). Assess severity: data exposure → security-critical,
financial impact → business-critical, data loss → data-integrity-critical, compliance (GDPR,
SOC2, PCI-DSS) → note explicitly. Write `## Symptom` + `**Severity:**` into the report.

#### Step 0a. Inventory tooling

Check `investigations/tooling-inventory.md` first (template at `<skill-dir>/templates/tooling-inventory.md`).
Determine: production DB, logs, metrics, tracing, error tracking, live API, config, queues,
repo, CI/CD. Write `## Tooling` noting `direct` vs `inferred` per tool.

#### Step 0b. Verify the symptom

**S0-V — symptom verification required.** Confirm the symptom with at least one `direct` fact
(production DB query, log, or live API observation) before Step 1. `interpreted` sources (reports,
specs, prior investigations) must be re-verified against production. Append E1 to `evidence-log.md`.
Update `## Symptom` with `**Verified by:**` citing E1.

**S0-V.1 — Symptom proximity check.** If the symptom is transport-shaped (DNS failure,
`gaierror`, connection refused, socket timeout, 5xx, health-check fail, "host not found"),
the first hypothesis MUST include "target process never started or crashed during startup."
Before investigating the transport layer, gather `direct` evidence of upstream liveness:
startup logs, container state, readiness probe, process list. If that evidence is
unavailable, Step 1 is observability (expose startup output), not topology.

#### Step 1. Build the minimal model

Requires `formal-modeling` skill. Check production logs/traces for the actual execution path
before writing model code. Append findings to `evidence-log.md`.

**Locating modeling tooling.** The `formal-modeling` skill ships the Alloy/Dafny runners
(`alloy_run.sh`, `dafny_run.sh`, `verify.sh`) and reference `.als`/`.dfy` examples. When
installed as a plugin, look under `~/.claude/plugins/marketplaces/*/skills/formal-modeling/`
(`scripts/` for runners, `references/` for example models). If not found there, check
`~/.claude/skills/formal-modeling/` or ask the user for the install path before proceeding.

**Default: create a formal model file** (`.dfy` for fast iteration, `.als` for counterexamples).
The verifier catches edge cases that narrative reasoning misses. Run it, don't just write it.

**Model skip — requires explicit user acknowledgement before writing the skip entry.**

Protocol (MUST follow in order):
1. Claude asks the user a single direct question: "Do you acknowledge skipping the formal
   model? Here is what it would verify: `<X>`. Here are the edge cases narrative reasoning
   misses: `<Y>`."
2. Claude WAITS for a user message. Silence, "ok", "continue", or any non-response is NOT
   acknowledgement. The reply must be an explicit affirmative ("yes, skip", "ack", "go ahead
   without the model", etc.).
3. ONLY after (2), Claude writes `M1: Skipped (user-acknowledged)` to `model-change-log.md`.
   The entry MUST quote the user's verbatim acknowledgement string under an
   `Acknowledgement:` field.
4. If the user's reply is ambiguous, Claude re-asks. Claude does NOT infer acknowledgement
   from context, priors, or prior sessions.

Forbidden pattern: writing `M1: Skipped (user-acknowledged)` in the same turn that proposes
the skip. The skip entry and the proposal MUST be in different turns separated by a user
reply.

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
**F10** — Baseline comparability: differential vs "last known good" requires same repo, trigger,
and config. Record `Baseline: <id> | repo=X trigger=Y config-diff=Z`. Mismatched baseline = `interpreted`.
**F11** — Workspace contamination: local/CI investigations must check for untracked/gitignored
files that mask CI failure. Run `<skill-dir>/scripts/check_workspace_clean.sh [paths]` (which
wraps `git ls-files --others --exclude-standard` + gitignored enumeration). Use `--source-only`
to filter common source extensions when noise is high. Record `Workspace clean: yes/no` on
evidence derived from local state.

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
28. Formal model exists with solver results, OR `M1: Skipped (user-acknowledged)` with an `Acknowledgement:` field quoting the user's verbatim affirmative reply from a turn AFTER the skip was proposed (PV2)
29. Log files were created at Step 0 before any Step 0b/1/4 activity (PW0-init). Verify file creation timestamp of each log precedes the earliest `Collected at` / entry timestamp recorded in it. Retroactive rebuild fails this check.
30. No burst writes (PW0-live). No two consecutive `E<N>`/`H<id>-<N>`/`M<N>` entries share the same `Turn:` value when that turn is the termination turn.
31. Transport-shaped symptom: upstream process liveness proven via `direct` evidence before transport investigation (S0-V.1)
32. Differential evidence: baseline repo/trigger/config match the failing run (F10)
33. Local/CI investigations: workspace contamination checked via `git status --ignored` (F11)
34. No system change preceded `direct` evidence of the changed state (OB1)

If any fails, iterate. Before acceptance, append `alternative-considered` + `status-changed`
to `hypothesis-log.md`. Assemble report: Symptom, Conclusion, Hypothesis History, Evidence Log,
Hypothesis Log, Model Change Log, Model Coverage, Remaining Uncertainties, Next Steps.

---

## Proof of work logs

Three append-only logs, written as events happen. PW1: evidence log needs ≥1 `direct` entry.
PW2: model log needs ≥1 entry if model built, re-run after fact integration. PW3: hypothesis
log needs TC13-18 events.

**PW0-init — stub files are a blocking precondition.** All four Step 0 files MUST exist on
disk (created via `Write`) before Step 0a begins. No evidence collection, code reading, or
queries may precede their creation. Verify via directory listing shown to the user.

**PW0-live — live append, not retroactive.** Every `E<N>`, `H<id>-<N>`, `M<N>` entry MUST
be written to its log file in the same turn the observation is made. Burst-writing entries
at the end is forbidden even if contents are correct. Each entry's first line MUST include
a `Turn:` field. Enforcement: if two consecutive entry numbers share a `Turn:` value AND
that turn is the termination turn, termination fails (TC30). Before acceptance, run
`<skill-dir>/scripts/check_pw0_live.py <investigation-dir>` — exit 0 is required.

**Evidence entry format:** `E<N>: [description]` with Turn, Step, Collected at, Source, Reliability,
Raw observation, Interpretation, Integrated?, Hypotheses affected, Verification query.
**F6-F9 optional fields:** `Absence sources: N/M` + verdict (F6), `Analysis type: write-path` +
`Producer identified` (F7), `Computation method` + `Residual` (F8), `Field temporality` +
`Last written` (F9). These are the audit trail TC24-27 check at termination.

**F5 staleness:** `direct` evidence goes stale after deploy/migration. Re-verify before acceptance.
If investigation spans sessions, re-verify all prior `direct` evidence.

**Model entry format:** `M<N>: [description]` with Turn, Step, Trigger, What changed, Solver result.

**Hypothesis entry format:** `H<id>-<N>: [event]` with Turn, Step, Hypothesis, Event (created |
mechanism-stated | counterfactual-stated | observability-assessed | alternative-considered |
status-changed | equivalence-checked), Detail, Linked evidence.

**Pre-acceptance log checklist** (mirrors TC1-30):
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
22. Stub files created at Step 0 before any evidence collection (TC29/PW0-init)
23. No burst writes on the termination turn (TC30/PW0-live)
24. Transport-shaped symptom: liveness proven before transport investigation (TC31/S0-V.1)
25. Differential baseline matches on repo/trigger/config (TC32/F10)
26. Workspace contamination checked when local/CI is involved (TC33/F11)
27. No intervention before direct evidence of the state changed (TC34/OB1)

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
**F10** — Baseline comparability: differential requires matching repo/trigger/config. Record the diff.
**F11** — Workspace contamination: check `git status --ignored` + `git ls-files --others` on local/CI mixes.
**OB1** — Observability before intervention. Don't change topology/config/code under investigation
until you have `direct` evidence of the state being changed. Blind intervention moves the target.
**PV1** — ≥1 `direct` fact must support acceptance. Code reading alone is insufficient.
**PV2** — Formal model required. Skip requires: (a) Claude asked, (b) user replied affirmatively in a later turn, (c) the user's verbatim reply is quoted in the skip entry. Inferring acknowledgement from silence, prior preferences, or memory is forbidden.
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

- `templates/tooling-inventory.md` — Template for tooling inventory. Copy into the project's
  `investigations/` directory and fill in. The skill reads it at Step 0a to avoid
  re-enumerating tools each investigation.
- `scripts/check_pw0_live.py` — TC30/PW0-live enforcement. Run against an investigation
  directory before acceptance: `python3 scripts/check_pw0_live.py investigations/<slug>`.
  Fails if any entry lacks a `Turn:` field or if two consecutive entries share the
  termination turn (the latest `Turn:` value across all three logs).
- `scripts/check_workspace_clean.sh` — TC33/F11 enforcement. Run against the paths
  relevant to the investigation: `scripts/check_workspace_clean.sh src/ bot/`. Fails
  if any untracked or gitignored files exist under those paths. `--source-only` filters
  to common source extensions when the noise floor is high (e.g., `.DS_Store`, build
  artifacts). Exit 0 = clean, 1 = contamination.
