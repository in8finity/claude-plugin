module fdp_baseline_comparability

/*
 * Segment: F10 / TC32 baseline comparability.
 *
 * A differential against "last known good" only informs if the baseline
 * matches on repository, trigger type, and config. Mismatched baselines
 * pollute the differential and must not reach the termination gate.
 *
 * Counterpart to fdp_protocol.dfy's baselineMatches / f10_baselineComparable.
 */

-- ============================================================
-- Domain
-- ============================================================

sig Repo {}
sig Trigger {}
sig Config {}

sig Baseline {
  repo: one Repo,
  trigger: one Trigger,
  config: one Config
}

-- ============================================================
-- Predicates
-- ============================================================

pred baselineMatches[a, b: Baseline] {
  a.repo = b.repo
  a.trigger = b.trigger
  a.config = b.config
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- F10-S1: Mismatched repo fails.
assert F10_MismatchedRepoFails {
  all a, b: Baseline | a.repo != b.repo => not baselineMatches[a, b]
}
check F10_MismatchedRepoFails for 4

-- F10-S2: Same repo but different trigger fails.
assert F10_MismatchedTriggerFails {
  all a, b: Baseline |
    (a.repo = b.repo and a.trigger != b.trigger)
    => not baselineMatches[a, b]
}
check F10_MismatchedTriggerFails for 4

-- F10-S3: Same repo and trigger but different config fails.
assert F10_MismatchedConfigFails {
  all a, b: Baseline |
    (a.repo = b.repo and a.trigger = b.trigger and a.config != b.config)
    => not baselineMatches[a, b]
}
check F10_MismatchedConfigFails for 4

-- F10-S4: Match iff all three axes align.
assert F10_MatchIffAllAxes {
  all a, b: Baseline |
    baselineMatches[a, b]
    <=> (a.repo = b.repo and a.trigger = b.trigger and a.config = b.config)
}
check F10_MatchIffAllAxes for 4

-- F10-S5: Matching is reflexive (any baseline matches itself).
assert F10_Reflexive {
  all a: Baseline | baselineMatches[a, a]
}
check F10_Reflexive for 4

-- ============================================================
-- Liveness scenarios
-- ============================================================

-- Matching baselines exist (the happy path).
run ComparableBaselinesExist {
  some disj a, b: Baseline | baselineMatches[a, b]
} for 4

-- A mismatched pair exists (counterexample to naive differentials).
run MismatchedBaselinesExist {
  some disj a, b: Baseline | not baselineMatches[a, b]
} for 4
