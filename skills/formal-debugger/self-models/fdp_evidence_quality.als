module fdp_evidence_quality

/*
 * Segment 6: F6-F9 Evidence Quality Rules (Static)
 *
 * Proves structural properties of evidence quality gates added from
 * the summary-token-growth investigation feedback:
 *   F6 — cross-source absence verification
 *   F7 — trace the writer, not the reader
 *   F8 — compute locally before estimating
 *   F9 — DB fields are snapshots with write timestamps
 *
 * No temporal logic — these are constraints on evidence structure,
 * not on step ordering.
 */

-- ============================================================
-- Domain (self-contained)
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

abstract sig Reliability {}
one sig Direct, Inferred, Interpreted, UnreliableSource extends Reliability {}

-- ============================================================
-- F6: Cross-source absence verification
-- ============================================================

sig AbsenceClaim {
  sourcesChecked: one Int,
  sourcesTotal: one Int,
  allAgreeAbsent: one Bool
}

-- Note: Int bounds (checked <= total, non-negative) are enforced in predicates,
-- not as a global fact, to avoid overconstrained instances with Alloy Int.

pred f6_verified[a: AbsenceClaim] {
  a.sourcesChecked = a.sourcesTotal
  and a.sourcesTotal > 0
  and a.allAgreeAbsent = True
}

pred f6_singleSourceInsufficient[a: AbsenceClaim] {
  a.sourcesChecked = 1 and a.sourcesTotal > 1
}

-- F6-S1: Single source with multiple available → not verified
assert F6_SingleSourceBlocks {
  all a: AbsenceClaim |
    f6_singleSourceInsufficient[a] => not f6_verified[a]
}
check F6_SingleSourceBlocks for 6 but 3 Int

-- F6-S2: All sources checked and agree → verified
assert F6_AllSourcesPass {
  all a: AbsenceClaim |
    (a.sourcesChecked = a.sourcesTotal
     and a.sourcesTotal > 0
     and a.allAgreeAbsent = True)
    => f6_verified[a]
}
check F6_AllSourcesPass for 6 but 3 Int

-- F6-S3: Zero sources checked → not verified
assert F6_ZeroSourcesFail {
  all a: AbsenceClaim |
    a.sourcesChecked = 0 => not f6_verified[a]
}
check F6_ZeroSourcesFail for 6 but 3 Int

-- F6-S4: Partial check → not verified
assert F6_PartialCheckFails {
  all a: AbsenceClaim |
    a.sourcesChecked < a.sourcesTotal => not f6_verified[a]
}
check F6_PartialCheckFails for 6 but 3 Int

-- F6-S5: Sources disagree (not allAgreeAbsent) → not verified
assert F6_DisagreementFails {
  all a: AbsenceClaim |
    a.allAgreeAbsent = False => not f6_verified[a]
}
check F6_DisagreementFails for 6 but 3 Int

-- ============================================================
-- F7: Trace the writer, not the reader
-- ============================================================

sig WrongValueEvidence {
  writePathsEnumerated: one Bool,
  producerIdentified: one Bool,
  consumerOnlyAnalysis: one Bool
}

pred f7_writePathTraced[ev: WrongValueEvidence] {
  ev.writePathsEnumerated = True and ev.producerIdentified = True
}

-- F7-S1: Consumer-only analysis is incomplete
assert F7_ConsumerOnlyIncomplete {
  all ev: WrongValueEvidence |
    (ev.consumerOnlyAnalysis = True and ev.writePathsEnumerated = False)
    => not f7_writePathTraced[ev]
}
check F7_ConsumerOnlyIncomplete for 6

-- F7-S2: Full write-path analysis is complete
assert F7_WritePathComplete {
  all ev: WrongValueEvidence |
    (ev.writePathsEnumerated = True and ev.producerIdentified = True)
    => f7_writePathTraced[ev]
}
check F7_WritePathComplete for 6

-- F7-S3: Enumerated but no match → incomplete
assert F7_NoMatchIncomplete {
  all ev: WrongValueEvidence |
    (ev.writePathsEnumerated = True and ev.producerIdentified = False)
    => not f7_writePathTraced[ev]
}
check F7_NoMatchIncomplete for 6

-- F7-S4: Not enumerated → always incomplete
assert F7_NotEnumeratedIncomplete {
  all ev: WrongValueEvidence |
    ev.writePathsEnumerated = False => not f7_writePathTraced[ev]
}
check F7_NotEnumeratedIncomplete for 6

-- ============================================================
-- F8: Compute locally before estimating
-- ============================================================

sig NumericEvidence {
  replicableLocally: one Bool,
  computedExact: one Bool,
  estimatedFromProxy: one Bool,
  residualPercent: one Int
}

fact ResidualBounds {
  all ev: NumericEvidence | ev.residualPercent >= 0
}

fun f8_reliability[ev: NumericEvidence]: one Reliability {
  ev.computedExact = True => Direct
  else ev.estimatedFromProxy = True => Inferred
  else Interpreted
}

pred f8_residualSignalsError[ev: NumericEvidence] {
  ev.replicableLocally = True
  and ev.computedExact = False
  and ev.residualPercent > 5
}

-- F8-S1: Exact computation → Direct
assert F8_ExactIsDirect {
  all ev: NumericEvidence |
    ev.computedExact = True => f8_reliability[ev] = Direct
}
check F8_ExactIsDirect for 6 but 3 Int

-- F8-S2: Estimation → Inferred (weaker)
assert F8_EstimateIsInferred {
  all ev: NumericEvidence |
    (ev.computedExact = False and ev.estimatedFromProxy = True)
    => f8_reliability[ev] = Inferred
}
check F8_EstimateIsInferred for 6 but 3 Int

-- F8-S3: Neither → Interpreted (weakest)
assert F8_NeitherIsInterpreted {
  all ev: NumericEvidence |
    (ev.computedExact = False and ev.estimatedFromProxy = False)
    => f8_reliability[ev] = Interpreted
}
check F8_NeitherIsInterpreted for 6 but 3 Int

-- F8-S4: Residual with replicable = error signal
assert F8_ResidualSignalsError {
  all ev: NumericEvidence |
    (ev.replicableLocally = True and ev.computedExact = False and ev.residualPercent > 5)
    => f8_residualSignalsError[ev]
}
check F8_ResidualSignalsError for 6 but 3 Int

-- F8-S5: No residual signal when exact computed
assert F8_NoResidualWhenComputed {
  all ev: NumericEvidence |
    ev.computedExact = True => not f8_residualSignalsError[ev]
}
check F8_NoResidualWhenComputed for 6 but 3 Int

-- F8-S6: No residual signal when not replicable
assert F8_NoResidualWhenNotReplicable {
  all ev: NumericEvidence |
    ev.replicableLocally = False => not f8_residualSignalsError[ev]
}
check F8_NoResidualWhenNotReplicable for 6 but 3 Int

-- ============================================================
-- F9: DB fields are snapshots with write timestamps
-- ============================================================

abstract sig FieldTemporality {}
one sig LiveField, SnapshotField, ScheduledField extends FieldTemporality {}

abstract sig StateQuestion {}
one sig CurrentState, HistoricalState extends StateQuestion {}

fun f9_reliability[ft: FieldTemporality, sq: StateQuestion]: one Reliability {
  ft = LiveField => Direct
  else ft = SnapshotField and sq = HistoricalState => Direct
  else ft = SnapshotField and sq = CurrentState => Inferred
  else ft = ScheduledField and sq = HistoricalState => Direct
  else Inferred  -- ScheduledField + CurrentState
}

-- F9-S1: Live field is always Direct
assert F9_LiveAlwaysDirect {
  all sq: StateQuestion | f9_reliability[LiveField, sq] = Direct
}
check F9_LiveAlwaysDirect for 6

-- F9-S2: Snapshot is Direct for historical
assert F9_SnapshotDirectForHistory {
  f9_reliability[SnapshotField, HistoricalState] = Direct
}
check F9_SnapshotDirectForHistory for 6

-- F9-S3: Snapshot is Inferred for current state (the key safety property)
assert F9_SnapshotInferredForCurrent {
  f9_reliability[SnapshotField, CurrentState] = Inferred
  and f9_reliability[SnapshotField, CurrentState] != Direct
}
check F9_SnapshotInferredForCurrent for 6

-- F9-S4: Scheduled degrades for current state
assert F9_ScheduledDegradesCurrent {
  f9_reliability[ScheduledField, CurrentState] = Inferred
  and f9_reliability[ScheduledField, HistoricalState] = Direct
}
check F9_ScheduledDegradesCurrent for 6

-- F9-S5: Only LiveField is Direct for current state
assert F9_OnlyLiveDirectForCurrent {
  all ft: FieldTemporality |
    f9_reliability[ft, CurrentState] = Direct => ft = LiveField
}
check F9_OnlyLiveDirectForCurrent for 6

-- ============================================================
-- Scenarios
-- ============================================================

-- F6: Can we have a verified absence claim?
-- Note: Int fields with > comparison need sufficient bitwidth
run F6_VerifiedAbsence {
  some a: AbsenceClaim |
    a.sourcesChecked = 2 and a.sourcesTotal = 2 and a.allAgreeAbsent = True
} for exactly 1 AbsenceClaim, 0 WrongValueEvidence, 0 NumericEvidence, 5 Int

-- F7: Can we have a complete wrong-value analysis?
run F7_CompleteAnalysis {
  some ev: WrongValueEvidence | f7_writePathTraced[ev]
} for exactly 1 WrongValueEvidence, 0 AbsenceClaim, 0 NumericEvidence

-- F8: Can exact computation and estimation coexist?
run F8_MixedEvidence {
  some disj e1, e2: NumericEvidence |
    f8_reliability[e1] = Direct and f8_reliability[e2] = Inferred
} for exactly 2 NumericEvidence, 0 AbsenceClaim, 0 WrongValueEvidence, 4 Int

-- F9: Live is Direct for current, Snapshot is Inferred for current
run F9_ReliabilityCombinations {
  f9_reliability[LiveField, CurrentState] = Direct
  and f9_reliability[SnapshotField, CurrentState] = Inferred
} for 0 AbsenceClaim, 0 WrongValueEvidence, 0 NumericEvidence
