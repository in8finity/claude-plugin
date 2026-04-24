module fdp_rejection_reasons

/*
 * Segment: U2-doc / TC35 rejection reasons.
 *
 * Every rejected hypothesis must document WHY it was rejected:
 *   EvidenceBased — cites a specific evidence entry (by index)
 *   PreferenceBased — names a priority from a CLOSED allowed set
 *     + carries a non-empty rationale string
 *
 * Closes U2's loophole: "rejected because I prefer the other one" is
 * legitimate only when the preference criterion is named from the
 * allowed set and justified.
 *
 * Counterpart to fdp_protocol.dfy's validRejectionReason /
 * allRejectionsDocumented.
 */

-- ============================================================
-- Domain
-- ============================================================

-- Six allowed preference criteria. Any other "priority" is invalid.
abstract sig PreferenceName {}
one sig Occam, BlastRadius, Severity, RecencyOfDeploy,
        Reproducibility, FixCost extends PreferenceName {}

-- Evidence entries carry an index (for citation).
sig EvidenceEntry {}

-- A rejection reason is either evidence-based (citing one entry) or
-- preference-based (naming a preference + carrying a rationale).
abstract sig RejectionReason {}
sig EvidenceBased extends RejectionReason {
  citedEvidence: one EvidenceEntry
}
sig PreferenceBased extends RejectionReason {
  priority: one PreferenceName,
  rationaleNonEmpty: one Bool
}

abstract sig Bool {}
one sig True, False extends Bool {}

-- A rejected hypothesis carries exactly one rejection reason.
sig RejectedHypothesis {
  reason: one RejectionReason
}

-- ============================================================
-- Predicates
-- ============================================================

pred validReason[r: RejectionReason] {
  r in EvidenceBased
  or (r in PreferenceBased and r.rationaleNonEmpty = True)
}

pred rejectionDocumented[h: RejectedHypothesis] {
  validReason[h.reason]
}

pred allRejectionsDocumented[hs: set RejectedHypothesis] {
  all h: hs | rejectionDocumented[h]
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- TC35-S1: EvidenceBased is always a valid reason (the citation is
-- structurally guaranteed — citedEvidence is `one EvidenceEntry`).
assert TC35_EvidenceAlwaysValid {
  all r: EvidenceBased | validReason[r]
}
check TC35_EvidenceAlwaysValid for 4

-- TC35-S2: PreferenceBased with empty rationale fails.
assert TC35_EmptyRationaleFails {
  all r: PreferenceBased |
    r.rationaleNonEmpty = False => not validReason[r]
}
check TC35_EmptyRationaleFails for 4

-- TC35-S3: PreferenceBased with non-empty rationale + any of the
-- six allowed priorities is valid. (Structurally, the priority field
-- has type PreferenceName, so only the six named atoms are reachable;
-- any "other" priority would require extending the sig.)
assert TC35_WellFormedPreferenceValid {
  all r: PreferenceBased |
    r.rationaleNonEmpty = True => validReason[r]
}
check TC35_WellFormedPreferenceValid for 4

-- TC35-S4: One undocumented rejection poisons the whole sequence.
assert TC35_OneBadBreaksAll {
  all hs: set RejectedHypothesis, bad: RejectedHypothesis |
    (bad in hs and not rejectionDocumented[bad])
    => not allRejectionsDocumented[hs]
}
check TC35_OneBadBreaksAll for 4

-- TC35-S5: If every rejection carries a valid reason, the sequence is documented.
assert TC35_AllValidImpliesDocumented {
  all hs: set RejectedHypothesis |
    (all h: hs | validReason[h.reason])
    => allRejectionsDocumented[hs]
}
check TC35_AllValidImpliesDocumented for 4

-- ============================================================
-- Liveness scenarios
-- ============================================================

-- An evidence-based rejection exists.
run EvidenceBasedRejection {
  some h: RejectedHypothesis |
    h.reason in EvidenceBased and rejectionDocumented[h]
} for 4

-- A preference-based rejection exists with each of the six priorities.
run AllPrioritiesFeasible {
  Occam in PreferenceBased.priority
  BlastRadius in PreferenceBased.priority
  Severity in PreferenceBased.priority
  RecencyOfDeploy in PreferenceBased.priority
  Reproducibility in PreferenceBased.priority
  FixCost in PreferenceBased.priority
} for 6

-- A mixed investigation: some evidence-based, some preference-based.
run MixedDocumentedRejections {
  some h1, h2: RejectedHypothesis |
    h1.reason in EvidenceBased
    and h2.reason in PreferenceBased
    and h2.reason.rationaleNonEmpty = True
    and rejectionDocumented[h1]
    and rejectionDocumented[h2]
} for 4
