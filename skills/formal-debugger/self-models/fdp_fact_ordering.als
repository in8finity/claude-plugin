module fdp_fact_ordering

/*
 * Segment 4: F4 + TC19 Fact Ordering (Shallow Temporal)
 *
 * Proves production-first ordering for fact integration at S4:
 * - TC19: First fact at S4 must be Direct or Inferred (all tasks)
 * - F4: First fact at S4 must be Direct (Fix tasks only)
 *
 * No hypothesis state, no CauseClass, no full step sequence.
 * Just S4 with fact integration transitions.
 *
 * Interface contract: integrateFact ordering guards hold
 * The temporal core assumes these guards in its integrateFact pred.
 */

-- ============================================================
-- Domain (self-contained)
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

abstract sig Reliability {}
one sig Direct, Inferred, Interpreted, UnreliableSource extends Reliability {}

abstract sig TaskType {}
one sig Investigate, Fix extends TaskType {}

abstract sig SourceType {}
one sig ProductionDB, RecentProductionLogs, OldProductionLogs,
        LiveAPIResponse, DeployedConfig, RepoCode,
        LocalGitHistory, PriorReport, SpecDesignDoc,
        AlloyModelResult, UserVerbalDescription,
        MobileAppCode, ThirdPartyDocs, UserReport
  extends SourceType {}

-- F3 classification (must match main model)
fun sourceReliability[s: SourceType]: one Reliability {
  s in (ProductionDB + RecentProductionLogs + LiveAPIResponse + DeployedConfig)
    => Direct
  else s in (OldProductionLogs + AlloyModelResult + UserReport)
    => Inferred
  else s in (RepoCode + LocalGitHistory + PriorReport + SpecDesignDoc
             + UserVerbalDescription + ThirdPartyDocs)
    => Interpreted
  else
    UnreliableSource
}

-- ============================================================
-- Minimal temporal state: just S4 fact collection
-- ============================================================

one sig S4State {
  taskType: one TaskType,
  var firstFactCollected: one Bool,
  var hasProductionEvidence: one Bool,
  var evidenceLogHasDirect: one Bool
}

sig Fact {
  source: one SourceType,
  reliability: one Reliability,
  var integrated: one Bool
}

fact F3_Consistent {
  all f: Fact | f.reliability = sourceReliability[f.source]
}

fact Init {
  S4State.firstFactCollected = False
  S4State.hasProductionEvidence = False
  S4State.evidenceLogHasDirect = False
  all f: Fact | f.integrated = False
}

-- ============================================================
-- Transitions
-- ============================================================

pred frameFacts[changed: Fact] {
  all f: Fact - changed | f.integrated' = f.integrated
}

pred frameState {
  S4State.firstFactCollected' = S4State.firstFactCollected
  S4State.hasProductionEvidence' = S4State.hasProductionEvidence
  S4State.evidenceLogHasDirect' = S4State.evidenceLogHasDirect
}

pred stutter {
  frameState
  all f: Fact | f.integrated' = f.integrated
}

pred integrateFact[f: Fact] {
  f.integrated = False
  -- TC19: first fact must be production-grade (all tasks)
  (S4State.firstFactCollected = False)
    => f.reliability in (Direct + Inferred)
  -- F4: Fix tasks require Direct first fact
  (S4State.taskType = Fix and S4State.firstFactCollected = False)
    => f.reliability = Direct
  -- Execute
  f.integrated' = True
  S4State.firstFactCollected' = True
  -- Update production evidence flags
  (f.reliability = Direct) => (
    S4State.hasProductionEvidence' = True
    and S4State.evidenceLogHasDirect' = True
  ) else (
    S4State.hasProductionEvidence' = S4State.hasProductionEvidence
    and S4State.evidenceLogHasDirect' = S4State.evidenceLogHasDirect
  )
  frameFacts[f]
}

fact Transitions {
  always (
    stutter
    or (some f: Fact | integrateFact[f])
  )
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- F4-S1: Fix task's first fact must be Direct
assert F4_FixRequiresDirect {
  always (
    (S4State.taskType = Fix
     and S4State.firstFactCollected = False
     and S4State.firstFactCollected' = True)
    =>
    (some f: Fact | f.integrated = False and f.integrated' = True
                    and f.reliability = Direct)
  )
}
check F4_FixRequiresDirect for 4 but 3 Fact, 10 steps

-- TC19-S1: First fact must be Direct or Inferred (all tasks)
assert TC19_ProductionFirst {
  always (
    (S4State.firstFactCollected = False
     and S4State.firstFactCollected' = True)
    =>
    (some f: Fact | f.integrated = False and f.integrated' = True
                    and f.reliability in (Direct + Inferred))
  )
}
check TC19_ProductionFirst for 4 but 3 Fact, 10 steps

-- F4-S2: Investigate task allows Inferred first fact
-- (no additional constraint beyond TC19)
assert F4_InvestigateAllowsInferred {
  always (
    (S4State.taskType = Investigate
     and S4State.firstFactCollected = False
     and S4State.firstFactCollected' = True)
    =>
    (some f: Fact | f.integrated = False and f.integrated' = True
                    and f.reliability in (Direct + Inferred))
  )
}
check F4_InvestigateAllowsInferred for 4 but 3 Fact, 10 steps

-- F4-S3: Interpreted fact cannot be first (for any task)
assert F4_InterpretedCannotBeFirst {
  always (
    (S4State.firstFactCollected = False
     and S4State.firstFactCollected' = True)
    =>
    not (some f: Fact | f.integrated = False and f.integrated' = True
                        and f.reliability = Interpreted)
  )
}
check F4_InterpretedCannotBeFirst for 4 but 3 Fact, 10 steps

-- F4-S4: UnreliableSource fact cannot be first (for any task)
assert F4_UnreliableCannotBeFirst {
  always (
    (S4State.firstFactCollected = False
     and S4State.firstFactCollected' = True)
    =>
    not (some f: Fact | f.integrated = False and f.integrated' = True
                        and f.reliability = UnreliableSource)
  )
}
check F4_UnreliableCannotBeFirst for 4 but 3 Fact, 10 steps

-- F3-S1: Integrating repo code cannot set production evidence
assert F3_RepoCodeCantSetProductionEvidence {
  always (
    (some f: Fact | f.source = RepoCode and f.integrated = False and f.integrated' = True)
    =>
    (S4State.hasProductionEvidence' = S4State.hasProductionEvidence
     or S4State.hasProductionEvidence = True)
  )
}
check F3_RepoCodeCantSetProductionEvidence for 4 but 3 Fact, 10 steps

-- ============================================================
-- Scenarios
-- ============================================================

-- Investigate task can integrate Interpreted fact AFTER first production fact
run InvestigateInterpretedAfterFirst {
  S4State.taskType = Investigate
  and some f: Fact | f.source = RepoCode
    and eventually (f.integrated = True)
} for 4 but exactly 2 Fact, 12 steps

-- Fix task integrates Direct fact first, then anything
run FixDirectFirst {
  S4State.taskType = Fix
  and eventually (S4State.firstFactCollected = True
    and S4State.hasProductionEvidence = True)
} for 4 but exactly 2 Fact, 8 steps
