# System Models — Textual Variant

Self-models for `formal-debugger-harness-textual`. Each `.md` file is a
read-only spec that the agent walks by hand against the evidence log.
No solver execution. No `.als` / `.dfy` artefacts.

The representation kinds used across these files are catalogued in
**`formal-debugger-harness-textual/references/representation-menu.md`** (the
skill-local master). It ships under the published skill's `references/`
directory, NOT under `self-models/`. Editing the menu happens there; the
self-models below cite it by name.

## Files

### Vocabulary

| File                                                        | What it carries                                                                 |
|-------------------------------------------------------------|--------------------------------------------------------------------------------|
| [`fdp_core.md`](fdp_core.md)                                | Shared atom definitions (Steps, Statuses, Reliability, SourceTypes, …) — type taxonomy |

### Lifecycle

| File                                                          | Replaces (canonical)                | Menu kinds                                  |
|---------------------------------------------------------------|-------------------------------------|---------------------------------------------|
| [`fdp_temporal_core.md`](fdp_temporal_core.md)                | `fdp_temporal_core.als` (altered: TC28) | state-machine + invariant-table             |
| [`fdp_skip_protocol.md`](fdp_skip_protocol.md)                | `fdp_skip_protocol.als`             | sequence-diagram + invariant-table          |

### Per-rule self-models

| File                                                            | Replaces                              | Rule(s)                | Menu kinds                                  |
|-----------------------------------------------------------------|---------------------------------------|------------------------|---------------------------------------------|
| [`fdp_source_classification.md`](fdp_source_classification.md)  | `fdp_source_classification.als`       | F3                     | decision-table + invariant-table            |
| [`fdp_baseline_comparability.md`](fdp_baseline_comparability.md)| `fdp_baseline_comparability.als`      | F10 / TC32             | decision-table + invariant-table            |
| [`fdp_intervention_ordering.md`](fdp_intervention_ordering.md)  | `fdp_intervention_ordering.als`       | OB1 / TC34             | invariant-table                             |
| [`fdp_symptom_proximity.md`](fdp_symptom_proximity.md)          | `fdp_symptom_proximity.als`           | S0-V.1 / TC31          | decision-table + invariant-table            |
| [`fdp_rejection_reasons.md`](fdp_rejection_reasons.md)          | `fdp_rejection_reasons.als`           | U2-doc / TC35          | schema + invariant-table                    |
| [`fdp_dynamic_data.md`](fdp_dynamic_data.md)                    | `fdp_dynamic_data.als`                | F3 dynamic / TC23      | schema + invariant-table                    |
| [`fdp_evidence_quality.md`](fdp_evidence_quality.md)            | `fdp_evidence_quality.als`            | F6 / F7 / F8 / F9      | invariant-table (with schema/decision-table accents) |
| [`fdp_fact_ordering.md`](fdp_fact_ordering.md)                  | `fdp_fact_ordering.als`               | F3 / F4 / TC19         | state-machine + invariant-table             |
| [`fdp_storage_chain.md`](fdp_storage_chain.md)                  | `harness/fdp_storage_chain.als`       | TC29 / TC30 / TC36     | dag + schema + invariant-table              |

## Files NOT translated (and why)

| Source file                                | Disposition                                         | Reason                                                                                      |
|--------------------------------------------|-----------------------------------------------------|---------------------------------------------------------------------------------------------|
| `system-models/fdp_protocol.als`           | dropped                                             | Monolith composing the segments above; the textual variant uses the segments directly       |
| `system-models/fdp_protocol.dfy`           | dropped                                             | Dafny-only; the textual variant has no solver, and every Dafny lemma corresponds to a row in one of the per-rule invariant tables above |
| `system-models/canonical/fdp_structured_chain.als` | not translated here                          | Canonical-variant filesystem-mode storage chain; the textual variant inherits the harness chain (`fdp_storage_chain.md`)              |

## How the textual self-models relate to the SKILL

`formal-debugger-harness-textual/SKILL.md` is the protocol the agent
follows; the files here are the **specification** of that protocol —
what the agent's outputs and gates must satisfy. Two layers:

1. **Self-models** (these files) describe the FDP protocol itself:
   what an investigation's record sequence must look like, which
   transitions are valid, which gates apply at which step.
2. **Per-investigation models** are what the agent **builds** at Step 1
   for the specific bug being investigated, also drawn from
   [`representation-menu.md`](representation-menu.md). They live under
   `investigations/<slug>/models/` (or as `ModelChange` items in
   hashharness, depending on the storage backend).

The two layers share one vocabulary (the menu); they differ in scope.
