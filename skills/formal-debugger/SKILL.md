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

Create `./investigations/<slug>/` (kebab-case from symptom) with this layout:
1. `investigation-report-<N>_<timestamp>.md` — versioned narrative snapshots (PW1).
   Multiple files: `investigation-report-1_<ts>.md` at Step 0 (symptom only),
   `investigation-report-2_<ts>.md` after Step 0b, additional versions as the
   investigation progresses, and a final version at termination.
2. `evidence/` — one file per evidence entry E<N> (PW1)
3. `hypothesis/` — one file per hypothesis event H<id>-<N> (PW3)
4. `model-changes/` — one file per model change M<N> (PW2)

Formal model files (`.dfy`, `.als`) go at the investigation root.

**Report versioning.** Reports are immutable once written; new information produces a new
versioned file rather than an edit in place. Each report from version 2 onward carries a
`PrevReportHash:` field = `sha256(previous-report-file-bytes)`, forming a report chain
parallel to the hypothesis and model chains. The first report (`investigation-report-1_*`)
has no `PrevReportHash:`; it is the genesis anchor for all three chains — hypothesis, model,
and report.

Each record is its OWN file — no monolithic append logs. Filename format:
`E1_2026-04-25T10-30-45-123Z.md`, `H1-2_2026-04-25T10-31-00-456Z.md`,
`M1_2026-04-25T10-40-00-789Z.md`. The suffix is an ISO 8601 timestamp with millisecond
precision, using `-` in place of `:` and `.` (filesystem-safe, sortable, greppable). Each
record also carries a `Timestamp:` field with the full ISO 8601 value (with colons and
decimal ms) INSIDE the file, e.g., `Timestamp: 2026-04-25T10:30:45.123Z`.

**Chain structure — three relationships, not one flat chain.**

1. **Hypothesis events chain to each other** — the causal-reasoning trail. Each hypothesis
   record (H<id>-<N>) carries `PrevHypHash:` = `sha256(previous-hypothesis-event-file)`,
   where "previous" is the H event with the next-lower `Timestamp:`. The first H event's
   `PrevHypHash:` anchors to `sha256(investigation-report-1_*.md)` — the first (genesis) report.
2. **Evidence attaches to a hypothesis event** — evidence exists to serve a specific check
   or state transition. Each E record carries `ParentHypEvent: H<id>-<N>` identifying the
   hypothesis event it was collected for, and `ParentHypHash: sha256(parent-file)` snapshotting
   that parent at collection time. Evidence does NOT chain to other evidence.
3. **Model-changes both chain and attach** — each M record carries `PrevModelHash:`
   (sha256 of previous M, anchored on `sha256(investigation-report-1_*.md)` for the first)
   AND `ParentHypEvent:` / `ParentHypHash:` identifying which hypothesis context triggered
   the model iteration.
4. **Reports chain to each other** — each `investigation-report-<N>_*.md` with N≥2 carries
   `PrevReportHash:` = `sha256(investigation-report-<N-1>_*.md)`. The first report has no
   `PrevReportHash:`; it is the genesis for all three parallel chains.

**State-change events freeze their evidence.** When a hypothesis record is a `status-changed`
event (to `compatible`, `weakened`, `rejected`, `undistinguished`, `accepted`), it carries
`Evidence: [E<N>, E<M>, ...]` listing the specific evidence it rests on, plus `EvidenceHash:`
= `sha256(sorted-concat-of-evidence-file-sha256s)`. Any later edit to any referenced
evidence record invalidates the state-change's `EvidenceHash` — evidence becomes immutable
once cited in a state transition.

**Symptom-verification anchor.** At Step 0b, before collecting E1, write `H0-1: symptom-claimed`
as the root anchor event. Its `PrevHypHash:` = `sha256(investigation-report-1_*.md)`. E1
then links to H0-1 as its `ParentHypEvent:`. This keeps the "evidence must attach to a
hypothesis event" rule consistent from the very first evidence.

**Precondition.** Before writing any record, its parent (or chain predecessor) must exist
on disk with ALL required fields. You cannot write H1-2 without H1-1 being complete; you
cannot write E3 without its parent H event being complete; you cannot write a `status-changed`
event without its cited evidence being complete. This makes construction sequential by
necessity and makes the dependency graph explicit.

Why this works instead of forcing sleeps: batch-flushing the whole structure at session end
requires either (a) honest `Timestamp:` values matching wall-clock during the flush — caught
by filesystem-provenance — or (b) backdated timestamps — also caught by filesystem-provenance.
Meanwhile, the chain and reference hashes prevent any retroactive insert, reorder, or edit
of a record that has already been cited or chained from.

**Blocking precondition (PW0-init).** Before proceeding to Step 0a, Claude MUST create
`investigation-report-1_<timestamp>.md` (the first report, with just the symptom sketch)
plus the three subdirectories (`evidence/`, `hypothesis/`, `model-changes/`) on disk.
Claude MUST NOT collect evidence, read code, or run queries before these exist on disk.
Verify with a directory listing and show it to the user. Retroactive stub creation does
not satisfy this rule.

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

First write `hypothesis/H0-1_<timestamp>.md` with `Event: symptom-claimed` and
`PrevHypHash: sha256(investigation-report-1_*.md)` — this anchors the hypothesis chain. Then
write `evidence/E1_<timestamp>.md` with `ParentHypEvent: H0-1` and `ParentHypHash:` set to
the sha256 of H0-1's file bytes. Then write `investigation-report-2_<timestamp>.md` (the
updated narrative now including `**Verified by:** E1`) with `PrevReportHash:` = sha256 of
`investigation-report-1_*.md`. Do NOT edit the first report — write a new version.

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
29. Investigation layout was created at Step 0 before any Step 0b/1/4 activity (PW0-init). `investigation-report.md` + three subdirectories (`evidence/`, `hypothesis/`, `model-changes/`) exist on disk. Filesystem ctime of each subdirectory precedes the earliest `Timestamp:` field value of any record inside it. Retroactive rebuild fails this check.
30. Valid structured hash integrity and filesystem provenance (PW0-live). (a) Every record file has a `Timestamp:` field in ISO 8601 UTC with millisecond precision; (b) `investigation-report-<N>_*.md` files chain via `PrevReportHash:` (first report has none); (c) hypothesis records form a valid SHA-256 chain via `PrevHypHash:` anchored on `sha256(investigation-report-1_*.md)`; (d) evidence records have a valid `ParentHypEvent:` + `ParentHypHash:` pointing to an existing hypothesis event; (e) model-change records chain via `PrevModelHash:` and have valid `ParentHypEvent:` + `ParentHypHash:`; (f) every `status-changed`/`accepted` hypothesis record has a matching `EvidenceHash:` over the cited `Evidence:` list; (g) each record's in-field `Timestamp:` matches filesystem ctime within 60 seconds.
31. Transport-shaped symptom: upstream process liveness proven via `direct` evidence before transport investigation (S0-V.1)
32. Differential evidence: baseline repo/trigger/config match the failing run (F10)
33. Local/CI investigations: workspace contamination checked via `git status --ignored` (F11)
34. No system change preceded `direct` evidence of the changed state (OB1)
35. Every `rejected` hypothesis has a valid `Reason:` (evidence-based with `Evidence: E<N>`, or preference-based with an allowed `Priority:` + `Rationale:`) in its `status-changed` log entry (U2-doc)
36. Single-record write discipline observed throughout the investigation (PW0-strict): each E/H/M record was written by exactly one `Write` call, preceded by `Bash` calls to `now_iso.py` and `sha256_file.py` for fresh values; no multi-file write/repair helper was used; pre-write narration was present for each chain record

If any fails, iterate. Before acceptance, write an `alternative-considered` and a
`status-changed` event file under `hypothesis/`. Assemble report: Symptom, Conclusion,
Hypothesis History, Evidence Log, Hypothesis Log, Model Change Log, Model Coverage,
Remaining Uncertainties, Next Steps. The report may reference the individual record files
by name (e.g., "E1, E4, and H2-3 together rule out ...").

---

## Proof of work records

Three per-record subdirectories, one file per event. PW1: `evidence/` needs ≥1 `direct`
entry. PW2: `model-changes/` needs ≥1 file if a model is built, re-run after fact
integration. PW3: `hypothesis/` needs TC13-18 events across the hypothesis lifecycle.

**PW0-init — stub layout is a blocking precondition.** `investigation-report.md` plus the
three subdirectories (`evidence/`, `hypothesis/`, `model-changes/`) MUST exist on disk
before Step 0a begins. No evidence collection, code reading, or queries may precede their
creation. Verify via directory listing shown to the user.

**PW0-live — per-record files with structured hash integrity.** Each E, H, M event is its
OWN file with a timestamp suffix in the filename, a `Timestamp:` field inside, and
reference-hash fields tying it to its dependencies. Enforcement (TC30) is four-part:

1. **No missing Timestamp:** every record file must have a `Timestamp:` field in ISO 8601
   UTC form with millisecond precision (e.g., `Timestamp: 2026-04-25T10:30:45.123Z`).
2. **Hypothesis chain valid:** hypothesis records sorted by `Timestamp:` form a valid
   SHA-256 chain. Each H record's `PrevHypHash:` equals `sha256(previous-H-file-bytes)`.
   First H record's `PrevHypHash:` equals `sha256(investigation-report-1_*.md)`.
3. **Evidence parent link valid:** every E record has `ParentHypEvent: H<id>-<N>` pointing
   to an existing H event, and `ParentHypHash:` equals `sha256(parent-H-file-bytes)`.
   Evidence is not cross-chained. Model-change records have `ParentHypEvent:` +
   `ParentHypHash:` the same way, and additionally chain via `PrevModelHash:` to the
   previous M (or `sha256(investigation-report-1_*.md)` for the first M).
   Reports with N≥2 chain via `PrevReportHash:` = `sha256(investigation-report-<N-1>_*.md)`.
4. **State-change EvidenceHash valid:** hypothesis records with `Event: status-changed`
   (or `accepted`) include `Evidence: [E<N>, ...]` and `EvidenceHash:` = SHA-256 over
   the sorted concatenation of the cited evidence files' own SHA-256 hashes. Any later
   edit to any cited evidence invalidates this hash. Evidence records become immutable
   once cited in a state transition.
5. **Filesystem provenance:** the in-field `Timestamp:` must match the file's creation
   time within 60 seconds. Large disagreement = backdated record.

These checks together make the following attacks detectable:
- Retroactive insert/reorder/edit of a hypothesis event → hypothesis chain mismatch
- Fake evidence attached to a closed state-change → EvidenceHash mismatch
- Evidence tampered with after being cited → EvidenceHash mismatch
- Orphan evidence without a parent → missing `ParentHypEvent:` or mismatched `ParentHypHash:`
- Batch-flush at session end → filesystem-provenance mismatch (if timestamps backdated)
  or matched wall-clock mismatch (if timestamps honest but clustered)

Records can be written at whatever pace the investigation runs — the structure enforces
sequential dependencies without requiring artificial sleeps.

Before acceptance, run `<skill-dir>/scripts/check_pw0_live.py <investigation-dir>` — exit 0
is required.

**PW0-strict — single-record write discipline.** This is the binding rule that prevents
batch-fix shortcuts. The structural integrity of the chain only holds if each record was
actually constructed sequentially against the live state of its predecessor.

1. **One Write per record.** Each E/H/M record is written by exactly one `Write` tool call,
   immediately preceded by `Bash` calls that read the current wall-clock time and the
   predecessor's SHA-256. Use `scripts/now_iso.py` and `scripts/sha256_file.py`. The
   `Timestamp:` and `PrevHypHash:`/`ParentHypHash:`/`PrevModelHash:`/`PrevReportHash:`/
   `EvidenceHash:` values MUST be the values returned by those calls — never synthesized,
   never derived from a multi-file write helper.

2. **No multi-file write helpers.** Read-only helpers that compute hashes or timestamps
   for a single record (`sha256_file.py`, `evidence_hash.py`, `now_iso.py`) are allowed
   and encouraged. Any Bash/Python invocation that *writes*, *edits*, or *rechains* two
   or more record files in a single pass is forbidden — including for "fixups" after a
   check fails, including for setup of test fixtures, including for "convenience."

3. **Append-only forever. Never delete or rewrite a record.** Once an E/H/M/Report file
   is written, its bytes are immutable — and its existence on disk is permanent. Deletion
   of a broken record is NOT a permitted "fix." Renaming, moving, or rewriting in place
   is also forbidden. If a record is wrong, the only remedy is to write a NEW record that
   supersedes it (see rule 6 below). The broken record stays on disk as a visible
   historical fact — the audit trail must record the mistake, not pretend it never happened.

4. **If a checker fails, repair file-by-file.** When `check_pw0_live.py` or
   `check_rejection_reasons.py` reports violations across multiple files, the fix is to
   repair each affected record individually with a fresh `Bash` call to `now_iso.py`
   and a fresh `Write`. Do not write a script to fix multiple files at once. Do not
   propose one. If a "single-pass repair" feels like the right move, that is the signal
   that PW0-strict is binding — write the next single file instead.

5. **Cost is not a justification.** Permission prompts, tool round-trips, and context
   size are costs the user accepts in exchange for the integrity the protocol provides.
   "Batching saves tokens / round-trips / prompts" is not a valid reason to violate any
   of the rules above.

6. **Supersedes mechanism for repairing broken records.** When a record needs correction
   (e.g., a state-change with stale `EvidenceHash:` after evidence was tampered with), the
   repair is a NEW state-change record carrying a `Supersedes: H<id>-<N>` field naming the
   record it replaces. The new record has its own fresh `Timestamp:`, `PrevHypHash:` (linking
   to whichever record currently has the highest Timestamp), `Evidence:`, and `EvidenceHash:`
   values. The original broken record stays on disk untouched. The supersession itself is
   part of the audit trail.

   `check_pw0_live.py` excuses a superseded record from per-record validity checks where
   "the broken state IS the audit trail":
   - Check 4 (state-change `EvidenceHash:` validity) — skipped for superseded records
   - Check 5 (filesystem provenance: `Timestamp:` vs ctime within 60s) — skipped for
     superseded records

   Other checks still apply transitively because they're about the record's relationship
   to OTHER records, not the record's own validity:
   - Check 2 (hypothesis chain via `PrevHypHash:`) — successors of a superseded record
     still chain to its content hash; supersession doesn't break the chain
   - Check 3 (evidence parent links) — `ParentHypHash:` reflects what the parent's content
     was at attachment time, which doesn't change under supersession

   So if you supersede a state-change whose ctime has drifted (e.g., the file was touched
   long after its in-field `Timestamp:`), the check passes once the superseder is in place.
   The drift on the historical record is acknowledged, not erased.

7. **Pre-Write narration.** Before each Write of a chain record, state in one sentence:
   the file being written, the `Timestamp:` value just read from `now_iso.py`, and the
   PrevHash/ParentHash/EvidenceHash value just computed. This narration is the audit
   trail of construction discipline; skipping it is itself a PW0-strict violation.

The forbidden patterns:
- Drafting all the records' content first, then writing them in rapid succession with
  timestamps computed in a loop. Even if the chain mechanically validates, this
  violates rule 1.
- Deleting a broken record to make a check pass. The audit trail must record the
  mistake; rule 3 forbids deletion regardless of what it would "fix."
- Treating "deletion" as distinct from "edit" — both are forbidden mutations of disk
  state. The rule is append-only at the filesystem level, not just at the file-content
  level.

**Report record format:** A file at `investigation-report-<N>_<timestamp-suffix>.md` where
`<N>` starts at 1 and increments with each new version. Required fields in the body:
`Timestamp:` (ISO 8601 UTC ms), and `PrevReportHash:` (sha256 of the previous report file)
for N≥2. The first report has no `PrevReportHash:`. Narrative content (Symptom, Severity,
Tooling, and later Conclusion / Hypothesis History / etc.) follows.

**Evidence record format:** A file at `evidence/E<N>_<timestamp-suffix>.md` with first line
`E<N>: [description]`, followed by required fields: `Timestamp:` (ISO 8601 UTC ms),
`ParentHypEvent:` (the H record it serves, e.g., `H1-2` or `H0-1` for symptom verification),
`ParentHypHash:` (sha256 of the parent H file at collection time), Step, Source, Reliability,
Raw observation, Interpretation, Integrated?, Hypotheses affected, Verification query.
**F6-F9 optional fields:** `Absence sources: N/M` + verdict (F6), `Analysis type: write-path` +
`Producer identified` (F7), `Computation method` + `Residual` (F8), `Field temporality` +
`Last written` (F9). These are the audit trail TC24-27 check at termination.

**F5 staleness:** `direct` evidence goes stale after deploy/migration. Re-verify before acceptance.
If investigation spans sessions, re-verify all prior `direct` evidence.

**Model record format:** A file at `model-changes/M<N>_<timestamp-suffix>.md` with first
line `M<N>: [description]`, followed by required fields: `Timestamp:` (ISO 8601 UTC ms),
`PrevModelHash:` (sha256 of previous M, or sha256 of investigation-report.md for the first),
`ParentHypEvent:` (triggering H event), `ParentHypHash:` (sha256 of that parent H at the
time of this model change), Step, Trigger, What changed, Solver result.

**Hypothesis record format:** A file at `hypothesis/H<id>-<N>_<timestamp-suffix>.md` with
first line `H<id>-<N>: [event]`, followed by required fields: `Timestamp:` (ISO 8601 UTC ms),
`PrevHypHash:` (sha256 of previous H record — or sha256 of investigation-report.md for the
first H, which is H0-1 at Step 0b), Step, Hypothesis, Event (symptom-claimed | created |
mechanism-stated | counterfactual-stated | observability-assessed | alternative-considered |
status-changed | equivalence-checked), Detail.

For `Event: status-changed` (any target status) or `Event: accepted`, additionally include:
`Evidence: [E<N>, E<M>, ...]` listing the specific evidence that justifies this transition,
and `EvidenceHash:` = SHA-256 over the sorted concatenation of the cited evidence files'
own SHA-256 hashes. For `status-changed` to `rejected`, also add `Reason:` — either
`evidence` + `Evidence: E<N>` (the evidence list also populates the EvidenceHash) OR
`preference` + `Priority:` (from the allowed set) + `Rationale:` (non-empty text; a
preference-based rejection still needs `Evidence: []` + `EvidenceHash:` = sha256 of empty
concatenation).

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
- `scripts/check_pw0_live.py` — TC30/PW0-live enforcement. Run against an investigation
  directory before acceptance: `python3 scripts/check_pw0_live.py investigations/<slug>`.
  Fails if any entry lacks a `Turn:` field or if two consecutive entries share the
  termination turn (the latest `Turn:` value across all three logs).
- `scripts/check_workspace_clean.sh` — TC33/F11 enforcement. Run against the paths
  relevant to the investigation: `scripts/check_workspace_clean.sh src/ bot/`. Fails
  if any untracked or gitignored files exist under those paths. `--source-only` filters
  to common source extensions when the noise floor is high (e.g., `.DS_Store`, build
  artifacts). Exit 0 = clean, 1 = contamination.
- `scripts/check_rejection_reasons.py` — TC35/U2-doc enforcement. Run against an
  investigation directory: `python3 scripts/check_rejection_reasons.py investigations/<slug>`.
  Flags `status-changed`-to-`rejected` entries missing `Reason:`, using `preference`
  without an allowed `Priority:`, or missing `Evidence:`/`Rationale:` backing fields.
- `scripts/sha256_file.py <path>` — print SHA-256 hex of one file. Use for computing
  `PrevHypHash:`, `PrevModelHash:`, `PrevReportHash:`, and `ParentHypHash:` values.
- `scripts/evidence_hash.py <file> [<file> ...]` — compute `EvidenceHash:` for a
  state-change record. Hashes each input individually, sorts the hex digests, concatenates,
  then takes sha256 of the result. Order-independent (same inputs → same hash regardless
  of argument order).
- `scripts/now_iso.py [--filename]` — current UTC timestamp with millisecond precision.
  Default form is the in-field `Timestamp:` value (`2026-04-25T10:30:45.123Z`); `--filename`
  gives the filename-safe form (`2026-04-25T10-30-45-123Z`) with `:` and `.` replaced by `-`.
- `scripts/iso_to_filename.py <iso>` / `--reverse <filename>` — convert between the two
  timestamp forms.
- `scripts/time_delta.py <earlier> <later>` — signed time delta in seconds with ms
  precision. Accepts either canonical or filename-safe ISO form. Useful for verifying
  the 60s filesystem-vs-field tolerance and for computing investigation span.
