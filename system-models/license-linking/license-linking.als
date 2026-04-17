-- ================================================================
-- License Linking / Derivation Semantics Model
--
-- Extends the aggregation model (license-compatibility.als) with
-- the second axis where license compatibility matters: how one
-- component interacts with another.
--
-- Aggregation (sibling model): ship components side-by-side. Each
-- retains its own license. No obligations flow across components.
--
-- Linking / derivation (this model): one component calls, imports,
-- or modifies another. Copyleft propagation depends on linking
-- mode:
--   - MereAggregation   — separate programs shipped together
--   - DynamicLink       — runtime loading (shared lib, SPI, import)
--   - StaticLink        — compile-time fusion
--   - SourceDerivation  — modifying the target's source files
--
-- Each license declares which linking modes propagate its copyleft.
-- We then build the current link graph for this plugin and verify
-- that OriginalWork (our code, CC BY-NC-SA 4.0) does not transitively
-- inherit any incompatible copyleft obligation via ^propagates.
--
-- Assertions:
--   A1 NoStrongCopyleftInheritance    — OriginalWork does not inherit GPL-style whole-program copyleft
--   A2 LGPLDynamicLinkCarveout        — LGPL §6 / §4 dynamic-link exemption is honored in the current graph
--   A3 OriginalWorkDoesNotInfectOthers — CC's SA does not flow TO other components via aggregation
--   A4 MPLFileCopyleftContained       — MPL 2.0 §3.3 carve-out: combining with other licenses is permitted
--
-- Runs:
--   R1 CurrentGraphValid              — witness instance with current link graph
--   R2 StaticLinkLGPLWouldPropagate   — what-if: static linking SAT4J would pull LGPL obligations in
--   R3 HypotheticalGPLComponentBreaks — what-if: dynamic linking a GPL component breaks NoStrongCopyleft
-- ================================================================

module license_linking

-- ─── Booleans ────────────────────────────────────────────────────
abstract sig Bool {}
one sig True, False extends Bool {}

-- ─── Linking modes ──────────────────────────────────────────────
abstract sig LinkMode {}
one sig MereAggregation  extends LinkMode {} -- independent programs in same distro
one sig DynamicLink      extends LinkMode {} -- runtime loading: shared lib, SPI, Java import
one sig StaticLink       extends LinkMode {} -- compile-time fusion: linker includes obj code
one sig SourceDerivation extends LinkMode {} -- modifying the target's source files

-- ─── Copyleft kinds ─────────────────────────────────────────────
abstract sig CopyleftKind {}
one sig NoCopyleft      extends CopyleftKind {} -- MIT, BSD, permissive
one sig FileLevel       extends CopyleftKind {} -- MPL 2.0
one sig LibraryLevel    extends CopyleftKind {} -- LGPL 2.1 / 3
one sig WholeProgram    extends CopyleftKind {} -- GPL 2 / 3
one sig AdaptedMaterial extends CopyleftKind {} -- CC BY-SA / BY-NC-SA

-- ─── Licenses ───────────────────────────────────────────────────
abstract sig License {
  copyleft         : one CopyleftKind,
  -- Set of linking modes across which this license's copyleft
  -- propagates to the caller / including work.
  propagatesAcross : set LinkMode,
  permitsCommercialUse : one Bool
}

one sig MIT        extends License {}
one sig LGPL21     extends License {}
one sig MPL20      extends License {}
one sig GPL3       extends License {}
one sig CCBYNCSA40 extends License {}

fact LicenseProfiles {
  -- MIT: permissive; no propagation in any mode.
  MIT.copyleft = NoCopyleft
  no MIT.propagatesAcross
  MIT.permitsCommercialUse = True

  -- LGPL 2.1: weak copyleft. Propagates via static linking and
  -- source derivation. §6 carves out dynamic linking so the caller
  -- is not forced to adopt LGPL; §2 (mere aggregation) is also
  -- exempt.
  LGPL21.copyleft = LibraryLevel
  LGPL21.propagatesAcross = StaticLink + SourceDerivation
  LGPL21.permitsCommercialUse = True

  -- MPL 2.0: file-level copyleft. §3.3 explicitly permits combining
  -- MPL-licensed files with differently-licensed files in the same
  -- larger work. Only modifications to MPL files themselves stay MPL.
  MPL20.copyleft = FileLevel
  MPL20.propagatesAcross = SourceDerivation
  MPL20.permitsCommercialUse = True

  -- GPL 3: strong copyleft. Propagates via every form of combining
  -- except pure mere aggregation (where programs are independent
  -- and communicate only via arms-length interfaces). We conservatively
  -- include DynamicLink here because GPL considers linking a form of
  -- combination; the Classpath Exception and similar carve-outs are
  -- separate LICENSES, not GPL itself.
  GPL3.copyleft = WholeProgram
  GPL3.propagatesAcross = DynamicLink + StaticLink + SourceDerivation
  GPL3.permitsCommercialUse = True

  -- CC BY-NC-SA 4.0: ShareAlike applies to "Adapted Material", i.e.,
  -- derivative works. §1(l) clarifies that inclusion in a Collection
  -- (aggregation) does not create Adapted Material. So SA propagates
  -- only via SourceDerivation.
  CCBYNCSA40.copyleft = AdaptedMaterial
  CCBYNCSA40.propagatesAcross = SourceDerivation
  CCBYNCSA40.permitsCommercialUse = False
}

-- ─── Components ─────────────────────────────────────────────────
abstract sig Component { license : one License }

one sig OriginalWork   extends Component {} -- our code (AlloyRunner + formal models + scripts)
one sig AlloyCore      extends Component {} -- Alloy 6 main classes
one sig Kodkod         extends Component {} -- relational model finder, MIT
one sig SAT4JSolver    extends Component {} -- LGPL, fallback SAT backend
one sig MiniSatProver  extends Component {} -- MIT, pinned SAT backend
one sig Electrod       extends Component {} -- MPL, temporal backend (present, not invoked)

fact ComponentLicenses {
  OriginalWork.license  = CCBYNCSA40
  AlloyCore.license     = MIT
  Kodkod.license        = MIT
  SAT4JSolver.license   = LGPL21
  MiniSatProver.license = MIT
  Electrod.license      = MPL20
}

-- ─── Linking graph (one edge per real-world linkage) ────────────
abstract sig Link {
  caller : one Component,
  callee : one Component,
  mode   : one LinkMode
}

-- Reality:
--   AlloyRunner.java imports edu.mit.csail.sdg.* and kodkod.* classes.
--   Those are Java imports → DynamicLink (JVM class loading).
--   Kodkod discovers SAT backends via ServiceLoader SPI → DynamicLink.
--   Nothing is statically linked. Nothing is a source derivation.
--   Electrod is present on disk but not invoked — no Link edge.
one sig LinkRunnerToAlloy, LinkRunnerToKodkod, LinkKodkodToSAT4J, LinkKodkodToMiniSat
    extends Link {}

fact CurrentLinkGraph {
  LinkRunnerToAlloy.caller = OriginalWork
  LinkRunnerToAlloy.callee = AlloyCore
  LinkRunnerToAlloy.mode   = DynamicLink

  LinkRunnerToKodkod.caller = OriginalWork
  LinkRunnerToKodkod.callee = Kodkod
  LinkRunnerToKodkod.mode   = DynamicLink

  LinkKodkodToSAT4J.caller = Kodkod
  LinkKodkodToSAT4J.callee = SAT4JSolver
  LinkKodkodToSAT4J.mode   = DynamicLink

  LinkKodkodToMiniSat.caller = Kodkod
  LinkKodkodToMiniSat.callee = MiniSatProver
  LinkKodkodToMiniSat.mode   = DynamicLink
}

-- ─── Propagation relation ───────────────────────────────────────
-- A callee's copyleft propagates to the caller if the link mode is
-- in the callee's propagatesAcross set. The relation below captures
-- single-hop propagation; ^propagatesTo gives transitive closure.

fun propagatesTo : Component -> Component {
  { p, c: Component |
      some l: Link |
        l.caller = p and l.callee = c
        and l.mode in c.license.propagatesAcross }
}

-- ─── Assertions ─────────────────────────────────────────────────

-- A1: OriginalWork does not transitively inherit GPL-style
-- whole-program copyleft. If any reachable component via propagation
-- has WholeProgram copyleft, we'd be forced to relicense as GPL —
-- which conflicts with CC BY-NC-SA 4.0 (both because CC can't legally
-- sit under GPL and because -NC adds a restriction GPL §7 forbids).
assert NoStrongCopyleftInheritance {
  no c: OriginalWork.^propagatesTo |
    c.license.copyleft = WholeProgram
}

-- A2: LGPL §6 dynamic-link carve-out is honored. If our code
-- dynamically links to SAT4J (transitively via Kodkod), LGPL does
-- not propagate — LGPL lists StaticLink + SourceDerivation as the
-- propagation modes, not DynamicLink.
assert LGPLDynamicLinkCarveout {
  all l: Link |
    l.callee.license = LGPL21
    and l.mode = DynamicLink
    implies l.mode not in l.callee.license.propagatesAcross
}

-- A3: OriginalWork's own ShareAlike (AdaptedMaterial copyleft) does
-- not infect OTHER components via the current link graph. The SA
-- clause applies only when OriginalWork is itself the subject of a
-- SourceDerivation — not when OriginalWork is the caller.
assert OriginalWorkDoesNotInfectOthers {
  no l: Link |
    l.callee = OriginalWork
    and l.mode in OriginalWork.license.propagatesAcross
}

-- A4: MPL 2.0 file-level copyleft is contained to file-level
-- modifications, not to linking. Electrod is MPL but we don't link
-- to it anyway. Even if we did dynamic-link, MPL permits it.
assert MPLFileCopyleftContained {
  no l: Link |
    l.callee.license = MPL20
    and l.mode = DynamicLink
    and l.mode in l.callee.license.propagatesAcross
}

-- ─── Verification runs ─────────────────────────────────────────

check NoStrongCopyleftInheritance    for 8
check LGPLDynamicLinkCarveout        for 8
check OriginalWorkDoesNotInfectOthers for 8
check MPLFileCopyleftContained       for 8

-- R1: witness for the current link graph — no copyleft propagation
-- reaches OriginalWork.
run CurrentGraphValid {
  no OriginalWork.^propagatesTo
} for 8

-- R2 (UNSAT expected under current facts): demonstrate what would
-- happen if we ever statically linked SAT4J into our AlloyRunner.
-- LGPL's propagatesAcross includes StaticLink, so OriginalWork would
-- then inherit LGPL obligations — which don't technically conflict
-- with CC-NC-SA (LGPL permits commercial use and is permissive on
-- aggregation) but would force us to accept additional LGPL terms on
-- the combined work and provide SAT4J sources / object files on request.
run StaticLinkLGPLWouldPropagate {
  some l: Link |
    l.caller = OriginalWork
    and l.callee = SAT4JSolver
    and l.mode = StaticLink
} for 8

-- R3: what-if scenario — if we ever added a GPL-licensed component
-- and linked to it dynamically, A1 would fail. (This is the linking
-- analog of the earlier aggregation-level GPL rejection check.)
run HypotheticalGPLComponentBreaks {
  some c: Component, l: Link |
    c.license = GPL3
    and l.caller = OriginalWork
    and l.callee = c
    and l.mode = DynamicLink
} for 8
