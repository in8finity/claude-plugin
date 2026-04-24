module fdp_intervention_ordering

/*
 * Segment: OB1 / TC34 observability before intervention.
 *
 * Every system change (topology, config, code) must be preceded by a
 * direct-evidence entry capturing the state being changed. Blind
 * intervention moves the target and blurs the causality chain.
 *
 * Counterpart to fdp_protocol.dfy's ob1_InterventionValid /
 * ob1_AllInterventionsValid.
 */

-- ============================================================
-- Domain
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

sig Intervention {
  observationTime: one Int,
  priorDirectEvidenceTime: one Int,
  targetStateObservable: one Bool
}

-- ============================================================
-- Predicates
-- ============================================================

pred interventionValid[i: Intervention] {
  i.targetStateObservable = True
  i.priorDirectEvidenceTime < i.observationTime
}

pred allInterventionsValid[xs: set Intervention] {
  all i: xs | interventionValid[i]
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- OB1-S1: Unobserved intervention fails regardless of timing.
assert OB1_UnobservedInterventionFails {
  all i: Intervention |
    i.targetStateObservable = False => not interventionValid[i]
}
check OB1_UnobservedInterventionFails for 4 but 4 Int

-- OB1-S2: Simultaneous evidence and intervention fails (evidence must be BEFORE).
assert OB1_SimultaneousInterventionFails {
  all i: Intervention |
    (i.targetStateObservable = True and i.priorDirectEvidenceTime = i.observationTime)
    => not interventionValid[i]
}
check OB1_SimultaneousInterventionFails for 4 but 4 Int

-- OB1-S3: Evidence AFTER intervention fails (the target was changed blind).
assert OB1_LateEvidenceFails {
  all i: Intervention |
    (i.targetStateObservable = True and i.priorDirectEvidenceTime > i.observationTime)
    => not interventionValid[i]
}
check OB1_LateEvidenceFails for 4 but 4 Int

-- OB1-S4: A well-formed intervention (observable + prior evidence strictly
-- earlier than the intervention turn) is valid. Safety check, not existence.
assert OB1_WellFormedIsValid {
  all i: Intervention |
    (i.targetStateObservable = True and i.priorDirectEvidenceTime < i.observationTime)
    => interventionValid[i]
}
check OB1_WellFormedIsValid for 4 but 4 Int

-- OB1-S5: One bad intervention poisons the whole sequence.
assert OB1_OneBadBreaksAll {
  all xs: set Intervention, bad: Intervention |
    (bad in xs and not interventionValid[bad])
    => not allInterventionsValid[xs]
}
check OB1_OneBadBreaksAll for 4 but 4 Int

-- ============================================================
-- Liveness scenarios
-- ============================================================

run ValidInterventionExists {
  some i: Intervention | interventionValid[i]
} for 4 but 4 Int

run BlindInterventionExists {
  some i: Intervention |
    i.targetStateObservable = False and not interventionValid[i]
} for 4 but 4 Int
