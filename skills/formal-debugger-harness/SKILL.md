---
name: formal-debugger-harness
description: >
  Structured bug investigation using formal models for hypothesis-driven debugging, with
  hashharness MCP storage as the append-only backend (experimental variant of formal-debugger).
  Builds scoped Alloy models (normative rules, data constraints, causal chains, observability)
  to generate distinguishing experiments and narrow the causality cone around a symptom. Use
  whenever the user reports a bug, incident, or unexpected behavior and wants rigorous
  investigation backed by hashharness's append-only hash-chained storage. Trigger on
  "investigate", "root cause", "debug this", "why does this happen", "find the bug", "postmortem",
  or any unexplained symptom. Valuable for: business-rule bugs, state machine errors, workflow
  inconsistencies, cross-service disagreements, investigations where the obvious explanation was
  already checked. Not for simple stack traces or typos — use when the problem space is large
  enough that unstructured search would waste time or miss the real cause.
---

# Formal Debugger (HashHarness variant)

> **Experimental variant**: this skill is the same investigation protocol as `formal-debugger`,
> but with the append-only record store backed by the hashharness MCP server instead of
> filesystem files. Several PW0-strict rules become storage invariants here (immutability,
> hash chain integrity, evidence-hash binding) — see the HashHarness mode notes in the
> branch's design doc and (forthcoming) parallel SKILL section.

Requires `formal-modeling` skill. Hypothesis accepted only when no other compatible hypothesis
remains undistinguished. **Production first** — prefer `direct` production queries over
`interpreted` code reading at every step.

#### Step 0. Document the symptom

The investigation is stored as **hashharness items** (an MCP server providing
append-only hash-chained text storage). All records — reports, hypothesis
events, evidence, model changes — are created through MCP tool calls.

The MCP tools are:
- `mcp__hashharness__set_schema` — declare item types and link rules (once per environment)
- `mcp__hashharness__get_schema` — read the current schema
- `mcp__hashharness__create_item` — create a new immutable item
- `mcp__hashharness__find_items` — search by `text`, `title`, `work_package_id`, or `all`
- `mcp__hashharness__get_item_by_hash` — fetch by `text_sha256`
- `mcp__hashharness__get_work_package` — fetch all items for one exact `work_package_id`
  (the canonical read path for the materialization protocol — see below)
- `mcp__hashharness__query_chain` — walk all referenced items transitively from a root
- `mcp__hashharness__verify_chain` — recompute and validate every hash in the reachable graph

Each investigation gets a unique `work_package_id` (kebab-case from the symptom, e.g.,
`webhook-drops-2pct`). All items for that investigation carry that `work_package_id` in
their metadata. The agent should also create `./investigations/<slug>/` as a human-facing
directory holding **derived markdown views** of the work package (regenerated on demand —
they are not the source of truth). Project-wide tooling lives in `./investigations/tooling-inventory.md`;
do not fork it per investigation.

Files under `./investigations/<slug>/`:
1. `work-package.md` — pointer file with `slug`, `work_package_id`, symptom sketch,
   Report v1's `text_sha256`, and the latest materialization timestamp
2. `investigation-report.md` — generated summary view of the current Report chain
3. `evidence-log.md` — generated view of all `Evidence` items
4. `hypothesis-log.md` — generated view of all `HypothesisEvent` items
5. `model-change-log.md` — generated view of all `ModelChange` items

These markdown files are **GENERATED VIEWS**, regenerated from hashharness whenever the
materialization protocol fires. The append-only proof remains the stored items. Do not
maintain markdown logs incrementally after every item creation.

Item types and links (set once via `set_schema` with this payload):

```json
{
  "types": {
    "Report": {
      "links": {
        "prevReport": {"kind": "single", "target_types": ["Report"]}
      }
    },
    "HypothesisEvent": {
      "links": {
        "prevHyp":         {"kind": "single", "target_types": ["HypothesisEvent", "Report"]},
        "citedEvidence":   {"kind": "many",   "target_types": ["Evidence"]},
        "supersedes":      {"kind": "single", "target_types": ["HypothesisEvent"]}
      }
    },
    "Evidence": {
      "links": {
        "parentHypEvent": {"kind": "single", "target_types": ["HypothesisEvent"]}
      }
    },
    "ModelChange": {
      "links": {
        "prevModel":      {"kind": "single", "target_types": ["ModelChange", "Report"]},
        "parentHypEvent": {"kind": "single", "target_types": ["HypothesisEvent"]}
      }
    }
  }
}
```

**Materialization protocol for readable logs.** Regenerate the four log markdown files
only when one of these is true:
- the user asks for clarification, status, or a human-readable summary
- the investigation reaches conclusion or handoff
- you (the agent) need to review prior reasoning across many records

When that happens:
1. Call `mcp__hashharness__get_work_package` for the active `work_package_id`. Optional
   per-type `find_items` calls are allowed for formatting, but the canonical read path is
   `get_work_package`.
2. Sort returned items by `created_at` (tie-break by `stored_at`, then `text_sha256`).
3. Rewrite `investigation-report.md`, `evidence-log.md`, `hypothesis-log.md`, and
   `model-change-log.md` from scratch — these are derived views, not append-only.
4. Start each generated file with a header containing: `Generated from hashharness via
   get_work_package`, `Work package: <id>`, `Generated at: <iso8601>`, `Source of truth:
   hashharness items`.
5. Include item timestamps, titles, hashes, text, and important links (`prev*`,
   `parent*`, `citedEvidence`, `supersedes`) so the markdown stays human-readable
   without hiding the chain structure.

`scripts/materialize.py <work_package_id> <output-dir>` is the canonical implementation
of this protocol — one MCP call to `get_work_package`, sort by created_at, write the
four markdown views with the correct headers. Use it instead of hand-rolling.

**What hashharness enforces automatically (was agent discipline in the filesystem variant):**

- **Append-only**: existing items are immutable. Calling `create_item` with the same
  `text` but different `links` or metadata returns `StorageError`. Nothing is ever
  deleted or rewritten.
- **Hash chain integrity**: every item's `record_sha256` is computed by the server from
  `text_sha256 + meta_sha256 + links_sha256`. The agent never computes hashes manually.
- **Link validation**: a link to an item that doesn't exist (or has the wrong type) is
  rejected at `create_item` time.
- **EvidenceHash equivalent**: for the `citedEvidence: many` link, the server stores a
  derived `citedEvidenceHash` field — sha256 of the sorted evidence-text-hashes. This is
  the structural equivalent of the old `EvidenceHash:` field but auto-derived.
- **Chain traversal and verification**: `verify_chain(text_sha256)` walks the full graph
  reachable from any item through its links and recomputes every hash. Returns `ok: true`
  iff the graph is consistent.

**Four parallel chains, same as the filesystem variant — but expressed as hashharness links:**

1. **Report chain** — `Report` items chain via `prevReport`. The first report has no
   `prevReport`; it is the genesis anchor for everything.
2. **Hypothesis chain** — `HypothesisEvent` items chain via `prevHyp`. The first H event
   anchors on the genesis Report (cross-type link).
3. **Evidence parent links** — `Evidence` items attach upward to a `HypothesisEvent` via
   `parentHypEvent`. Evidence is not chained to other evidence.
4. **Model-change chain + parent** — `ModelChange` items chain via `prevModel` AND attach
   to the triggering H event via `parentHypEvent`.

State-change events (a `HypothesisEvent` whose `text` indicates `event=status-changed`
or `event=accepted`) carry the `citedEvidence: many` link. The auto-derived
`citedEvidenceHash` is the integrity binding — any later evidence change would produce
a different hash, but evidence is also immutable so this binding is permanent.

**Symptom-verification anchor.** At Step 0b, after creating Report v1 (the genesis),
the first thing to create is an H0-1 `HypothesisEvent` with `event=symptom-claimed` and
`prevHyp` linked to Report v1. Then E1 attaches to H0-1 via `parentHypEvent`. This
keeps the "evidence must attach to a hypothesis event" rule consistent from the very
first evidence.

**Blocking precondition (PW0-init).** Before proceeding to Step 0a, Claude MUST:
1. Verify the schema is set via `mcp__hashharness__get_schema`. If empty, call
   `mcp__hashharness__set_schema` with the payload above. (This is normally a one-time
   environment setup, but verify per-investigation.)
2. Choose a `work_package_id` and a `slug` (kebab-case from symptom). Create
   `./investigations/<slug>/` and write `work-package.md` with: the `slug`,
   `work_package_id`, symptom sketch, and a placeholder for Report v1's hash.
3. Create Report v1 via `mcp__hashharness__create_item` with `item_type=Report`, no
   `prevReport` link, and the symptom sketch as the `text`. Update `work-package.md`
   with the returned `text_sha256`.
4. Show the user the resulting `text_sha256` of Report v1 AND the path to
   `./investigations/<slug>/work-package.md`.

Claude MUST NOT collect evidence, read code, or run queries before Report v1 exists
AND `work-package.md` is on disk. PW0-init requires both: storage acknowledgement of
Report v1's creation AND the human-pointer file existing.

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
specs, prior investigations) must be re-verified against production.

Make three sequential `mcp__hashharness__create_item` calls:

1. **H0-1 (symptom-claimed anchor):** `item_type=HypothesisEvent`,
   `links={"prevHyp": <Report v1 text_sha256>}`, `text` describes the symptom claim
   (e.g., `event=symptom-claimed; the symptom is real and worth investigating`).

2. **E1 (verifying evidence):** `item_type=Evidence`,
   `links={"parentHypEvent": <H0-1 text_sha256>}`, `text` is the actual `direct` observation
   (production DB result, log line, live API response).

3. **Report v2:** `item_type=Report`, `links={"prevReport": <Report v1 text_sha256>}`,
   `text` is the updated narrative now noting that the symptom is verified by E1.
   Reference E1's `text_sha256` in the prose for human readability.

The hashharness server returns each item's `text_sha256` in the response. Use that hash
when forming subsequent links — never invent or synthesize a hash. There is nothing to
"do not edit" — the storage layer makes Report v1 immutable on creation.

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

**Default: create a formal model file AND run the solver in the same step.** Use `.dfy` for
fast iteration, `.als` for counterexamples. Building the model and running the solver are
one atomic step — a `.dfy`/`.als` file without a `Solver result:` field in `model-change-log.md`
does NOT satisfy TC28. "Model exists but solver deferred pending evidence" is NOT an allowed
state.

Consequences:
- If constraints are too sparse to run usefully (e.g., waiting for S0-V.1 liveness evidence),
  do one of: (a) defer MODEL CREATION until Step 4 evidence arrives, (b) run the solver
  anyway on the sparse model — unsat or a minimal counterexample is still signal that narrows
  the hypothesis space, or (c) propose a skip per the protocol below.
- A solver run that times out counts as a run; record the timeout and which assertions were
  tried. Partial results still satisfy TC28 when accompanied by a documented next step.
- The M<N> entry MUST include the `Solver result:` field per the hypothesis-entry format.
  An M1 entry without a solver result is a protocol violation caught by the termination gate.

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
29. Schema set, `work-package.md` created, and Report v1 created at Step 0 before any Step 0b/1/4 activity (PW0-init). `mcp__hashharness__get_schema` returns the four type definitions; `mcp__hashharness__get_work_package` returns Report v1 under the chosen `work_package_id`; `./investigations/<slug>/work-package.md` exists on disk pointing at the work package. No items of other types exist yet.
30. Valid hashharness chain integrity (PW0-live). `mcp__hashharness__verify_chain` from the latest `HypothesisEvent` (or any tip item) returns `ok: true` for every reachable item. The server validates: (a) every item has a valid `text_sha256`/`meta_sha256`/`links_sha256`/`record_sha256`; (b) every link points to an existing item of the declared `target_types`; (c) every `citedEvidence` link's auto-derived `citedEvidenceHash` matches the sha256 of the sorted referenced hashes; (d) Report/Hypothesis/Model chains follow valid type sequences via their respective `prev*` links.
31. Transport-shaped symptom: upstream process liveness proven via `direct` evidence before transport investigation (S0-V.1)
32. Differential evidence: baseline repo/trigger/config match the failing run (F10)
33. Local/CI investigations: workspace contamination checked via `git status --ignored` (F11)
34. No system change preceded `direct` evidence of the changed state (OB1)
35. Every `rejected` hypothesis has a valid `Reason:` (evidence-based with `Evidence: E<N>`, or preference-based with an allowed `Priority:` + `Rationale:`) in its `status-changed` log entry (U2-doc)
36. Single-record write discipline observed throughout the investigation (PW0-strict): each item was created by exactly one `mcp__hashharness__create_item` call; no multi-item batch helper was used; pre-write narration was present for each chain record (item type, intended links by hash, intended `text` and `title`).

If any fails, iterate. Before acceptance, write an `alternative-considered` and a
`status-changed` event file under `hypothesis/`. Assemble report: Symptom, Conclusion,
Hypothesis History, Evidence Log, Hypothesis Log, Model Change Log, Model Coverage,
Remaining Uncertainties, Next Steps. The report may reference the individual record files
by name (e.g., "E1, E4, and H2-3 together rule out ...").

---

## Proof of work records

Records live as hashharness items addressed by `text_sha256`. PW1: at least one
`Evidence` item with `direct` reliability. PW2: at least one `ModelChange` item
if a model is built, re-run after fact integration. PW3: a `HypothesisEvent`
item for each TC13-18 lifecycle event.

**PW0-init — schema set and Report v1 created.** Before Step 0a begins:

1. Verify schema via `mcp__hashharness__get_schema`. If empty or missing any of the
   four types (`Report`, `HypothesisEvent`, `Evidence`, `ModelChange`), call
   `mcp__hashharness__set_schema` with the payload from Step 0.
2. Choose a `work_package_id` (kebab-case from the symptom).
3. Create Report v1 via `mcp__hashharness__create_item`:
   `item_type=Report`, `work_package_id=<chosen>`, `text=<symptom sketch>`,
   no `links` (no `prevReport` — this is the genesis).
4. Show the user the returned `text_sha256`.

No evidence collection, code reading, or queries may precede this. PW0-init is
satisfied by the storage acknowledgement of Report v1's creation.

**PW0-live — append-only hashharness storage with chain integrity.** Most of what
PW0-live used to demand from the agent (timestamp validity, chain hashes, evidence
freezing, immutability) is now enforced by the storage layer. What remains:

1. **Use the right item types and links.** Each record is exactly one
   `mcp__hashharness__create_item` call with the right `item_type` and `links`
   per the schema. A wrong link kind or unknown target type is rejected by the
   server.
2. **Use returned hashes only.** Every link value (in `prevHyp`, `parentHypEvent`,
   `prevReport`, `prevModel`, `citedEvidence`, `supersedes`) MUST be the
   `text_sha256` of an item that already exists in storage and was just returned
   by a prior `create_item` call (or fetched via `find_items` / `query_chain`).
   Never invent or guess a hash.
3. **`work_package_id` consistency.** All items in one investigation share the
   same `work_package_id`. Mixing values in one investigation is a PW0-live
   violation even if every individual item is well-formed.
4. **`verify_chain` clean at termination.** Before acceptance, call
   `mcp__hashharness__verify_chain` on the latest item (or any tip — the chain
   reaches everything). The result MUST be `ok: true` for every reachable item.

What hashharness gives you for free (no agent discipline required):
- Append-only / immutability (rewrites with same `text` and different links are
  rejected with `StorageError`)
- All four chains (Report, H, E, M) — server validates the link references at
  `create_item` time
- `citedEvidenceHash` — automatically derived from the sorted evidence text-hashes
  inside the `citedEvidence: many` link. The agent never computes this.
- `record_sha256` integrity — recomputed by `verify_chain`

What is NO LONGER part of the protocol (vs filesystem-mode):
- Filename timestamp suffixes. Items are named by their content hash.
- In-record `Timestamp:` field maintained by the agent. Each item has a server-
  recorded `created_at` instead. Timestamp manipulation is not a vector.
- `Timestamp:` vs filesystem ctime check. There is no filesystem.
- Burst detection. Storage immutability + append-only chain validation provides
  the integrity those checks were trying to approximate.

**PW0-strict — single-create discipline.** The append-only storage closes the
"delete the broken record" loophole automatically (storage refuses), but the
batch-fix shortcut at the agent level is still possible: the agent could write
a Python script that loops over `mcp__hashharness__create_item` calls. PW0-strict
remains binding to prevent that.

1. **One `create_item` per record.** Each H/E/M/Report item is created by exactly
   one `mcp__hashharness__create_item` tool call. No script, loop, or helper that
   issues multiple `create_item` calls in one pass.
2. **No multi-item batch helpers.** It is NEVER acceptable to write a Bash/Python
   script that creates multiple items, even for "fixups," even for setup, even
   for "convenience."
3. **Append-only is automatic — but don't try to work around it.** Storage
   refuses rewrites. Don't propose deleting items from the data directory
   directly to bypass storage. If a record is wrong, the only remedy is a
   `Supersedes` link from a new item (see rule 5).
4. **If `verify_chain` fails, repair item-by-item.** When verification reports
   violations on multiple items, fix each with its own `create_item` call (or
   `Supersedes` superseder). Do not write a script to "fix all the broken
   ones at once." If a single-pass repair feels like the right move, that is
   the signal PW0-strict is binding.
5. **Supersedes mechanism for repairing broken state-changes.** A state-change
   `HypothesisEvent` whose cited evidence has been semantically replaced (an
   `Evidence` item that should no longer be the basis for a decision, possibly
   because a more recent Evidence item supersedes its meaning) is repaired by
   creating a NEW `HypothesisEvent` with `links={"supersedes": <broken-state-
   change text_sha256>, "prevHyp": <latest H tip>, "citedEvidence": <fresh list>}`.
   The old item stays in storage as historical fact (storage immutability
   guarantees this; deletion is not even possible).

   `verify_chain` is currently structural — it doesn't have semantic
   "supersedes excuses validation gaps" logic the way `check_pw0_live.py`
   does, because the structural chain stays valid by construction (no
   `EvidenceHash` to go stale, since `citedEvidenceHash` is auto-derived from
   the actual current cited items). The only sense in which a state-change
   "becomes wrong" is semantic, not structural — the agent or user decides
   the citation is no longer the right basis. The fix is the same: append a
   `Supersedes` superseder.

6. **Cost is not a justification.** Permission prompts, tokens, round-trips
   are costs the user accepts in exchange for integrity. "It's faster to do
   this in one pass" is never a reason to violate the rules above.

7. **Pre-create narration.** Before each `mcp__hashharness__create_item` call,
   state in one sentence: the `item_type`, the `work_package_id`, the `links`
   you intend to send (each as a label like "H0-1's text_sha256: <hex>"), and a
   one-line summary of the `text` you will store. This narration is the audit
   trail of construction discipline; skipping it is itself a PW0-strict
   violation.

The forbidden patterns:
- Drafting all the items first then issuing many `create_item` calls in rapid
  succession from a script. Even if the chain validates, this violates rule 1.
- Manipulating the hashharness data directory directly to "clean up" or
  "reset" mid-investigation. Storage is the source of truth; bypassing it
  is forging the audit trail.
- Treating storage immutability as license to skip pre-create narration.
  Mechanical correctness ≠ deliberate construction.

**Item shapes per type.** hashharness items carry `text` (prose narrative),
`links` (typed references), AND `attributes` (a structured dict for queryable
fields). Use `attributes` for anything you'd otherwise want to grep — event
type, status values, reliability tags — and reserve `text` for the prose a
human reviewer reads.

`attributes` are JSON-serializable and included in the item's `meta_sha256`,
so they're tamper-evident the same way the rest of the record is.

- **Report**:
  - `attributes`: `{"version": <int>, "step": "<step-id>", "severity":
    "<level>"}` where `step` is one of `0`, `0b`, `4`, `7`, `8` (the step at
    which this snapshot was made) and `severity` is one of
    `security-critical`, `business-critical`, `data-integrity-critical`,
    or `normal`.
  - `text`: the narrative snapshot — Symptom, Tooling, findings, Conclusion.
  - `links`: `{"prevReport": <prior report hash>}` for v2+; none for v1.

- **HypothesisEvent**:
  - `attributes`: `{"event": "<event-type>", "hypothesis_id": "H1",
    "event_seq": <int>}` where `event` is one of `symptom-claimed | created |
    mechanism-stated | counterfactual-stated | observability-assessed |
    alternative-considered | status-changed | equivalence-checked | accepted`.
    For `status-changed`, also include `"new_status": "<rejected|compatible|
    weakened|undistinguished|accepted>"` and `"reason": "<evidence|preference>"`.
    For `reason=preference`, also include `"priority": "<allowed-name>"` and
    `"rationale": "<one-line text>"`.
  - `text`: the prose content of the event — the hypothesis claim, the
    mechanism, the counterfactual, the observation summary, the rationale
    explanation. What a human would read to understand the reasoning.
  - `links`: `{"prevHyp": <prior H or Report v1 hash>}`. For state-change
    events add `"citedEvidence": [<E hash>, ...]`. To repair an earlier
    state-change add `"supersedes": <broken H hash>`.

- **Evidence**:
  - `attributes`: `{"evidence_id": "E1", "source": "<source-name>",
    "reliability": "<direct|inferred|interpreted|unreliable-source>"}`.
    Plus optional F6-F9 audit fields when applicable: `"absence_sources":
    "N/M"`, `"verdict": "..."`, `"analysis_type": "write-path"`,
    `"producer_identified": true`, `"computation_method": "exact-local"`,
    `"residual": "0%"`, `"field_temporality": "live|snapshot|scheduled"`,
    `"last_written": "<iso>"`.
  - `text`: the actual observation — query result, log line, value, raw
    interpretation in prose.
  - `links`: `{"parentHypEvent": <H event hash>}`.

- **ModelChange**:
  - `attributes`: `{"model_id": "M1", "step": <int>, "trigger":
    "<initial|fact-integration|deepening|fix-verification|skip>",
    "solver_result": "<sat|unsat|timeout|partial|skipped>"}`. For
    `trigger=skip`, also include `"acknowledgement": "<verbatim user reply>"`.
  - `text`: what changed in the model, optionally embedded `.als`/`.dfy`
    snippets, observed solver behavior in prose.
  - `links`: `{"prevModel": <prior M hash, or Report v1 for the first M>,
    "parentHypEvent": <triggering H hash>}`.

The protocol checkers (e.g., `scripts/check_rejection_reasons.py`) read from
`attributes` directly. Putting structured fields in `attributes` instead of
hand-parsed `text` makes the integrity binding stronger (any later edit would
change `meta_sha256`) and the queries faster.

**F5 staleness:** `direct` evidence goes stale after deploy/migration. Re-verify
before acceptance. Re-verification means creating a NEW Evidence item linked to
the same parent (or to a fresher hypothesis event if appropriate); the old
Evidence item stays in storage as the historical observation.

**Pre-acceptance log checklist** (mirrors TC1-36):
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
28. Every `rejected` hypothesis has a documented `Reason:` + backing field (TC35/U2-doc)
29. Single-record write discipline observed (TC36/PW0-strict): one `Write` per record, fresh `Bash` calls for time and predecessor hash, no multi-file write/repair helpers, pre-write narration present

If any fails, iterate.

---

## Protocol rules

**H1** — Every hypothesis: `[condition] -> [mechanism] -> [state change] -> [symptom]`.
**H2** — State what observation would make it false. No counterfactual = too vague.
**T1** — Every check: which hypotheses does it distinguish? Compatible with all = zero value.
**U1** — Accept only if no other hypothesis is compatible. If undistinguished → deepen, don't pick.
**U2** — Multiple compatible hypotheses: keep all active, do not collapse.
**U2-doc** — Every `status-changed` entry to `rejected` MUST carry a `Reason:` field:
`Reason: evidence` + `Evidence: E<N>` (cite the specific entry) OR
`Reason: preference` + `Priority: <name>` + `Rationale: <text>`.
Allowed `Priority:` values: `Occam`, `BlastRadius`, `Severity`, `RecencyOfDeploy`,
`Reproducibility`, `FixCost`. Any other priority must be raised to the user first.
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
**PW0-strict** — One `Write` per record, with fresh `Bash` calls for time and predecessor hash.
No multi-file write/repair helpers. If a checker fails, fix each affected file individually with
a new `Bash` + `Write` per file — do NOT write a script that batches the fix. Cost (tokens,
prompts, round-trips) is not a justification. Pre-write narration: state file, Timestamp,
PrevHash before each Write.
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
**MCP tools (replace most of the helper scripts in the filesystem variant):**

- `mcp__hashharness__set_schema` / `get_schema` — schema declaration
- `mcp__hashharness__create_item` — single record creation (one call per record)
- `mcp__hashharness__find_items` — search by `text`/`title`/`work_package_id`/`all`
- `mcp__hashharness__get_item_by_hash` — fetch by `text_sha256`
- `mcp__hashharness__query_chain` — walk transitively from a tip
- `mcp__hashharness__verify_chain` — recompute and validate every hash; the TC30
  acceptance check

**Token-efficient wrapper scripts.** Direct `mcp__hashharness__create_item`
calls from the agent are verbose — both the request and response carry the
full item content. To cut token cost, the skill ships per-record bash-style
wrapper scripts that translate CLI args to MCP HTTP calls and return ONLY
the new `text_sha256`. They talk to hashharness purely through the MCP HTTP
API (no direct storage import), keeping the agent on the protocol surface.

**Setup (once per machine):**

Run hashharness as a long-running HTTP MCP server (separate terminal or
launchd/systemd service):

```
HASHHARNESS_MCP_TRANSPORT=http \
HASHHARNESS_HTTP_PORT=8765 \
HASHHARNESS_DATA_DIR=$HOME/workspace/hashharness/data \
python3 -m hashharness.mcp_server
```

The wrapper scripts default to `http://127.0.0.1:8765/mcp`; override with
`HASHHARNESS_HTTP_URL`. To avoid races with a separate stdio MCP server
spawned by Claude Code, point both transports at the same data dir but only
run one at a time, OR configure Claude Code's MCP to use HTTP transport
against this same server.

**Wrapper scripts (one create_item per invocation — preserves PW0-strict):**

- `scripts/record_report.py` — create one Report. Args:
  `--version`, `--step`, `--severity`, `--title`, `--text`,
  `[--prev-report <hash>]`. Stdout: new `text_sha256`.
- `scripts/record_h_event.py` — create one HypothesisEvent. Args:
  `--event`, `--hypothesis-id`, `--event-seq`, `--prev-hyp`, `--title`,
  `--text`, plus optional `--cited-evidence`, `--supersedes`, `--new-status`,
  `--reason`, `--priority`, `--rationale`.
- `scripts/record_evidence.py` — create one Evidence. Args:
  `--evidence-id`, `--source`, `--reliability`, `--parent-hyp-event`,
  `--title`, `--text`, plus F6-F9 audit fields.
- `scripts/record_model_change.py` — create one ModelChange. Args:
  `--model-id`, `--step`, `--trigger`, `--solver-result`, `--prev-model`,
  `--parent-hyp-event`, `--title`, `--text`, optional `--acknowledgement`
  (for `--trigger=skip`).
- `scripts/audit.py <work_package_id>` — pre-acceptance summary.
  Combines `verify_chain` (TC30) + `check_rejection_reasons` (TC35) into a
  single concise output. Returns exit 0 if all checks pass.
- `scripts/materialize.py <work_package_id> <output-dir>` — render the four
  human-readable markdown views (`investigation-report.md`, `evidence-log.md`,
  `hypothesis-log.md`, `model-change-log.md`) from the hashharness store via
  `get_work_package`. The canonical implementation of the materialization
  protocol — use this rather than hand-rolling. Files are rewritten from
  scratch each run; they are derived views, not the source of truth.
- `scripts/check_rejection_reasons.py <work_package_id>` — TC35/U2-doc
  enforcement on its own. Queries the store via MCP HTTP, reads each
  rejection's structured `attributes`, validates the schema.
- `scripts/check_workspace_clean.sh [paths...]` — TC33/F11 enforcement.
  Untouched from filesystem variant; F11 is a filesystem concern in the
  dev workspace, independent of hashharness.

**PW0-strict (rule 1) is preserved:** each script invocation is exactly one
`create_item` over the wire — no batching. The fact that the script is
shorter than the equivalent direct MCP call doesn't make it "less of a
write." Pre-create narration (rule 7) still applies: state intent before
each `Bash` invocation.

**Falling back to direct MCP tools.** If the HTTP server is not running, or
for ad-hoc queries (e.g., one-off `find_items` to navigate a chain), use
the `mcp__hashharness__*` tools directly. The wrappers are an
optimization, not a replacement.

The filesystem variant of formal-debugger ships a different set of helpers
(`sha256_file.py`, `evidence_hash.py`, `now_iso.py`, etc.). None apply here
— hashing is internal to hashharness.
