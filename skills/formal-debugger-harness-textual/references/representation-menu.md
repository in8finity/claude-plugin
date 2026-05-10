# Representation Menu — Textual Formal Debugger

Catalogue of textual-only representation kinds used by the
`formal-debugger-hashharness-textual` variant. Every reference model in this
variant is expressed as a combination of one or more entries below — never as
Alloy or Dafny source. The agent reads these representations as design-doc
material; nothing here is meant to be executed.

Each representation is paired with the Alloy patterns from
`formal-modeling/references/alloy-patterns.reference` that it textualises, so
the lineage from the runtime variants is traceable.

---

## Menu

| # | Representation       | Format                                              | Carries                                                           |
|---|----------------------|-----------------------------------------------------|-------------------------------------------------------------------|
| 1 | State machine        | Mermaid `stateDiagram-v2` + transition table        | Lifecycle, status flow, allowed step orderings                    |
| 2 | Sequence diagram     | Mermaid `sequenceDiagram` with actor lanes          | Multi-actor protocols, ordering, preconditions per call           |
| 3 | DAG / dependency     | Mermaid `graph LR` / `flowchart`                    | Chains, pipelines, link/anchor structure, acyclicity              |
| 4 | Schema block         | Fenced YAML or JSON-Schema-style block              | Item shapes, link rules, field-level constraints, payload formats |
| 5 | Decision / lookup    | Markdown table                                      | Mappings, role×state×field access, recipient sets, type semantics |
| 6 | Invariant table      | Markdown table (`id ‖ rule ‖ why ‖ trigger ‖ how-to-verify-by-hand`) | Standalone checks, freshness guards, symmetry, conservation laws |
| 7 | Type taxonomy        | Nested bullet list                                  | Disjoint subtypes, ordered enums, severity/reliability ladders    |
| 8 | Worked example       | Before/after fenced block with narration            | Concrete scenario traces, counterexample-style illustrations      |

---

## Selection rule

For any reference model, pick **the smallest combination that carries the
content losslessly**. Typical combinations seen in this variant:

- **Lifecycle / status model** → #1 + #6
- **Write protocol / multi-step interaction** → #2 + #4 + #6
- **Storage chain / link integrity** → #3 + #4 + #6
- **Classification rule (e.g. source → reliability)** → #5 + #7
- **Standalone assertion family (e.g. rejection-reasons)** → #5 + #6
- **Scenario illustration** → #8 alongside one of the above

If two entries fit equally well, prefer the one earlier in the menu
(state machines and sequence diagrams beat tables for behavioural content;
schemas beat prose for shape constraints).

---

## Per-entry details

### 1. State machine

Mermaid `stateDiagram-v2` block followed by a transition table.

- **States** — one per reachable status; `[*]` is the entry pseudostate.
- **Transitions** — labelled with the trigger (action/event); guards go in
  parentheses on the same arrow.
- **Transition table** — rows of `from → to | trigger | guard | postcondition`
  for everything the diagram shows, plus any *forbidden* transitions called
  out explicitly.
- **Invariants on states** — appended as bullet list under the table; one
  bullet per `always`-style claim from the source model.

Replaces Alloy patterns: 8 (Soft-Delete Lifecycle), 17 (Temporal State
Machine), 31 (Artifact Versioning lifecycle).

### 2. Sequence diagram

Mermaid `sequenceDiagram` with explicit `participant` declarations.

- **One lane per actor** — agent, MCP server, filesystem, external service.
- **Numbered steps** — every message gets a number; the same number anchors
  preconditions and postconditions in the prose under the diagram.
- **Notes for invariants** — `Note over X: invariant` for anything that must
  hold across a span of messages.
- **Forbidden interleavings** — listed as a "Disallowed" subsection beneath
  the diagram, each with the concrete violation it would represent.

Replaces Alloy patterns: 11 (Cross-System Integration), 16 (Event Sigs
emission), 20 (Nested Eventually), 29 (Sliding Window), 36 (Concurrency).

### 3. DAG / dependency graph

Mermaid `graph LR` (or `flowchart`) showing nodes and directed edges.

- **Nodes** — items, artifacts, schema versions, build outputs.
- **Edges** — labelled with the link kind (e.g. `prevReport`, `citedEvidence`,
  `Supersedes`).
- **Acyclicity / anchoring constraints** — listed as bullets beneath the
  graph; "every chain anchors on Genesis", "Supersedes is acyclic", etc.
- **Cardinality** — annotated on edges (`1`, `0..1`, `*`) when it matters.

Replaces Alloy patterns: 14 (Chain/Linked List), 30 (Pipeline DAG).

### 4. Schema block

Fenced YAML (preferred for hashharness item shapes — matches the
`set_schema` payload) or JSON-Schema-style block.

- **One block per item type** — fields with types, required-ness, allowed
  values.
- **Link declarations** — `kind: single | set`, `target_types`, `required`,
  `chain_predecessor` flag.
- **Cross-references** — to the invariant table (#6) for any rule that
  cannot be expressed structurally in the schema.

Replaces Alloy patterns: 9 (Partial Unique Index), 16 (Event Sigs shape),
26 (Data Format Mismatch), 27 (DB Column Types), 33 (Proof of Work),
48 (Compositional Interface).

### 5. Decision / lookup table

Markdown table whose row-key is the input and whose column(s) are the
output(s) of a deterministic function.

- **Header row** — names of the input dimensions and output(s).
- **Total coverage** — every input combination must have a row, or the table
  must end with a "default / otherwise" row that covers the remainder.
- **Provenance column** — when the rule was added (e.g. F-rule id) so the
  reader can trace it back to source.

Replaces Alloy patterns: 21 (Access Matrix), 22 (CTA Validity),
23 (Notification Recipients), 24 (Template→Trigger), 25 (Axiomatic
Conversion), 28 (Effect Bag), 38 (Resolved Choice).

### 6. Invariant table

Markdown table with columns:

| id | kind | rule | why | trigger | how to verify by hand |
|----|------|------|-----|---------|------------------------|

- **id** — stable identifier (e.g. `TC30`, `F6`, `OB1-Late`).
- **kind** — one of `protocol | data | observability | setup`. *protocol*:
  invariants of the system under study (state transitions, contracts).
  *data*: invariants over stored values. *observability*: invariants about
  what should be visible (logs, metrics, traces). *setup*: invariants
  binding production-state to replay-state or experiment-state — the
  anchors for Step-2 assumptions audit rows. Treat any new `setup` row as
  a candidate A-row; it is the strongest place for an unstated premise to
  hide.
- **rule** — one sentence, present tense, falsifiable.
- **why** — the failure mode the rule prevents.
- **trigger** — when in the investigation flow this check applies.
- **how to verify by hand** — concrete steps the agent or a reviewer can
  execute against the artifacts (no solver). Cite tool calls, file paths,
  field names.

Replaces Alloy patterns: 12 (Cache Consistency), 13 (Pair Symmetry),
32 (Freshness Guards), and every standalone Alloy `assert` whose content is
"if precondition then postcondition" without a temporal trace.

### 7. Type taxonomy

Nested bullet list, optionally with a one-line gloss per leaf.

- **Top level** — the abstract type.
- **Children** — disjoint subtypes; ordered enums get a numeric prefix to
  encode the order.
- **Annotations** — bracketed tag per leaf when reliability/severity matters
  (e.g. `[direct]`, `[interpreted]`, `[unreliable]`).

Replaces Alloy patterns: 10 (Platform Mutual Exclusion), 15 (Ordered Enum
Chain).

### 8. Worked example

Before/after fenced block with narration.

- **Setup** — minimal world: which items exist, what their key fields are.
- **Action** — the one operation under test, written as a tool-call sketch
  or narrative step.
- **Outcome** — what changes; for counterexample-style illustrations, what
  rule the outcome violates.
- **Cross-reference** — to the invariant table row (#6) the example bears
  on.

Replaces Alloy patterns: 34 (Scenario Predicates), plus narrative versions
of any `run` instances that earlier variants relied on.

---

## What is intentionally not in the menu

The following Alloy patterns have no textual analogue and are simply
absent from this variant:

- Patterns 1-7 — `Bool`/`Enum`/`lone`/`fun`/comprehension/lookup/`Int`
  ranges. These are Alloy syntax for expressing the patterns above; the
  textual variant uses native Markdown/YAML constructs instead.
- Pattern 18 — relation override `++`. Implementation idiom for state-machine
  updates; subsumed by entry #1's transition semantics.
- Pattern 19 — frame conditions / stutter. Same: subsumed by #1.
- Pattern 35 — scoping and cardinality. A solver knob, not content.
- Pattern 37 — gap assertion (intentional failure). Becomes a note in
  entry #6 under `id` (e.g. `GAP9 — known gap, see <link>`).
- Patterns 39-47 — Alloy 6 essentials (ordering alias, `until`, `disj`,
  module parameters, sequences, inductive structure, `expect`,
  equivalence classes). Pure Alloy syntax.

If a reference model in formal-debugger relies primarily on these patterns,
its content is either dropped (it was a syntactic scaffold) or relocated
into one of entries #1-#8 (it was actually expressing one of those shapes
under the hood).
