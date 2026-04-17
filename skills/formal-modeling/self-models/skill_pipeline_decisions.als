-- ================================================================
-- Critical Decisions — isolated module (no pipeline dependency)
--
-- Verifies style selection, pattern matching, counterexample response,
-- runtime choice, drift detection / entry mode, and scope progression.
-- None of these require Step ordering or Artifact dependency chains.
--
-- Extracted from skill_pipeline.als for faster solver runs.
-- ================================================================

module skill_pipeline_decisions

abstract sig Bool {}
one sig Yes, No extends Bool {}

-- ─── D1: Modeling Style ─────────────────────────────────────────

abstract sig ModelingStyle {}
one sig Static   extends ModelingStyle {}
one sig Temporal extends ModelingStyle {}
one sig UxLayer  extends ModelingStyle {}

one sig ProblemProfile {
  needsTemporalOrder:    one Bool,
  needsAccessMatrix:     one Bool,
  needsLivenessCheck:    one Bool,
  chosenStyle:           one ModelingStyle
}

fact StyleMatchesProblem {
  (ProblemProfile.needsTemporalOrder = Yes or ProblemProfile.needsLivenessCheck = Yes)
    implies ProblemProfile.chosenStyle = Temporal
  (ProblemProfile.needsAccessMatrix = Yes
    and ProblemProfile.needsTemporalOrder = No
    and ProblemProfile.needsLivenessCheck = No)
    implies ProblemProfile.chosenStyle = UxLayer
}

-- ─── D2: Pattern Selection ──────────────────────────────────────

abstract sig PatternCategory {}
one sig Basics       extends PatternCategory {}
one sig Structural   extends PatternCategory {}
one sig TemporalCat  extends PatternCategory {}
one sig UxAccess     extends PatternCategory {}
one sig DataConvert  extends PatternCategory {}
one sig Pipeline     extends PatternCategory {}
one sig Verification extends PatternCategory {}

sig SelectedPattern {
  category: one PatternCategory,
  relevantToStyle: one ModelingStyle
}

fact PatternsMatchStyle {
  all sp: SelectedPattern | sp.relevantToStyle = ProblemProfile.chosenStyle
    or sp.category = Basics
    or sp.category = Verification
}

fact DomainPatternSelected {
  some sp: SelectedPattern | sp.category != Basics and sp.category != Verification
}

-- ─── D6: Counterexample Response ────────────────────────────────

abstract sig CounterexampleResponse {}
one sig FixAndRerun   extends CounterexampleResponse {}
one sig DesignBugFound extends CounterexampleResponse {}

sig CounterexampleEvent {
  response: one CounterexampleResponse
}

-- ─── D5: Runtime Choice (Java OR Docker) ────────────────────────

abstract sig RuntimeOption {}
one sig UseLocalJava extends RuntimeOption {}
one sig UseDocker   extends RuntimeOption {}

one sig RuntimeChoice {
  chosen: one RuntimeOption
}

-- ─── D9: Entry Mode (fresh vs re-verify) ────────────────────────

abstract sig EntryMode {}
one sig FreshRun   extends EntryMode {}
one sig Reverify   extends EntryMode {}

abstract sig DriftStatus {}
one sig NoModelExists extends DriftStatus {}
one sig ModelCurrent  extends DriftStatus {}
one sig ModelStale    extends DriftStatus {}

one sig PipelineConfig {
  entryMode: one EntryMode,
  driftStatus: one DriftStatus
}

fact EntryModeFromDrift {
  PipelineConfig.driftStatus = NoModelExists implies PipelineConfig.entryMode = FreshRun
  PipelineConfig.driftStatus = ModelStale implies PipelineConfig.entryMode = Reverify
  PipelineConfig.driftStatus = ModelCurrent implies PipelineConfig.entryMode = FreshRun
}

-- ─── D10: Scope Progression ─────────────────────────────────────

abstract sig ScopeLevel {}
one sig Scope4 extends ScopeLevel {}
one sig Scope6 extends ScopeLevel {}
one sig Scope8 extends ScopeLevel {}

one sig SolverConfig {
  currentScope: one ScopeLevel,
  allPassedAtCurrentScope: one Bool
}

pred shouldIncreaseScope {
  SolverConfig.allPassedAtCurrentScope = Yes
  and SolverConfig.currentScope != Scope8
}


-- ================================================================
-- ASSERTIONS
-- ================================================================

-- A33: Temporal problems require temporal style
assert TemporalProblemRequiresTemporalStyle {
  (ProblemProfile.needsTemporalOrder = Yes or ProblemProfile.needsLivenessCheck = Yes)
    implies ProblemProfile.chosenStyle = Temporal
}

-- A34: Access-matrix problems without temporal needs → UxLayer style
assert AccessMatrixGetsUxStyle {
  (ProblemProfile.needsAccessMatrix = Yes
    and ProblemProfile.needsTemporalOrder = No
    and ProblemProfile.needsLivenessCheck = No)
    implies ProblemProfile.chosenStyle = UxLayer
}

-- A35: Selected patterns must include at least one domain-specific category
assert PatternSelectionNotGenericOnly {
  some sp: SelectedPattern | sp.category != Basics and sp.category != Verification
}

-- A36: Both counterexample response types are structurally valid
assert DesignBugIsValidResponse {
  all ce: CounterexampleEvent | ce.response = DesignBugFound or ce.response = FixAndRerun
}

-- A37: Reverify mode requires stale drift status
assert ReverifyRequiresDriftDetected {
  PipelineConfig.entryMode = Reverify implies PipelineConfig.driftStatus = ModelStale
}

-- A50: No model exists → must be fresh run
assert NoModelMeansFreshRun {
  PipelineConfig.driftStatus = NoModelExists implies PipelineConfig.entryMode = FreshRun
}

-- A38: Scope increase is suggested when all checks pass at current scope
assert ScopeProgressionAvailable {
  shouldIncreaseScope implies SolverConfig.currentScope != Scope8
}


-- ================================================================
-- CHECKS
-- ================================================================

check TemporalProblemRequiresTemporalStyle for 6
check AccessMatrixGetsUxStyle              for 6
check PatternSelectionNotGenericOnly       for 6
check DesignBugIsValidResponse             for 6
check ReverifyRequiresDriftDetected        for 6
check NoModelMeansFreshRun                 for 6
check ScopeProgressionAvailable            for 6


-- ================================================================
-- SCENARIOS
-- ================================================================

run TemporalProblemGetsTemporalStyle {
  ProblemProfile.needsTemporalOrder = Yes
  and ProblemProfile.chosenStyle = Temporal
} for 4

-- Should be UNSAT
run TemporalProblemWrongStyle {
  ProblemProfile.needsTemporalOrder = Yes
  and ProblemProfile.chosenStyle = Static
} for 4

run UxProblemSelectsUxPatterns {
  ProblemProfile.needsAccessMatrix = Yes
  and ProblemProfile.needsTemporalOrder = No
  and ProblemProfile.needsLivenessCheck = No
  and ProblemProfile.chosenStyle = UxLayer
  and some sp: SelectedPattern | sp.category = UxAccess
} for 4

run DesignBugReport {
  some ce: CounterexampleEvent | ce.response = DesignBugFound
} for 4

run CounterexampleFixAndRerun {
  some ce: CounterexampleEvent | ce.response = FixAndRerun
} for 4

run ReverifyMode {
  PipelineConfig.driftStatus = ModelStale
  and PipelineConfig.entryMode = Reverify
} for 4

run FreshRunNoModel {
  PipelineConfig.driftStatus = NoModelExists
  and PipelineConfig.entryMode = FreshRun
} for 4

-- Should be UNSAT
run ReverifyWithoutModel {
  PipelineConfig.driftStatus = NoModelExists
  and PipelineConfig.entryMode = Reverify
} for 4

run ScopeIncreaseSuggested {
  SolverConfig.currentScope = Scope4
  and SolverConfig.allPassedAtCurrentScope = Yes
  and shouldIncreaseScope
} for 4
