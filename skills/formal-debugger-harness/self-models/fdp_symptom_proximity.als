module fdp_symptom_proximity

/*
 * Segment: S0-V.1 / TC31 symptom proximity check.
 *
 * Transport-shaped symptoms (DNS failure, gaierror, connection refused,
 * socket timeout, 5xx, health-check fail) may be downstream effects of
 * the target process never starting. Before any transport-layer
 * hypothesis can be accepted, the investigator must have DIRECT evidence
 * of upstream liveness.
 *
 * Counterpart to fdp_protocol.dfy's s0v1_Satisfied.
 */

-- ============================================================
-- Domain
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

abstract sig SymptomShape {}
one sig TransportLayer, NonTransport extends SymptomShape {}

abstract sig Reliability {}
one sig Direct, Inferred, Interpreted, UnreliableSource extends Reliability {}

sig LivenessEvidence {
  reliability: one Reliability,
  observedLive: one Bool
}

-- ============================================================
-- Predicates
-- ============================================================

pred livenessIsDirect[e: LivenessEvidence] {
  e.reliability = Direct
  e.observedLive = True
}

-- S0-V.1: the per-investigation gate.
pred s0v1_Satisfied[shape: SymptomShape, e: LivenessEvidence] {
  shape = TransportLayer => livenessIsDirect[e]
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- S0V1-S1: Non-transport symptoms ignore the liveness witness.
assert S0V1_NonTransportIgnoresLiveness {
  all e: LivenessEvidence | s0v1_Satisfied[NonTransport, e]
}
check S0V1_NonTransportIgnoresLiveness for 4

-- S0V1-S2: Transport with non-direct liveness fails.
assert S0V1_TransportRequiresDirect {
  all e: LivenessEvidence |
    e.reliability != Direct => not s0v1_Satisfied[TransportLayer, e]
}
check S0V1_TransportRequiresDirect for 4

-- S0V1-S3: Transport with non-observed-live evidence fails.
assert S0V1_TransportRequiresObservedLive {
  all e: LivenessEvidence |
    e.observedLive = False => not s0v1_Satisfied[TransportLayer, e]
}
check S0V1_TransportRequiresObservedLive for 4

-- S0V1-S4: Interpreted liveness (e.g., code reading) fails the transport gate.
assert S0V1_InterpretedLivenessBlocks {
  all e: LivenessEvidence |
    e.reliability = Interpreted => not s0v1_Satisfied[TransportLayer, e]
}
check S0V1_InterpretedLivenessBlocks for 4

-- ============================================================
-- Liveness scenario (witness: valid transport investigation exists)
-- ============================================================

run ValidTransportPath {
  some e: LivenessEvidence |
    e.reliability = Direct and e.observedLive = True
    and s0v1_Satisfied[TransportLayer, e]
} for 4
