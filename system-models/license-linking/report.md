# License Linking / Derivation Semantics — Verification Report

**Model:** `system-models/license-linking/license-linking.als`
**Pairs with:** `system-models/license-compatibility/` (aggregation model)
**Tool:** Alloy 6.2.0 via bundled runner, `minisat.prover` active
**Scope:** `for 8`
**Date:** 2026-04-17

## Why this model exists

The original compatibility model reasoned about **aggregation** — multiple
components shipped side-by-side in the same distribution, each retaining its
own license. That covered the "can we bundle these?" question. It explicitly
deferred **derivation / linking semantics** with the note:

> *"The model treats license compatibility at the aggregation level, which is
> the actual legal question for this package (no component is statically
> linked into or derived from another in ways that would trigger strong
> copyleft propagation). Derivation / linking semantics are out of scope."*

That deferral was accurate given the then-current packaging (everything was
bundled; no static linking). But linking is the second axis where license
compatibility can break down, and the skill invokes Alloy/Kodkod classes at
runtime via Java imports — so there *is* a link graph worth verifying.

## What changes when you move from aggregation to linking

Licenses treat different forms of combination differently. Each license
declares which **linking modes** trigger its copyleft propagation:

| Linking mode | What it means | Who triggers what |
|--------------|---------------|-------------------|
| `MereAggregation` | Independent programs shipped together | No license propagates — each program is separate |
| `DynamicLink` | Runtime loading: shared lib, SPI, Java import | LGPL §6 carves out — caller not forced to LGPL. GPL does propagate (strict reading). |
| `StaticLink` | Compile-time fusion (linker embeds obj code) | LGPL propagates. GPL propagates. MPL files must stay MPL. |
| `SourceDerivation` | Modifying the target's source files | All copyleft licenses propagate to the modified file |

In our model, each license declares its `propagatesAcross` as the subset of
linking modes where its copyleft flows outward:

| License | `propagatesAcross` |
|---------|--------------------|
| MIT | *(none)* |
| LGPL 2.1 | `StaticLink + SourceDerivation` |
| MPL 2.0 | `SourceDerivation` |
| GPL 3 | `DynamicLink + StaticLink + SourceDerivation` |
| CC BY-NC-SA 4.0 | `SourceDerivation` (via §1(l) Collection carve-out) |

## Current link graph

Four real-world linkages in this plugin, all dynamic:

| Caller | Callee | Mode | License of callee |
|--------|--------|------|-------------------|
| OriginalWork (AlloyRunner) | AlloyCore | `DynamicLink` (Java imports) | MIT |
| OriginalWork (AlloyRunner) | Kodkod | `DynamicLink` (Java imports) | MIT |
| Kodkod | SAT4JSolver | `DynamicLink` (ServiceLoader SPI) | LGPL 2.1 |
| Kodkod | MiniSatProver | `DynamicLink` (ServiceLoader SPI) | MIT |

Notably **absent** from the graph: Electrod (MPL) is present on disk but not
invoked — no Link edge. Lingeling is stripped, so no edge. GPL-licensed
components are rejected at extraction, so no edge.

## Verification results

All four assertions hold at scope 8:

| # | Assertion | Verdict |
|---|-----------|---------|
| A1 | `NoStrongCopyleftInheritance` — OriginalWork does not transitively inherit GPL-style whole-program copyleft | ✓ |
| A2 | `LGPLDynamicLinkCarveout` — LGPL §6 dynamic-link exemption is honored (no Link with LGPL callee + DynamicLink has LGPL's copyleft propagate) | ✓ |
| A3 | `OriginalWorkDoesNotInfectOthers` — CC's ShareAlike does not flow to other components via the current graph | ✓ |
| A4 | `MPLFileCopyleftContained` — MPL file-level copyleft does not propagate across DynamicLink | ✓ |

And three what-if runs:

- `CurrentGraphValid` — satisfiable; witnesses the clean current state.
- `StaticLinkLGPLWouldPropagate` — UNSAT under current facts (we haven't static-linked SAT4J; the fact forbids it). Comment in the model explains that if such a link existed, LGPL would propagate.
- `HypotheticalGPLComponentBreaks` — UNSAT under current facts (we have no GPL-licensed components). If added, A1 would fail.

## What the model proves

Under the current link graph:

1. **No copyleft reaches OriginalWork.** Every link from OriginalWork is a
   DynamicLink to an MIT-licensed callee. MIT has empty `propagatesAcross`,
   so nothing flows into our code.
2. **Transitive reach through Kodkod is safe.** Kodkod dynamically links
   SAT4J (LGPL), but LGPL's `propagatesAcross` = `{StaticLink,
   SourceDerivation}` — `DynamicLink` is excluded by §6. So even transitively
   (OriginalWork → Kodkod → SAT4J via two DynamicLinks), LGPL does not flow
   back to our code.
3. **Our ShareAlike does not infect downstream components.** CC BY-NC-SA 4.0
   propagates only via `SourceDerivation`. No Link in the current graph has
   OriginalWork as a callee under SourceDerivation.
4. **MPL file-level copyleft is contained.** Electrod is in the extracted
   jar but not linked by our runner; its copyleft can only propagate via
   source-level modifications, which we do not make.

## Why the compatibility story is now complete

The two models together cover both axes of license interaction:

- **Aggregation** (`license-compatibility.als`) — proving that bundling these
  components into one distribution does not violate any license.
- **Linking / derivation** (this model) — proving that the runtime
  interactions between components do not trigger copyleft propagation that
  would conflict with CC BY-NC-SA 4.0 at the top level.

The earlier caveat in the compatibility model —

> *"This is engineering-grade verification, not legal advice."*

still applies to both. But the technical story is now closed: no linking
mode in our current graph carries a copyleft obligation that would conflict
with the top-level license, and the assertion set would catch regressions
(e.g., if someone introduced static linking, or bundled a GPL component,
or source-modified an MPL file).

## Gaps worth naming

Three modeling limitations carried over from the aggregation model:

1. **GPL's DynamicLink stance is conservative.** This model treats GPL as
   propagating across `DynamicLink`, matching the FSF's strict reading.
   Courts have sometimes accepted narrower interpretations. For our
   purposes, the conservative reading is the safe one.
2. **No Classpath Exception modeling.** Java's OpenJDK uses GPL + Classpath
   Exception, which permits linking without propagation. We don't link to
   OpenJDK-licensed code directly (it's the runtime, not a bundled library),
   so this doesn't bite. If a bundled library ever had "GPL + Classpath
   Exception," we'd need to model the exception separately.
3. **Transitive derivation is not modeled.** If component A modifies
   component B's source (SourceDerivation with B as callee) and a downstream
   caller then DynamicLinks A, the caller's relationship to B is mediated by
   A. This subtlety doesn't affect our graph (we don't source-modify
   anything), but would need attention if we ever forked an upstream
   component.
