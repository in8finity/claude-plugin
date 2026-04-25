module fdp_dynamic_data

/*
 * Segment 2: F3 Dynamic Data Verification — TC23 (Static)
 *
 * Proves that the TC23 gate logic is correct: hypotheses depending on
 * dynamic data (DB templates, config, feature flags) cannot pass the
 * acceptance gate without all three verification checks.
 *
 * Interface contract: tc23_gate_passes[h] iff
 *   h.dynamicDataDependent = False OR all three data checks = True
 * The temporal core calls this predicate inside acceptHypothesis.
 */

-- ============================================================
-- Domain (self-contained)
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

-- A hypothesis's dynamic data state at the acceptance point
sig HypDataState {
  dependent: one Bool,              -- does hypothesis depend on dynamic data?
  currentValueVerified: one Bool,   -- (a) current value queried from production
  changeHistoryVerified: one Bool,  -- (b) audit trail / revision table checked
  timelineCoverageVerified: one Bool -- (c) triggering condition covers symptom window
}

-- ============================================================
-- TC23 gate predicate (the contract)
-- ============================================================

pred tc23_gate_passes[d: HypDataState] {
  d.dependent = True implies (
    d.currentValueVerified = True
    and d.changeHistoryVerified = True
    and d.timelineCoverageVerified = True
  )
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- TC23-S1: Gate blocks when dependent and current value unverified
assert TC23_BlocksMissingCurrentValue {
  all d: HypDataState |
    d.dependent = True and d.currentValueVerified = False
    => not tc23_gate_passes[d]
}
check TC23_BlocksMissingCurrentValue for 6

-- TC23-S2: Gate blocks when dependent and change history unverified
assert TC23_BlocksMissingChangeHistory {
  all d: HypDataState |
    d.dependent = True and d.changeHistoryVerified = False
    => not tc23_gate_passes[d]
}
check TC23_BlocksMissingChangeHistory for 6

-- TC23-S3: Gate blocks when dependent and timeline coverage unverified
assert TC23_BlocksMissingTimeline {
  all d: HypDataState |
    d.dependent = True and d.timelineCoverageVerified = False
    => not tc23_gate_passes[d]
}
check TC23_BlocksMissingTimeline for 6

-- TC23-S4: Gate passes when all three checks verified
assert TC23_PassesWhenAllVerified {
  all d: HypDataState |
    d.dependent = True
    and d.currentValueVerified = True
    and d.changeHistoryVerified = True
    and d.timelineCoverageVerified = True
    => tc23_gate_passes[d]
}
check TC23_PassesWhenAllVerified for 6

-- TC23-S5: Gate passes vacuously when not dependent on dynamic data
assert TC23_VacuousSatisfaction {
  all d: HypDataState |
    d.dependent = False => tc23_gate_passes[d]
}
check TC23_VacuousSatisfaction for 6

-- TC23-S6: Gate blocks on completely unverified dynamic data
assert TC23_BlocksUnverified {
  all d: HypDataState |
    d.dependent = True
    and d.currentValueVerified = False
    and d.changeHistoryVerified = False
    and d.timelineCoverageVerified = False
    => not tc23_gate_passes[d]
}
check TC23_BlocksUnverified for 6

-- TC23-S7: Only Full verification passes for dependent hypotheses
-- (partial verification is insufficient)
assert TC23_PartialIsInsufficient {
  all d: HypDataState |
    d.dependent = True
    and (d.currentValueVerified = False
         or d.changeHistoryVerified = False
         or d.timelineCoverageVerified = False)
    => not tc23_gate_passes[d]
}
check TC23_PartialIsInsufficient for 6

-- ============================================================
-- Scenarios
-- ============================================================

-- Can a dependent hypothesis pass the gate?
run DependentPasses {
  some d: HypDataState |
    d.dependent = True and tc23_gate_passes[d]
} for exactly 2 HypDataState

-- Can a non-dependent hypothesis pass without any verification?
run NonDependentPasses {
  some d: HypDataState |
    d.dependent = False
    and d.currentValueVerified = False
    and d.changeHistoryVerified = False
    and d.timelineCoverageVerified = False
    and tc23_gate_passes[d]
} for exactly 1 HypDataState

-- Can a dependent hypothesis with partial verification fail?
run PartialVerificationFails {
  some d: HypDataState |
    d.dependent = True
    and d.currentValueVerified = True
    and d.changeHistoryVerified = True
    and d.timelineCoverageVerified = False
    and not tc23_gate_passes[d]
} for exactly 1 HypDataState
