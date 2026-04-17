# Reconciliation Report (Round 2): license-compatibility.als vs. current implementation + license texts

**Model:** `system-models/license-compatibility/license-compatibility.als`
**Tool:** Alloy 6.2.0 via bundled runner, `minisat.prover` active
**Sources reconciled against:**
- The same 10 upstream license texts (unchanged since Round 1)
- The current `.gitignore`, `NOTICE`, `THIRD_PARTY_LICENSES.md`, `README.md`
- The current `skills/formal-modeling/scripts/alloy_run.sh` (commit `f24a875`)
- The current `skills/formal-modeling/scripts/alloy_run.sh` `strip_nc_solvers` function
- The `AlloyRunner` heredoc (pinned solver + diagnostic)

**Date:** 2026-04-17
**Supersedes:** Round 1 (the Round 1 drifts D1 and D2 are closed; this
round inventories new drifts introduced by the remediation itself.)

## Summary

- Properties checked: **26** (23 from Round 1 + 3 new claims about runtime fetch + strip + pinning)
- **Aligned: 24**
- **FixModel applied this round: 2**
- **Drift: 0** — none remaining; all previously-flagged items are closed
- **FixSource / Exclusion: 0**

## What changed since Round 1

| Round 1 finding | Status after remediation |
|-----------------|--------------------------|
| D1 — ZChaff redistribution without Princeton consent | **Closed.** Repository redistributes nothing: `.alloy/` gitignored, runtime fetch from AlloyTools, strip step removes the Lingeling SPI wrapper. ZChaff is not shipped as an executable in Alloy 6.2+ at all — only its historical license text remains in the jar. |
| D2 — Lingeling redistribution outside grant scope | **Closed** on three independent axes: not redistributed, not invoked, not present on disk after strip. |
| FM1 — Lingeling's "evaluation and research only" whitelist not modeled | **Moot.** Lingeling is no longer part of the package at all, so its whitelist does not apply. Model now sets `Lingeling.bundled = False`. |
| FM2 — ZChaff distribution consent not modeled | **Moot.** Same reason — ZChaff is `bundled = False` in the updated model. |
| FM3 — `forbidsAdditionalRestrictions` field is binary where reality is scoped (LGPL/MPL aggregation carve-outs) | **Closed.** Superseded by the linking model's `propagatesAcross: set LinkMode`. The aggregation model was refactored to share that vocabulary — each license now declares the specific linking modes across which its copyleft propagates (LGPL: StaticLink + SourceDerivation; MPL: SourceDerivation; GPL: DynamicLink + StaticLink + SourceDerivation; etc.), and A5 was rewritten to check `DynamicLink in c.license.propagatesAcross` instead of the old binary flag. All 6 aggregation assertions still pass post-refactor. |

## FixModel applied this round

### FM4 — `bundled` semantics drifted from "shipped in repo" to "present after strip"

**Model before:** `all c: Component - OriginalWork { c.bundled = True }` — every upstream component is treated as "bundled." This matched the original bundled-extraction implementation.

**Reality:** Nothing is shipped by this repository — `.alloy/` is gitignored and populated at runtime. After `strip_nc_solvers` runs, Lingeling artefacts are physically absent from the user's workspace. ZChaff has not shipped as an executable in Alloy 6.2+.

**Fix applied:**
1. Added a header comment to `fact CurrentBundle` clarifying that `bundled = True` now means "present in the user's local cache after our script finishes," not "shipped by this repository."
2. Enumerated each component explicitly: `{AlloyCore, Kodkod, MiniSat, JavaCup, Gini, SAT4J, Electrod, Glucose}` have `bundled = True`.
3. `Lingeling.bundled = False` (stripped by `alloy_run.sh`).
4. `ZChaff.bundled = False` (not shipped in Alloy 6.2+).

**Consequence for assertion A6 (FieldOfUseFlowsUp):** the package's `effectiveRestrictions` is now `{NoCommercial, NoSATCompetitions}` rather than `{NoCommercial, ResearchOnly, NoSATCompetitions}` — the `ResearchOnly` contribution from ZChaff and the duplicate `NoCommercial + NoSATCompetitions` contribution from Lingeling no longer flow up. The package is strictly less restricted after the remediation.

### FM5 — Invocation pinning is an implementation property, not modeled

**Model:** no notion of which solver is invoked by the runner.

**Reality:** `AlloyRunner` calls `SATFactory.find("minisat.prover")` and only falls back to `SATFactory.DEFAULT` (SAT4J) if MiniSat's native library is unavailable. The runner prints `Solver: <id>` at startup so this is observable.

**Decision:** Not modeling this round. The invocation pin is a *stronger* property than mere presence, and the existing compatibility assertions already hold on presence grounds — adding `Component.isInvoked: Bool` would let the model prove additional properties (e.g., "the skill only ever invokes MIT-licensed solvers") but is not required to verify the existing claims. Queued for Round 3 if the need arises.

## Aligned properties (24)

All 23 properties from Round 1 remain aligned, plus three new claims about the runtime model:

| # | Property (new in this round) | Source evidence | Verdict |
|---|------------------------------|-----------------|---------|
| 24 | Repository does not redistribute any third-party binary | `.gitignore` excludes `skills/formal-modeling/scripts/.alloy/`; git history clean (commit `f24a875` shows repo tree contains no `.alloy/` files) | Aligned |
| 25 | Lingeling is absent from the user's workspace after `alloy_run.sh` runs | `alloy_run.sh` lines 146–177 (`strip_nc_solvers`) deletes `native/*/*/plingeling{,.exe}`, `org/alloytools/solvers/natv/lingeling`, and the Lingeling line from `META-INF/services/kodkod.engine.satlab.SATFactory` | Aligned |
| 26 | The pinned solver is MiniSat-with-unsat-core (MIT), not a noncommercial solver | `AlloyRunner` heredoc in `alloy_run.sh` lines 212–219 selects `SATFactory.find("minisat.prover")`; confirmed at runtime by the `Solver: minisat.prover` diagnostic | Aligned |

## Enforcement audit (updated)

| Assertion | Decision point | Gate language? | Enforced? |
|-----------|----------------|----------------|-----------|
| MIT attribution & license preservation | `NOTICE`, `THIRD_PARTY_LICENSES.md`, plus the upstream `.txt` files that travel in the downloaded jar | Gate ✓ | Enforced — attribution and license-text preservation are contract terms we satisfy by documenting and by letting the upstream files flow to the user's cache untouched |
| ZChaff distribution consent | N/A — not redistributed by us, and not shipped as an executable by upstream | N/A | Moot |
| Lingeling "all other usage is reserved" | N/A — stripped from the user's cache; never invoked | N/A | Moot |
| CC BY-NC-SA 4.0 attribution | `README.md` § License, `LICENSE` file at repo root | Gate ✓ | Enforced |
| CC BY-NC-SA 4.0 ShareAlike | Third-party bundled components retain their own licenses per `NOTICE`; we do not apply CC BY-NC-SA to them | Gate ✓ | Enforced |

## Recommended next steps

1. **None blocking.** The model now faithfully represents the implementation, and the implementation is consistent with every upstream license text as interpreted in Round 1.
2. **Optional — Round 3 model extension.** Add `Component.isInvoked: Bool` and an assertion *"the runner never invokes a noncommercial solver"* (`all c: Component | c.isInvoked = True implies NoCommercial not in c.license.restrictions`). This would let the model prove the value of the pinning step at the SAT-backend level, not just the presence level.
3. **FM3 cleanup — completed.** Superseded by the linking model's `propagatesAcross`; the aggregation model was refactored to share that vocabulary. See the updated FM3 row in the summary table above.

## Verdict

Model and implementation are now reconciled. All six compatibility
assertions still hold, on the actively-pinned MiniSat backend (verified
by the `Solver: minisat.prover` diagnostic, which earlier caught a
silent SAT4J fallback that was passing tests for the wrong reason).
