module fdp_source_classification

/*
 * Segment 1: F3 Source Classification (Static)
 *
 * Proves that the source→reliability mapping is consistent and that
 * repo code can never produce Direct evidence. No temporal logic needed —
 * source and reliability are immutable fields on Fact.
 *
 * Interface contract: f.reliability = sourceReliability[f.source]
 * The temporal core assumes this as a fact.
 */

-- ============================================================
-- Domain enums (self-contained, no imports)
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

abstract sig Reliability {}
one sig Direct, Inferred, Interpreted, UnreliableSource extends Reliability {}

abstract sig SourceType {}
one sig ProductionDB,
        RecentProductionLogs,
        OldProductionLogs,
        LiveAPIResponse,
        DeployedConfig,
        RepoCode,
        LocalGitHistory,
        PriorReport,
        SpecDesignDoc,
        AlloyModelResult,
        UserVerbalDescription,
        MobileAppCode,
        ThirdPartyDocs,
        UserReport
  extends SourceType {}

-- ============================================================
-- F3: source → reliability classification function
-- ============================================================

fun sourceReliability[s: SourceType]: one Reliability {
  s in (ProductionDB + RecentProductionLogs + LiveAPIResponse + DeployedConfig)
    => Direct
  else s in (OldProductionLogs + AlloyModelResult + UserReport)
    => Inferred
  else s in (RepoCode + LocalGitHistory + PriorReport + SpecDesignDoc
             + UserVerbalDescription + ThirdPartyDocs)
    => Interpreted
  else  -- MobileAppCode
    UnreliableSource
}

-- ============================================================
-- Fact sig with source classification
-- ============================================================

sig Fact {
  source: one SourceType,
  reliability: one Reliability
}

-- F3 constraint: reliability must match the classification table
fact F3_ReliabilityMatchesSource {
  all f: Fact | f.reliability = sourceReliability[f.source]
}

-- ============================================================
-- Safety assertions (all static — no temporal operators needed)
-- ============================================================

-- F3-S1: Every source type maps to exactly one reliability level
assert F3_TotalFunction {
  all s: SourceType | one sourceReliability[s]
}
check F3_TotalFunction for 6

-- F3-S2: Repo code is always Interpreted, never Direct
assert F3_RepoCodeIsInterpreted {
  sourceReliability[RepoCode] = Interpreted
  and sourceReliability[RepoCode] != Direct
}
check F3_RepoCodeIsInterpreted for 6

-- F3-S3: All 4 Direct sources are production-grade
assert F3_DirectSourcesAreProduction {
  sourceReliability[ProductionDB] = Direct
  and sourceReliability[RecentProductionLogs] = Direct
  and sourceReliability[LiveAPIResponse] = Direct
  and sourceReliability[DeployedConfig] = Direct
}
check F3_DirectSourcesAreProduction for 6

-- F3-S4: Mobile app code is UnreliableSource (lowest tier)
assert F3_MobileAppIsUnreliable {
  sourceReliability[MobileAppCode] = UnreliableSource
}
check F3_MobileAppIsUnreliable for 6

-- F3-S5: Old production logs degrade from Direct to Inferred
assert F3_OldLogsDegraded {
  sourceReliability[RecentProductionLogs] = Direct
  and sourceReliability[OldProductionLogs] = Inferred
}
check F3_OldLogsDegraded for 6

-- F3-S6: Alloy model results are Inferred, not Direct
assert F3_AlloyResultIsInferred {
  sourceReliability[AlloyModelResult] = Inferred
  and sourceReliability[AlloyModelResult] != Direct
}
check F3_AlloyResultIsInferred for 6

-- F3-S7: No interpreted source can produce Direct evidence
-- (the key safety property — prevents code reading from being tagged Direct)
assert F3_InterpretedNeverDirect {
  all f: Fact | f.reliability = Interpreted => f.source not in
    (ProductionDB + RecentProductionLogs + LiveAPIResponse + DeployedConfig)
}
check F3_InterpretedNeverDirect for 6

-- F3-S8: A repo-code-only fact set has no Direct evidence
-- (consequence: hasDirectEvidence stays False → PV1 blocks acceptance)
assert F3_RepoCodeOnlyBlocksDirectEvidence {
  (all f: Fact | f.source = RepoCode) =>
    (no f: Fact | f.reliability = Direct)
}
check F3_RepoCodeOnlyBlocksDirectEvidence for 6

-- F3-S9: Reliability is always consistent with source
-- (the F3 fact restated as an assertion for explicit verification)
assert F3_ReliabilityConsistent {
  all f: Fact | f.reliability = sourceReliability[f.source]
}
check F3_ReliabilityConsistent for 6

-- ============================================================
-- Scenarios
-- ============================================================

-- Can we have a fact set with at least one Direct and one Interpreted?
run MixedReliabilitySet {
  some f1, f2: Fact | f1.reliability = Direct and f2.reliability = Interpreted
} for exactly 3 Fact

-- Can we have a fact set that is all Interpreted? (no Direct evidence)
run AllInterpretedSet {
  all f: Fact | f.reliability = Interpreted
} for exactly 2 Fact
