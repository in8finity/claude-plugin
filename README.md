# Formal Methods Plugin for Claude Code

A Claude Code plugin that brings formal verification and hypothesis-driven debugging to your workflow using [Alloy 6](https://alloytools.org/) and [Dafny](https://dafny.org/).

## Skills

### formal-modeling

Write, run, and interpret formal models for software systems, business processes, and skill/workflow design. Pick the right tool for the job:

- **Alloy 6** for bounded counterexamples, instance generation, temporal models, and UX/pipeline verification
- **Dafny** for unbounded proofs over data invariants, pre/post-conditions, and fast iteration

Catches design bugs — race conditions, invariant violations, impossible states, stale caches, hollow verification — before they become production incidents.

**When to use:** state machines, lifecycle flows, data invariants, API contracts, permission matrices, business rules, temporal ordering, cache coherence, pipeline dependencies, role×state×field access, notification recipient sets.

**Example prompts:**
- "Model my order system states and check that cancelled orders can't be shipped"
- "Verify our multi-tenant RBAC rules — every workspace must have exactly one owner"
- "Prove that the approval workflow can't skip the dual-approval step for orders over $10k"

**What it does:**
1. Translates requirements into an Alloy 6 or Dafny model (style chosen by verification need)
2. Runs the model through a local pipeline — Alloy via bundled Java runner, Dafny via `dafny verify`
3. Interprets results — Alloy counterexamples become concrete bug reports; Dafny failures pinpoint the violated assertion
4. Iterates with you to refine the model until all invariants hold

**Workflow:**

1. **Build the model.** Pick a style — static (data invariants, permission matrices), temporal (state machines, lifecycles, concurrency), or UX/access-control (role × state × field) — and write facts + assertions + runs.
2. **Review boundaries (quality gate).** Before running, mark every element of the system as `Include` / `ExcludeSafe` / `ExcludeRisky` / `Stub`. Risky exclusions must carry a gap assertion documenting what's lost. No model proceeds without facts, assertions, and run scenarios.
3. **Run and interpret.** Solver output becomes either a concrete counterexample (explain exactly which interleaving breaks the assertion) or a pass (explain what the check actually guarantees, not just "it's green").
4. **Reconcile against source artifacts.** Compare every assertion to the real code, specs, tests, and docs. Each property gets a verdict: `Aligned`, `FixModel` (model is wrong), `FixSource` (source has the bug), `Drift` (spec and impl disagree), or `Exclusion` (intentionally out of scope). The reconciliation report is persisted to `./system-models/reports/{domain}-reconciliation.md` — no iteration happens until it exists on disk.
5. **Enforcement audit** (for natural-language sources like runbooks, skills, compliance docs). For each `Aligned` rule, check three things: is it at the **decision point** (not buried elsewhere), does it use **gate language** (`must`, `requires`, `blocks`) rather than advisory language (`consider`, `should ideally`), and is the **audit chain** intact — what the gate checks must be recorded in a named field with a recording instruction. A rule proven by the model but absent from the gate, or present in advisory language, is **mentioned but unenforced**. Persist to `./system-models/reports/{domain}-enforcement.md`.
6. **Iterate.** Only after both reports exist, fix the model or the source and re-run. Changes to either side trigger a new reconciliation pass.

### formal-debugger

Structured bug investigation using formal models for hypothesis-driven root cause analysis. Turns vague symptoms into falsifiable hypotheses with concrete verification plans, backed by an append-only evidence log.

**When to use:** intermittent bugs, business-rule violations, state machine errors, workflow inconsistencies, cross-service disagreements, incidents where the obvious explanation was already checked.

**Example prompts:**
- "Orders sometimes get stuck in 'processing' — help me investigate systematically"
- "Users occasionally see another user's data on their dashboard"
- "Billing is overcharging customers after plan downgrades"

**What it does:**
1. Pins down the symptom (what, where, when, for whom, what is NOT the symptom) and assesses severity
2. Inventories available tooling (prod DB, logs, metrics, tracing) — distinguishes `direct` vs `inferred` evidence
3. Verifies the symptom with at least one direct production fact before building any model
4. Builds a minimal 4-layer model (normative rules, data constraints, causal chains, observability)
5. Generates competing hypotheses in the form `[condition] → [mechanism] → [state change] → [symptom]`
6. Designs distinguishing experiments ranked by diagnostic power
7. Iterates — each fact narrows the causality cone until one hypothesis remains

**Dependency:** Requires the `formal-modeling` skill (included in this plugin) for the model runner pipeline.

## Skills are formally verifiable

A Claude skill is a workflow: steps, artifacts, dependencies, and quality gates. That makes it exactly the kind of thing formal modeling can verify. This plugin does it to itself — `skills/formal-modeling/self-models/` contains Alloy and Dafny models of the `formal-modeling` skill's own pipeline, boundary decisions, and quality gate. Run `scripts/verify.sh --self` to check them. Use the models as a template for proving properties about your own skills.

## Prerequisites

- **Java 11+** — required to run the Alloy 6 solver (bundled in `skills/formal-modeling/scripts/.alloy/`)
- **Python 3** — required for formatting solver output
- **Dafny** (optional but recommended) — `brew install dafny` on macOS, or `dotnet tool install --global dafny`. Needed only when using Dafny models.

## Installation

All commands below are slash commands — type them inside a Claude Code session. There is no `claude plugin ...` shell subcommand; plugin management runs entirely through `/plugin` and friends.

### 1. Add the marketplace

**From GitHub:**

```
/plugin marketplace add <your-username>/morozov-claude-plugin
```

**From a local clone:**

```
/plugin marketplace add /absolute/path/to/morozov-claude-plugin
```

### 2. Install the plugin

```
/plugin install formal-methods@morozov-claude-plugin
```

### 3. Manage plugins

```
/plugin                                              # open the plugin UI (Installed tab lists enabled plugins)
/plugin disable formal-methods@morozov-claude-plugin
/plugin enable  formal-methods@morozov-claude-plugin
/reload-plugins                                      # pick up changes after editing the plugin locally
```

### 4. Verify

Start a new Claude Code session and type `/` — you should see the `formal-modeling` and `formal-debugger` skills listed. Or ask Claude directly: *"use the formal-modeling skill to check a tiny state machine"*.

### 5. Reducing permission prompts (optional)

The plugin's scripts run via Claude Code's Bash tool and trigger a permission prompt on first invocation. Claude Code's plugin system does not support pre-declared allowlists, so this is a one-time friction by design. If you use the skill often and want to skip the prompts, add the scripts to your project's `.claude/settings.json` or user-level `~/.claude/settings.json`:

```json
{
  "permissions": {
    "Bash": {
      "allow": [
        "skills/formal-modeling/scripts/alloy_run\\.sh",
        "skills/formal-modeling/scripts/dafny_run\\.sh",
        "skills/formal-modeling/scripts/verify\\.sh"
      ]
    }
  }
}
```

Purely optional — nothing breaks without it. The `/less-permission-prompts` skill (bundled with Claude Code) can also populate this allowlist from your transcript.

## Structure

```
.claude-plugin/
  marketplace.json          # Marketplace manifest
  plugin.json               # Plugin manifest
skills/
  formal-modeling/
    SKILL.md                # Skill definition
    references/             # Alloy + Dafny pattern libraries and worked examples
                            #   (static, temporal, UX verification, pipeline, e-commerce,
                            #    feature flags, data conversion)
    scripts/
      alloy_run.sh          # Alloy runner
      alloy_format.py       # Alloy output formatter
      dafny_run.sh          # Dafny runner
      dafny_format.py       # Dafny output formatter
      verify.sh             # Unified runner — routes .als → Alloy, .dfy → Dafny;
                            #   supports --self for skill self-verification
      eval_*.sh             # Eval harness scripts
                            # (.alloy/ is a gitignored runtime cache — alloy_run.sh
                            #  fetches the jar from AlloyTools on first use, then pins
                            #  minisat.prover (MIT) with sat4j (LGPL) fallback)
    self-models/            # Self-verifying models of the skill's own pipeline
                            #   (skill_pipeline.als, skill_pipeline.dfy, boundary,
                            #    decisions, quality)
  formal-debugger/
    SKILL.md                # Skill definition
    tooling-inventory.md    # Template for Step 0a tooling inventory
```

## License

Copyright (c) 2026 Alexander Morozov.

**Original work** in this repository (SKILL.md files, Alloy/Dafny models, scripts, references, plugin manifests) is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License (CC BY-NC-SA 4.0)](https://creativecommons.org/licenses/by-nc-sa/4.0/). See [`LICENSE`](./LICENSE) for the full legal code.

You are free to share and adapt the material for non-commercial purposes, provided you give appropriate attribution and distribute any derivative works under the same license.

**Commercial use** — using this plugin as part of paid development work, or shipping derivative works commercially, requires a separate commercial license. See [`COMMERCIAL.md`](./COMMERCIAL.md) for who needs one, what it grants, and how to request one. Your own code, models, and reports produced with help from the plugin are not derivative works and remain yours regardless of license tier — the formal analysis is at [`system-models/derived-claude-code-work/report.md`](./system-models/derived-claude-code-work/report.md).

**Third-party components** — the Alloy 6 distribution is downloaded at runtime by `scripts/alloy_run.sh` from the official AlloyTools GitHub releases, not redistributed by this repository. The skill's `AlloyRunner` pins `minisat.prover` (MIT, with unsat-core support) as the SAT backend and `sat4j` (LGPL) as platform fallback — ZChaff and Lingeling are present in the downloaded distribution but never invoked. See [`NOTICE`](./NOTICE) and [`THIRD_PARTY_LICENSES.md`](./THIRD_PARTY_LICENSES.md) for the full breakdown.

The runtime-fetch + pinning design is documented in [`system-models/reports/license-compatibility-reconciliation.md`](./system-models/reports/license-compatibility-reconciliation.md) — it keeps this repository out of the ZChaff/Lingeling redistribution chain while preserving commercially-compatible solver capability for users whose downstream use may not be noncommercial.
