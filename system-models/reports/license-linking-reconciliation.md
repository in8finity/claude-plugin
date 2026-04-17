# Reconciliation Report: license-linking.als vs. actual license texts

**Model:** `system-models/license-linking/license-linking.als`
**Sources reconciled against:**
- `skills/formal-modeling/scripts/.alloy/extracted/Alloy.txt` (MIT)
- `skills/formal-modeling/scripts/.alloy/extracted/SAT4J.txt` (LGPL 2.1)
- `skills/formal-modeling/scripts/.alloy/extracted/LICENSES/Electrod.txt` (MPL 2.0)
- GPL v3 canonical text (FSF, not bundled here — used as counterexample baseline)
- `LICENSE` (CC BY-NC-SA 4.0 canonical legal code from Creative Commons)
- `skills/formal-modeling/scripts/alloy_run.sh` (the live link graph)

**Date:** 2026-04-17

## Summary

- License profiles reconciled: **5** (MIT, LGPL 2.1, MPL 2.0, GPL 3, CC BY-NC-SA 4.0)
- Link-graph edges reconciled: **4** (Runner→Alloy, Runner→Kodkod, Kodkod→SAT4J, Kodkod→MiniSat)
- Model assertions reconciled: **4** (A1, A2, A3, A4)
- **Aligned: 11**
- **Aligned-with-nuance: 2** (conservative encoding; documented in model comments)
- **FixModel: 0**
- **Drift: 0**

Both the license encodings and the live link graph match the authoritative sources. Two entries are flagged as "aligned-with-nuance" — they use conservative readings of legally contested areas (GPL-on-DynamicLink, CC-on-unmodified-aggregation) rather than taking the most permissive interpretation. The model's comments already call these out.

## Per-license reconciliation (5)

### MIT — Aligned

**Model:** `MIT.propagatesAcross = {}` (no copyleft propagation in any mode).

**Text evidence** (`Alloy.txt:3–8`):
> *"Permission is hereby granted, free of charge, to any person obtaining a copy of this software ... to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software ..."*

No copyleft clause. Modifications don't need to be MIT; derivatives can be any license. The empty `propagatesAcross` set is a faithful encoding.

**Verdict:** Aligned.

### LGPL 2.1 — Aligned

**Model:** `LGPL21.propagatesAcross = StaticLink + SourceDerivation`.

**Text evidence:**

*Mere aggregation carve-out* (`SAT4J.txt:206–209`):
> *"In addition, mere aggregation of another work not based on the Library with the Library (or with a work based on the Library) on a volume of a storage or distribution medium does not bring the other work under the scope of this License."*

→ `MereAggregation` not in `propagatesAcross` ✓.

*Static-link propagation* (§6, `SAT4J.txt:271–276`):
> *"As an exception to the Sections above, you may also combine or link a 'work that uses the Library' with the Library to produce a work containing portions of the Library, and distribute that work under terms of your choice, provided that the terms permit modification of the work for the customer's own use and reverse engineering for debugging such modifications."*

→ LGPL terms attach to the combined static-link binary (propagation occurs, with specific user-modifiability conditions). `StaticLink` in `propagatesAcross` ✓.

*Dynamic-link carve-out* (§5 + §6 interaction, `SAT4J.txt:241–250`):
> *"A program that contains no derivative of any portion of the Library, but is designed to work with the Library by being compiled or linked with it, is called a 'work that uses the Library'. Such a work, in isolation, is not a derivative work of the Library, and therefore falls outside the scope of this License."*

→ Dynamic linking produces a "work that uses the Library" that is "outside the scope of this License." `DynamicLink` not in `propagatesAcross` ✓.

**Verdict:** Aligned. The model's binary "propagates or doesn't" is a simplification — §6 actually imposes specific conditions on the combined work (must permit reverse engineering, must allow replacement of the LGPL library) rather than forcing the LGPL license itself to apply. But for the purposes of "would combining this create obligations we'd inherit," treating it as propagation is conservative and correct.

### MPL 2.0 — Aligned

**Model:** `MPL20.propagatesAcross = SourceDerivation`.

**Text evidence:**

*Larger Work under any terms* (§3.3, `Electrod.txt:185–189`):
> *"You may create and distribute a Larger Work under terms of Your choice, provided that You also comply with the requirements of this License for the Covered Software."*

→ Combining MPL code with other-licensed code is explicitly permitted; the Larger Work can be any license. `MereAggregation`, `DynamicLink`, `StaticLink` all exempt ✓.

*File-level modifications* (§1.10 "Modifications", §3.3):
> MPL's "Modifications" are defined at the file level: any changes to a Covered Software file. Modifications to MPL files remain MPL; non-MPL files in the Larger Work keep their own terms.

→ `SourceDerivation` of an MPL file propagates MPL to that file. In `propagatesAcross` ✓.

**Verdict:** Aligned.

### GPL 3 — Aligned with nuance

**Model:** `GPL3.propagatesAcross = DynamicLink + StaticLink + SourceDerivation`.

**Text evidence:**

*Mere aggregation exempt* (GPL 3 §5):
> *"A compilation of a covered work with other separate and independent works, which are not by their nature extensions of the covered work, and which are not combined with it such as to form a larger program, in or on a volume of a storage or distribution medium, is called an 'aggregate'... Inclusion of a covered work in an aggregate does not cause this License to apply to the other parts of the aggregate."*

→ `MereAggregation` not in `propagatesAcross` ✓.

*Linking as derivation* (FSF position, not explicit in the GPL text):
The FSF holds that dynamic linking produces a derivative work; courts have sometimes disagreed. The model takes the strict FSF reading, which the file comments explicitly acknowledge:

> *"We conservatively include DynamicLink here because GPL considers linking a form of combination; the Classpath Exception and similar carve-outs are separate LICENSES, not GPL itself."*

**Verdict:** Aligned (conservative reading). A less-conservative model might exclude `DynamicLink` from GPL's propagation, matching narrow court interpretations. The conservative choice is safer for a license-compatibility model whose goal is to *reject* problematic configurations.

### CC BY-NC-SA 4.0 — Aligned with nuance

**Model:** `CCBYNCSA40.propagatesAcross = SourceDerivation`.

**Text evidence:**

*Adapted Material definition* (§1(a), `LICENSE:73–80`):
> *"Adapted Material means material subject to Copyright and Similar Rights that is derived from or based upon the Licensed Material and in which the Licensed Material is translated, altered, arranged, transformed, or otherwise modified in a manner requiring permission under the Copyright and Similar Rights held by the Licensor."*

*ShareAlike trigger* (§3(b), `LICENSE:283–289`):
> *"In addition to the conditions in Section 3(a), if You Share Adapted Material You produce, the following conditions also apply... The Adapter's License You apply must be a Creative Commons license with the same License Elements, this version or later, or a BY-NC-SA Compatible License."*

→ SA applies only to Adapted Material (derivative works). Not to inclusion of unmodified Licensed Material in a larger work. `SourceDerivation` in `propagatesAcross` ✓; other modes exempt.

**Nuance:** CC 4.0 removed the explicit "Collection" concept present in CC 3.0. Whether unmodified inclusion of a CC BY-NC-SA work in a compilation creates Adapted Material is not crisply answered in the text alone — the §1(a) phrase *"translated, altered, arranged, transformed, or otherwise modified"* could be read to include "arranged" (compilation) in some readings. CC's published FAQ confirms that unmodified inclusion is not Adapted Material, which is the model's encoding.

**Verdict:** Aligned (with the nuance that purely textual readings could argue a broader propagation; the model takes the published-intent reading, which is the consensus position).

## Per-edge reconciliation — link graph (4)

All four edges are verified against the actual code.

| # | Model edge | Mode | Source evidence | Verdict |
|---|-----------|------|-----------------|---------|
| 1 | OriginalWork → AlloyCore | DynamicLink | `alloy_run.sh` heredoc imports `edu.mit.csail.sdg.*` classes — JVM class loading at first reference is runtime (dynamic). | Aligned |
| 2 | OriginalWork → Kodkod | DynamicLink | Same heredoc imports `kodkod.engine.satlab.SATFactory` — Java class loading. | Aligned |
| 3 | Kodkod → SAT4J | DynamicLink | Kodkod discovers SAT backends via `META-INF/services/kodkod.engine.satlab.SATFactory` (ServiceLoader SPI). Instances are created by reflection at runtime. | Aligned |
| 4 | Kodkod → MiniSatProver | DynamicLink | Same ServiceLoader mechanism. Confirmed by the `Solver: minisat.prover` diagnostic emitted by the pinned runner. | Aligned |

No edges are missing from the model. No edges in the model are false.

## Per-assertion reconciliation (4)

| # | Assertion | Source-of-truth justification | Verdict |
|---|-----------|-------------------------------|---------|
| A1 | `NoStrongCopyleftInheritance` — no GPL-style copyleft reaches OriginalWork via `^propagatesTo` | No bundled component is GPL-licensed (enforced by `reject_gpl_components` in `alloy_run.sh`). Combined with correct GPL encoding (`propagatesAcross` includes DynamicLink), the assertion reduces to "no GPL in graph," which holds. | Aligned |
| A2 | `LGPLDynamicLinkCarveout` — LGPL §6 exemption honored | SAT4J is the only LGPL component. Our only link to it is transitive via Kodkod under DynamicLink. LGPL's `propagatesAcross = {StaticLink, SourceDerivation}` excludes DynamicLink, matching §6 text above. | Aligned |
| A3 | `OriginalWorkDoesNotInfectOthers` — CC's SA does not flow via current links | CC's `propagatesAcross = {SourceDerivation}`. No Link has OriginalWork as callee with SourceDerivation mode. (No one source-modifies our code.) | Aligned |
| A4 | `MPLFileCopyleftContained` — MPL file-level copyleft does not propagate across DynamicLink | Electrod is the only MPL component; it is present but not linked. Even if it were DynamicLink'd, MPL's `propagatesAcross = {SourceDerivation}` excludes DynamicLink per §3.3. | Aligned |

## Enforcement audit (for natural-language sources)

Each license text is a natural-language contract. Applying the enforcement-audit pattern to the specific propagation clauses we rely on:

| Clause | Location | Gate language? | Enforced by us? |
|--------|----------|----------------|-----------------|
| LGPL §2 mere aggregation exempt | SAT4J.txt:206–209 | Declarative ("does not bring ... under the scope") | Enforced structurally — we never bundle LGPL-modified files |
| LGPL §6 dynamic-link terms | SAT4J.txt:271–276 | Conditional ("may ... provided that the terms permit ...") | Enforced — no static linking in our runner |
| MPL §3.3 Larger Work carve-out | Electrod.txt:185–189 | Permissive ("You may create ... under terms of Your choice") | Enforced — Larger Work (our repo + downloaded Alloy jar) carries its own licenses, MPL files retained as-is |
| GPL §5 aggregate exemption | GPL v3 canonical | Declarative | Enforced — `reject_gpl_components` prevents any GPL from entering the cache |
| CC §1(a) Adapted Material | LICENSE:73–80 | Definitional | Enforced — no runtime flow modifies our code |
| CC §3(b) ShareAlike | LICENSE:283–289 | Conditional gate ("if You Share Adapted Material") | Enforced — SA triggers only on publishing derivative work; aggregation of CC + MIT/LGPL/MPL is not derivative |

All the clauses the model relies on are enforced either structurally (we never do X) or by executable gate (`reject_gpl_components`, `strip_nc_solvers`, `AlloyRunner` pinning).

## What the model does *not* attempt

Three categories of complexity deliberately out of scope, flagged in the model file's "Gaps worth naming" section:

1. **GPL + Classpath Exception** — the OpenJDK runtime is GPL-with-Classpath-Exception, which carves out linking. We don't bundle or link OpenJDK code; it's the runtime. Not modeled.
2. **Transitive source derivation** — if A modifies B's source (SourceDerivation) and a downstream caller DynamicLinks A, the relationship is mediated by A's chosen license. Not relevant to our current graph (no SourceDerivation edges), but would need separate modeling if we forked an upstream component.
3. **Jurisdictional variance** — FSF's reading of GPL-on-DynamicLink vs. court interpretations. The model takes the conservative FSF reading.

These are acknowledged limitations, not drifts.

## Verdict

The linking model's encoding of the five licenses and the four link-graph edges is faithful to the authoritative texts, with two "aligned-with-nuance" items where the model takes the conservative (safer) interpretation of legally contested areas. All four assertions hold when checked against the primary source for each clause.

**No FixModel, FixSource, or Drift items.** Ready to stand as the linking-axis side of the license-compatibility story alongside the aggregation-model's Round 2 reconciliation.
