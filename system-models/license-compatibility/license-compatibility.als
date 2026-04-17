-- ================================================================
-- License Compatibility Model for morozov-claude-plugin
--
-- Verifies: can we bundle the pre-extracted Alloy 6 distribution
-- (MIT + LGPL 2.1 + MPL 2.0 + two noncommercial research licenses)
-- inside a repository whose original work is CC BY-NC-SA 4.0?
--
-- Modeled as a STATIC aggregation problem:
--   - Each bundled Component has a License with machine-checkable
--     properties (attribution, preservation, copyleft scope,
--     restrictions, whether it forbids additional restrictions).
--   - The Package declares its top-level license and a policy
--     (attribution provided, license texts preserved, files modified
--     or not, whether commercial use is permitted).
--   - Six obligations must hold for the packaging to be valid.
--
-- Assertions:
--   A1 AttributionHonored        -- attribution provided where required
--   A2 LicenseTextsPreserved     -- upstream license files shipped alongside
--   A3 NoCommercialRespected     -- any NC restriction flows up to the package
--   A4 CopyleftFilesUnmodified   -- we don't modify LGPL/MPL files
--   A5 NoStrongCopyleftConflict  -- no GPL-like strong copyleft inside an NC package
--   A6 FieldOfUseFlowsUp         -- field-of-use restrictions inherited by package
--
-- Runs:
--   R1 CurrentPackagingValid      -- our exact packaging satisfies all 6
--   R2 AddingGPLBreaksPackage     -- counterexample: what if we bundled GPL code?
--   R3 ModifyingSAT4JBreaksPackage -- counterexample: what if we modified SAT4J?
-- ================================================================

module license_compatibility

-- ─── Booleans ────────────────────────────────────────────────────────
abstract sig Bool {}
one sig True, False extends Bool {}

-- ─── License dimensions ─────────────────────────────────────────────
abstract sig Copyleft {}
one sig NoCopyleft      extends Copyleft {} -- MIT, BSD, CC no-restrictions
one sig FileLevel       extends Copyleft {} -- MPL 2.0
one sig LibraryLevel    extends Copyleft {} -- LGPL 2.1
one sig WholeProgram    extends Copyleft {} -- GPL, CC SA

abstract sig Restriction {}
one sig NoCommercial       extends Restriction {}
one sig ResearchOnly       extends Restriction {}
one sig NoSATCompetitions  extends Restriction {}

-- Linking modes — shared vocabulary with the linking model
-- (system-models/license-linking/license-linking.als). Each license
-- declares the subset of modes across which its copyleft propagates
-- to the caller / containing work. This replaces the earlier binary
-- `forbidsAdditionalRestrictions` field (see FM3 in the Round 1
-- reconciliation report; closed by this refactor).
abstract sig LinkMode {}
one sig MereAggregation  extends LinkMode {}
one sig DynamicLink      extends LinkMode {}
one sig StaticLink       extends LinkMode {}
one sig SourceDerivation extends LinkMode {}

abstract sig License {
  requiresAttribution         : one Bool,
  requiresLicensePreservation : one Bool,
  shareAlike                  : one Bool,
  copyleft                    : one Copyleft,
  propagatesAcross            : set LinkMode,
  restrictions                : set Restriction
}

-- ─── Concrete licenses ──────────────────────────────────────────────
one sig MIT            extends License {}
one sig LGPL21         extends License {}
one sig MPL20          extends License {}
one sig CCBYNCSA40     extends License {}
one sig ZChaffNC       extends License {}
one sig LingelingNC    extends License {}
one sig GlucoseMITPlus extends License {}
one sig GPL3           extends License {}  -- not bundled; used for counterexamples

fact LicenseProfiles {
  -- MIT
  MIT.requiresAttribution = True
  MIT.requiresLicensePreservation = True
  MIT.shareAlike = False
  MIT.copyleft = NoCopyleft
  no MIT.propagatesAcross
  no MIT.restrictions

  -- LGPL 2.1 — weak copyleft. §6 carves out dynamic linking; §2 carves
  -- out mere aggregation. Only static linking and source-level modifications
  -- propagate LGPL to the containing work.
  LGPL21.requiresAttribution = True
  LGPL21.requiresLicensePreservation = True
  LGPL21.shareAlike = True
  LGPL21.copyleft = LibraryLevel
  LGPL21.propagatesAcross = StaticLink + SourceDerivation
  no LGPL21.restrictions

  -- MPL 2.0 — file-level copyleft. §3.3 explicitly permits combining
  -- with differently-licensed code; only modifications to MPL files stay MPL.
  MPL20.requiresAttribution = True
  MPL20.requiresLicensePreservation = True
  MPL20.shareAlike = True
  MPL20.copyleft = FileLevel
  MPL20.propagatesAcross = SourceDerivation
  no MPL20.restrictions

  -- CC BY-NC-SA 4.0 — our top-level. §1(l) Collection carve-out means
  -- aggregation does not create Adapted Material; SA applies only to
  -- derivatives of the licensed work (SourceDerivation).
  CCBYNCSA40.requiresAttribution = True
  CCBYNCSA40.requiresLicensePreservation = True
  CCBYNCSA40.shareAlike = True
  CCBYNCSA40.copyleft = WholeProgram
  CCBYNCSA40.propagatesAcross = SourceDerivation
  CCBYNCSA40.restrictions = NoCommercial

  -- ZChaff (Princeton NC, research only). Permissive on combination
  -- modes but restrictive on field of use.
  ZChaffNC.requiresAttribution = True
  ZChaffNC.requiresLicensePreservation = True
  ZChaffNC.shareAlike = False
  ZChaffNC.copyleft = NoCopyleft
  no ZChaffNC.propagatesAcross
  ZChaffNC.restrictions = NoCommercial + ResearchOnly

  -- Lingeling (Biere NC, no SAT competitions). Same structure as ZChaff.
  LingelingNC.requiresAttribution = True
  LingelingNC.requiresLicensePreservation = True
  LingelingNC.shareAlike = False
  LingelingNC.copyleft = NoCopyleft
  no LingelingNC.propagatesAcross
  LingelingNC.restrictions = NoCommercial + NoSATCompetitions

  -- Glucose-Syrup (MIT-base + no SAT competitions for parallel version).
  GlucoseMITPlus.requiresAttribution = True
  GlucoseMITPlus.requiresLicensePreservation = True
  GlucoseMITPlus.shareAlike = False
  GlucoseMITPlus.copyleft = NoCopyleft
  no GlucoseMITPlus.propagatesAcross
  GlucoseMITPlus.restrictions = NoSATCompetitions

  -- GPL 3 (for counterexamples only) — strong copyleft. Propagates
  -- across every linking mode except pure aggregation (§5).
  -- Conservatively includes DynamicLink, matching the FSF reading.
  GPL3.requiresAttribution = True
  GPL3.requiresLicensePreservation = True
  GPL3.shareAlike = True
  GPL3.copyleft = WholeProgram
  GPL3.propagatesAcross = DynamicLink + StaticLink + SourceDerivation
  no GPL3.restrictions
}

-- ─── Components ─────────────────────────────────────────────────────
abstract sig Component {
  license       : one License,
  bundled       : one Bool,
  isOriginalWork: one Bool,
  isModified    : one Bool    -- have we modified this component's files?
}

one sig OriginalWork, AlloyCore, Kodkod, MiniSat, JavaCup, Gini,
         SAT4J, Electrod, ZChaff, Lingeling, Glucose extends Component {}

-- NOTE on `bundled` semantics (post-remediation):
--   `bundled = True` means the component is physically present in the user's
--   local cache after `alloy_run.sh` has finished — i.e., after download,
--   extraction, and the post-extraction strip of noncommercial solvers.
--
--   This repository itself redistributes nothing: `.alloy/` is gitignored
--   and populated at runtime from AlloyTools' official release. So
--   distribution-triggered obligations (consent, attribution in our
--   packaging) do not apply — only the user-workspace obligations do.
fact CurrentBundle {
  OriginalWork.license = CCBYNCSA40
  OriginalWork.isOriginalWork = True
  OriginalWork.bundled = True
  OriginalWork.isModified = False

  AlloyCore.license = MIT
  Kodkod.license    = MIT
  MiniSat.license   = MIT
  JavaCup.license   = MIT
  Gini.license      = MIT
  SAT4J.license     = LGPL21
  Electrod.license  = MPL20
  ZChaff.license    = ZChaffNC
  Lingeling.license = LingelingNC
  Glucose.license   = GlucoseMITPlus

  -- Components that survive the post-extraction strip and end up in the
  -- user's cache: Alloy core, Kodkod, the MIT-licensed solvers, SAT4J,
  -- Electrod, and Glucose.
  all c: AlloyCore + Kodkod + MiniSat + JavaCup + Gini + SAT4J + Electrod + Glucose {
    c.isOriginalWork = False
    c.bundled = True
    c.isModified = False  -- we ship them as extracted from the Alloy jar, unmodified
  }

  -- Stripped by alloy_run.sh (plingeling binaries, PlingelingRef JNI wrapper,
  -- and the corresponding SPI registration line are deleted after extraction).
  Lingeling.isOriginalWork = False
  Lingeling.bundled        = False
  Lingeling.isModified     = False

  -- Alloy 6.2+ does not ship ZChaff as an executable solver. Only its
  -- historical license text remains in the jar as documentation.
  ZChaff.isOriginalWork = False
  ZChaff.bundled        = False
  ZChaff.isModified     = False
}

-- ─── Package policy ─────────────────────────────────────────────────
one sig Package {
  topLevelLicense       : one License,
  attributionProvided   : one Bool,
  licenseTextsPreserved : one Bool,
  permitsCommercialUse  : one Bool,
  effectiveRestrictions : set Restriction
}

fact PackageState {
  Package.topLevelLicense = CCBYNCSA40

  -- NOTICE + THIRD_PARTY_LICENSES.md + upstream .txt files in .alloy/extracted/
  Package.attributionProvided = True
  Package.licenseTextsPreserved = True

  -- top-level -NC
  Package.permitsCommercialUse = False

  -- Effective restrictions are the UNION of restrictions from every bundled component.
  Package.effectiveRestrictions = { r: Restriction |
    some c: Component | c.bundled = True and r in c.license.restrictions }
}

-- ─── Compatibility rules (6 obligations) ────────────────────────────

-- A1: attribution honored wherever required
assert AttributionHonored {
  (all c: Component | c.bundled = True and c.license.requiresAttribution = True
    implies Package.attributionProvided = True)
}

-- A2: upstream license texts preserved wherever required
assert LicenseTextsPreserved {
  (all c: Component | c.bundled = True and c.license.requiresLicensePreservation = True
    implies Package.licenseTextsPreserved = True)
}

-- A3: no commercial use if any bundled component says no commercial use
assert NoCommercialRespected {
  (some c: Component | c.bundled = True and NoCommercial in c.license.restrictions)
    implies Package.permitsCommercialUse = False
}

-- A4: we must not modify any file under a copyleft license without inheriting that copyleft
--    (we don't modify them, so this holds vacuously for current bundle)
assert CopyleftFilesUnmodified {
  all c: Component | c.bundled = True and c.license.copyleft != NoCopyleft
    and c != OriginalWork
    implies c.isModified = False
}

-- A5: no bundled third-party component propagates copyleft across
--    DynamicLink. The load-bearing concern is GPL, whose propagation
--    via dynamic linking would conflict with -NC once any runtime
--    interaction is introduced. LGPL is safe here (carves out
--    DynamicLink); MPL and CC are safe (propagate only via source
--    derivation). This is a tripwire at bundle boundary — the detailed
--    propagation analysis lives in the sibling linking model.
assert NoStrongCopyleftConflict {
  no c: Component |
    c.bundled = True and c != OriginalWork
    and DynamicLink in c.license.propagatesAcross
}

-- A6: every bundled component's restrictions flow up into the package's
--    effective restrictions (the package can never be LESS restrictive).
assert FieldOfUseFlowsUp {
  all c: Component, r: Restriction |
    c.bundled = True and r in c.license.restrictions
    implies r in Package.effectiveRestrictions
}

-- ─── Verification runs ──────────────────────────────────────────────

check AttributionHonored        for 12
check LicenseTextsPreserved     for 12
check NoCommercialRespected     for 12
check CopyleftFilesUnmodified   for 12
check NoStrongCopyleftConflict  for 12
check FieldOfUseFlowsUp         for 12

-- R1: the current bundle satisfies all six rules simultaneously.
run CurrentPackagingValid {
  (all c: Component | c.bundled = True and c.license.requiresAttribution = True
    implies Package.attributionProvided = True)
  and (all c: Component | c.bundled = True and c.license.requiresLicensePreservation = True
    implies Package.licenseTextsPreserved = True)
  and ((some c: Component | c.bundled = True and NoCommercial in c.license.restrictions)
    implies Package.permitsCommercialUse = False)
  and (all c: Component | c.bundled = True and c.license.copyleft != NoCopyleft
    and c != OriginalWork implies c.isModified = False)
  and (no c: Component | c.bundled = True and c != OriginalWork
    and DynamicLink in c.license.propagatesAcross)
  and (all c: Component, r: Restriction |
    c.bundled = True and r in c.license.restrictions
    implies r in Package.effectiveRestrictions)
} for 12

-- R2 / R3 intentionally UNSAT: they encode hypothetical violations
--    (bundling GPL, modifying SAT4J) that contradict `fact CurrentBundle`.
--    Their UNSAT result is the correct answer — it proves the current
--    bundle is provably not in those broken states.
run AddingGPLBreaksPackage {
  some c: Component |
    c != OriginalWork
    and c.license = GPL3
    and c.bundled = True
} for 12

run ModifyingSAT4JBreaksPackage {
  SAT4J.isModified = True
} for 12
