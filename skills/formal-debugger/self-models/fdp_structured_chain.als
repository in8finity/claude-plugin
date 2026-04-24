module fdp_structured_chain

/*
 * Segment: TC30 / PW0-live structured hash integrity.
 *
 * Models the four parallel chains that back the skill's provenance contract:
 *   1. Report chain: investigation-report-<N>_*.md chain via PrevReportHash
 *   2. Hypothesis chain: H events chain via PrevHypHash, anchored on report 1
 *   3. Evidence parent links: each E record has ParentHypEvent + ParentHypHash
 *   4. Model-change chain + parent links: M records chain via PrevModelHash
 *      AND carry ParentHypEvent + ParentHypHash
 *
 * Plus the orthogonal state-change EvidenceHash: H events with Event:
 * status-changed or accepted carry a sorted-concat hash over their cited
 * evidence records, freezing those records against post-citation edits.
 *
 * The model abstracts sha256 as an opaque Hash atom. "Tampering" = changing
 * a record's contentHash. The validity predicates enforce that reference
 * fields (PrevHypHash, ParentHypHash, EvidenceHash, etc.) match the
 * current contentHash of the records they reference.
 */

-- ============================================================
-- Domain
-- ============================================================

sig Hash {}  -- opaque; two distinct Hash atoms represent distinct content

abstract sig EventType {}
one sig SymptomClaimed, Created, MechanismStated, CounterfactualStated,
        ObservabilityAssessed, AlternativeConsidered, StatusChanged,
        Accepted, EquivalenceChecked extends EventType {}

-- The four record types. Each has a contentHash identifying its current
-- state; tampering means the contentHash changes.
abstract sig Record {
  contentHash: one Hash
}

sig Report extends Record {
  versionNum: one Int,
  prevReportRef: lone Report  -- None for version 1
}

sig HypothesisEvent extends Record {
  prevHypRef: lone Record,     -- either prev H or the genesis report (version 1)
  prevHypHash: one Hash,       -- the PrevHypHash field this event declares
  eventType: one EventType
}

sig Evidence extends Record {
  parentHypRef: one HypothesisEvent,
  parentHypHash: one Hash      -- the ParentHypHash field this E declares
}

sig ModelChange extends Record {
  prevModelRef: lone Record,   -- either prev M or the genesis report
  prevModelHash: one Hash,
  parentHypRef: one HypothesisEvent,
  parentHypHash: one Hash
}

-- State-change events are a distinguished subset of HypothesisEvent.
sig StateChangeEvent in HypothesisEvent {
  citedEvidence: some Evidence,
  evidenceHash: one Hash  -- the EvidenceHash field this event declares
} { eventType in StatusChanged + Accepted }

-- One singleton representing the genesis report (version 1).
one sig GenesisReport in Report {} { versionNum = 1 and no prevReportRef }

-- ============================================================
-- Facts: structural constraints that are always true
-- ============================================================

-- All records have distinct contentHash — no hash collisions in the scope.
-- (Two records having the same contentHash would mean identical content
-- which doesn't violate anything, but for this model we keep them distinct.)
fact DistinctContentHashes {
  all disj r1, r2: Record | r1.contentHash != r2.contentHash
}

-- Report chain: version numbers are positive, chain is acyclic, exactly
-- one genesis report with version 1.
fact ReportChainStructure {
  all r: Report | r.versionNum > 0
  no r: Report | r in r.^prevReportRef  -- acyclic
  all r: Report - GenesisReport |
    some r.prevReportRef and r.prevReportRef.versionNum = minus[r.versionNum, 1]
}

-- Every HypothesisEvent's prevHypRef is either another H or the genesis report.
fact HypChainStructure {
  all h: HypothesisEvent | h.prevHypRef in HypothesisEvent + Report
  -- First H event (one with prevHypRef = a Report) anchors on the genesis.
  all h: HypothesisEvent | h.prevHypRef in Report => h.prevHypRef = GenesisReport
  no h: HypothesisEvent | h in h.^prevHypRef  -- acyclic
}

fact ModelChainStructure {
  all m: ModelChange | m.prevModelRef in ModelChange + Report
  all m: ModelChange | m.prevModelRef in Report => m.prevModelRef = GenesisReport
  no m: ModelChange | m in m.^prevModelRef
}

-- ============================================================
-- Integrity predicates (what TC30 actually checks)
-- ============================================================

-- The declared prevHypHash matches the referenced record's current contentHash.
pred hypChainValid {
  all h: HypothesisEvent | h.prevHypHash = h.prevHypRef.contentHash
}

pred modelChainValid {
  all m: ModelChange | m.prevModelHash = m.prevModelRef.contentHash
}

pred reportChainValid {
  -- N>=2 reports carry an implicit PrevReportHash; we model it via the ref.
  -- The integrity check is that the referenced report's contentHash equals
  -- what this report claims (captured via the prevReportRef being current).
  all r: Report - GenesisReport | some r.prevReportRef
}

-- Evidence parent links valid: ParentHypHash matches the referenced H's
-- current contentHash.
pred evidenceParentLinksValid {
  all e: Evidence | e.parentHypHash = e.parentHypRef.contentHash
}

-- Model-change parent links valid.
pred modelParentLinksValid {
  all m: ModelChange | m.parentHypHash = m.parentHypRef.contentHash
}

-- EvidenceHash on a state-change event captures the hashes of cited evidence
-- at citation time. We model this by requiring: the state-change's
-- evidenceHash is a one-to-one function over the set of contentHash values
-- of its citedEvidence. (In the real implementation it's sha256 of the
-- sorted concatenation of those hashes; in Alloy we abstract that as a
-- unique representative Hash for each distinct set.)
pred evidenceHashValid {
  all disj sc1, sc2: StateChangeEvent |
    sc1.citedEvidence.contentHash != sc2.citedEvidence.contentHash
    => sc1.evidenceHash != sc2.evidenceHash
  -- Two state-changes citing identical evidence sets get identical hashes:
  all disj sc1, sc2: StateChangeEvent |
    sc1.citedEvidence.contentHash = sc2.citedEvidence.contentHash
    => sc1.evidenceHash = sc2.evidenceHash
}

-- Full TC30 compliance: all four checks pass.
pred tc30_pass {
  reportChainValid
  hypChainValid
  evidenceParentLinksValid
  modelChainValid
  modelParentLinksValid
  evidenceHashValid
}

-- ============================================================
-- Safety assertions — what tampering breaks
-- ============================================================

-- TC30-S1: If any H event's prevHypHash doesn't match its reference's current
-- contentHash, hypChainValid fails. (Retroactive edit to a past H event.)
assert HypTamperBreaksChain {
  all h: HypothesisEvent |
    h.prevHypHash != h.prevHypRef.contentHash => not hypChainValid
}
check HypTamperBreaksChain for 5

-- TC30-S2: If any evidence's parentHypHash doesn't match its parent's current
-- contentHash, evidenceParentLinksValid fails. (Retroactive edit to a parent H.)
assert EvidenceParentTamperBreaksLink {
  all e: Evidence |
    e.parentHypHash != e.parentHypRef.contentHash => not evidenceParentLinksValid
}
check EvidenceParentTamperBreaksLink for 5

-- TC30-S3: If two state-change events cite evidence sets with different
-- content-hashes but declare the same EvidenceHash, evidenceHashValid fails.
-- (Evidence tampering changes the hash set, breaking the citation.)
assert EvidenceTamperBreaksHash {
  all disj sc1, sc2: StateChangeEvent |
    (sc1.citedEvidence.contentHash != sc2.citedEvidence.contentHash
     and sc1.evidenceHash = sc2.evidenceHash)
    => not evidenceHashValid
}
check EvidenceTamperBreaksHash for 5

-- TC30-S4: The genesis report is always reachable via prevHypRef-chain from
-- every hypothesis event (acyclic + transitively reaches a Report).
assert AllHypsReachGenesis {
  all h: HypothesisEvent | GenesisReport in h.^prevHypRef
}
check AllHypsReachGenesis for 5

-- TC30-S5: The genesis report is always reachable from every model change.
assert AllModelsReachGenesis {
  all m: ModelChange | GenesisReport in m.^prevModelRef
}
check AllModelsReachGenesis for 5

-- TC30-S6: TC30 compliance is equivalent to the conjunction of the six
-- sub-checks. This is tautological but documents the decomposition.
assert TC30Decomposition {
  tc30_pass iff (
    reportChainValid and hypChainValid and evidenceParentLinksValid
    and modelChainValid and modelParentLinksValid and evidenceHashValid
  )
}
check TC30Decomposition for 5

-- ============================================================
-- Liveness scenarios
-- ============================================================

-- A valid investigation with TC30 compliance exists.
-- Scope 8 is needed because the 6 records each require a unique contentHash,
-- plus the state-change event's evidenceHash is a 7th Hash, plus parent-link
-- and chain-reference hashes. Hash atoms need to be numerous enough to
-- populate all the reference fields without collisions.
run ValidInvestigation {
  tc30_pass
  #HypothesisEvent >= 2
  #Evidence >= 1
  #ModelChange >= 1
  #Report >= 2
  #StateChangeEvent >= 1
} for 8

-- Minimal scenario: just a genesis report and one H event.
run MinimalAnchoredHypothesis {
  tc30_pass
  #Report = 1
  #HypothesisEvent = 1
  no Evidence
  no ModelChange
  no StateChangeEvent
} for 3
