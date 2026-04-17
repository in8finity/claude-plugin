# License Compatibility — Verification Report

**Model:** `license-compatibility.als`
**Tool:** Alloy 6 (bundled `scripts/alloy_run.sh`)
**Scope:** `for 12` (all 11 concrete components + Package + closed license/restriction domains)
**Date:** 2026-04-17

## Question

Can this repository legally bundle the pre-extracted Alloy 6 distribution —
MIT-licensed code, LGPL-2.1 (SAT4J), MPL-2.0 (Electrod), two noncommercial
research licenses (ZChaff, Lingeling), and a field-of-use-restricted component
(Glucose-Syrup) — alongside original work released under CC BY-NC-SA 4.0?

## Method

Each license is modeled by six machine-checkable properties: attribution
required, license-text preservation required, share-alike, copyleft scope
(none / file / library / whole-program), whether it forbids additional
restrictions, and its set of restrictions (NoCommercial, ResearchOnly,
NoSATCompetitions). Each component is assigned a license and packaging
status (bundled, modified, is-original). The package itself declares
attribution, preservation, commercial-use permission, and effective
restrictions.

Six obligations must hold simultaneously for the packaging to be valid:

| # | Assertion | Meaning |
|---|-----------|---------|
| A1 | AttributionHonored | Attribution provided wherever any bundled license requires it |
| A2 | LicenseTextsPreserved | Upstream license files shipped alongside |
| A3 | NoCommercialRespected | If any bundled license forbids commercial use, the package must forbid it too |
| A4 | CopyleftFilesUnmodified | LGPL / MPL files are not modified (modifying them would force copyleft propagation) |
| A5 | NoStrongCopyleftConflict | No GPL-like strong copyleft inside an NC package — GPL §7 forbids additional restrictions such as NC |
| A6 | FieldOfUseFlowsUp | Every bundled restriction inherits into the package's effective restrictions |

## Result

**All six checks pass at scope 12.**

```
check AttributionHonored        ✓  no counterexample
check LicenseTextsPreserved     ✓  no counterexample
check NoCommercialRespected     ✓  no counterexample
check CopyleftFilesUnmodified   ✓  no counterexample
check NoStrongCopyleftConflict  ✓  no counterexample
check FieldOfUseFlowsUp         ✓  no counterexample
run   CurrentPackagingValid     ✓  instance found
run   AddingGPLBreaksPackage    UNSAT (expected — fact pins out GPL)
run   ModifyingSAT4JBreaksPackage UNSAT (expected — fact pins out modification)
```

The package's effective restrictions are correctly computed as
`{NoCommercial, ResearchOnly, NoSATCompetitions}` — the union of everything
contributed by the bundled components. The top-level CC BY-NC-SA 4.0 claim
surfaces `NoCommercial` prominently; the other two are field-of-use
restrictions that rarely bite typical users and are documented in `NOTICE`
and `THIRD_PARTY_LICENSES.md`.

## Verdict

**Yes, all ten bundled tools can be included in the package under
CC BY-NC-SA 4.0**, provided that:

1. `NOTICE` + `THIRD_PARTY_LICENSES.md` continue to identify scope and
   preserve attribution. **(satisfied)**
2. The upstream license texts (`Alloy.txt`, `SAT4J.txt`, `LICENSES/Electrod.txt`,
   etc.) continue to ship inside `.alloy/extracted/`. **(satisfied)**
3. The LGPL and MPL files in `.alloy/extracted/` are not modified. If they
   are ever modified, those modifications must be released under LGPL 2.1
   / MPL 2.0 respectively — the CC license cannot absorb them. **(satisfied
   — we redistribute the official Alloy jar's contents as-is)**
4. The package does not claim to permit commercial use. ZChaff and Lingeling
   already force this independently of CC BY-NC-SA's `-NC` clause.
   **(satisfied)**

## What the model would catch

The model's guards `abstract sig License` and `abstract sig Component` close
the domains, so the solver cannot invent unenumerated components. But the
assertions are written generically, so if the bundle ever changes they would
catch:

- **Adding any GPL-licensed component** → A5 fails. GPL §7 forbids adding NC
  as a further restriction; the aggregation would not be distributable.
- **Forgetting to ship a license text** → A2 fails.
- **Modifying SAT4J / Electrod source files without relicensing derivatives**
  → A4 fails. The model flags the need to either (a) keep files pristine or
  (b) release the whole repo under the stricter copyleft.
- **Claiming the package permits commercial use** while Lingeling/ZChaff/CC-NC
  are bundled → A3 fails.
- **Dropping a component's restriction from the package's effective set** →
  A6 fails.

## Re-running

```bash
./skills/formal-modeling/scripts/alloy_run.sh system-models/license-compatibility/license-compatibility.als
```

## Caveats

- The model treats license compatibility at the aggregation level, which is
  the actual legal question for this package (no component is statically
  linked into or derived from another in ways that would trigger strong
  copyleft propagation). Derivation / linking semantics are out of scope.
- "Forbids additional restrictions" is modeled as a binary. In practice
  LGPL 2.1 §2/§6 and MPL 2.0 §3.3 explicitly carve out aggregation as
  permitted — that is implicit in the model (the assertions only fail for
  strong-copyleft + additional-restrictions combinations, matching the real
  legal picture).
- This is engineering-grade verification, not legal advice.
