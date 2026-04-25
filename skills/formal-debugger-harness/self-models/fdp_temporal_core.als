module fdp_temporal_core

/*
 * Segment 5: Temporal Core (Lean)
 *
 * The full step machine (S0→S8 with S7→S2 loop), hypothesis lifecycle,
 * fact integration, and acceptance gate — with reduced state space.
 *
 * State reductions (proved correct by segments 1-4):
 *   - skipProposed + skipAcknowledged → modelOrSkipReady (1 var Bool)
 *     Justified by: fdp_skip_protocol.als (5 checks, 3 runs)
 *   - 3x dynamicData* per Hypothesis → dynamicDataReady (1 var Bool)
 *     Justified by: fdp_dynamic_data.als (7 checks, 3 runs)
 *   - F3, F4, TC19 ordering checks removed (proved in segments)
 *     Justified by: fdp_source_classification.als, fdp_fact_ordering.als
 *
 * Net reduction: 7 fewer Boolean state variables = ~128x smaller state space.
 */

-- ============================================================
-- Domain enums
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

abstract sig Step {}
one sig S0_Symptom, S1_Model, S2_Hypotheses, S3_Checks,
        S4_Facts, S5_Update, S6_Equivalence, S7_Deepen,
        S8_Terminate extends Step {}

abstract sig HStatus {}
one sig Active, Rejected, Weakened, Compatible, Undistinguished, Accepted extends HStatus {}

abstract sig Reliability {}
one sig Direct, Inferred, Interpreted, UnreliableSource extends Reliability {}

abstract sig DiagStrength {}
one sig Strong, Weak, Irrelevant extends DiagStrength {}

-- M1: 14 cause classes
abstract sig CauseClass {}
one sig CC_Concurrency, CC_SharedMutableState, CC_ObjectLifecycle, CC_Caching,
        CC_AsyncBoundaries, CC_ExternalSystem, CC_PartialObservability,
        CC_ConfigFeatureFlags, CC_DataMigration, CC_TenantIsolation,
        CC_AuthState, CC_DeploymentDrift, CC_MultiArtifact, CC_BuildPipeline
  extends CauseClass {}

-- ============================================================
-- Core entities (reduced var fields)
-- ============================================================

sig Hypothesis {
  hasMechanism: one Bool,
  hasCounterfactual: one Bool,
  dynamicDataDependent: one Bool,       -- F3/TC23: immutable
  var counterfactualObservable: one Bool,
  var alternativeConsidered: one Bool,
  var counterfactualVerified: one Bool,
  var dynamicDataReady: one Bool,       -- COLLAPSED: replaces 3 individual data checks
  -- PW3: hypothesis log events
  var loggedMechanism: one Bool,
  var loggedCounterfactual: one Bool,
  var loggedObservability: one Bool,
  var loggedAlternative: one Bool,
  var status: one HStatus
}

sig Fact {
  reliability: one Reliability,
  var integrated: one Bool,
  var stale: one Bool
}

sig Check {
  strength: one DiagStrength,
  distinguishes: set Hypothesis
}

one sig Investigation {
  var currentStep: one Step,
  var modelBuilt: one Bool,
  var causesCovered: set CauseClass,
  var hasProductionEvidence: one Bool,
  var symptomVerified: one Bool,
  var toolingInventoried: one Bool,
  var evidenceLogHasDirect: one Bool,
  var modelRerunAfterFacts: one Bool,
  var firstS4FactCollected: one Bool,
  var equivalenceChecked: one Bool,
  var modelOrSkipReady: one Bool,      -- COLLAPSED: replaces skipProposed + skipAcknowledged
  var stubFilesCreated: one Bool       -- PW0-init/TC29: four log files on disk
}

-- ============================================================
-- Initial state
-- ============================================================

fact Init {
  Investigation.currentStep = S0_Symptom
  Investigation.modelBuilt = False
  no Investigation.causesCovered
  Investigation.hasProductionEvidence = False
  Investigation.symptomVerified = False
  Investigation.toolingInventoried = False
  Investigation.evidenceLogHasDirect = False
  Investigation.modelRerunAfterFacts = False
  Investigation.firstS4FactCollected = False
  Investigation.equivalenceChecked = False
  Investigation.modelOrSkipReady = False
  Investigation.stubFilesCreated = False
  all h: Hypothesis | h.status = Active and h.counterfactualObservable = False
    and h.alternativeConsidered = False and h.counterfactualVerified = False
    and h.dynamicDataReady = False
    and h.loggedMechanism = False and h.loggedCounterfactual = False
    and h.loggedObservability = False and h.loggedAlternative = False
  all f: Fact | f.integrated = False and f.stale = False
}

-- ============================================================
-- Frame conditions
-- ============================================================

pred frameHypotheses {
  all h: Hypothesis |
    h.status' = h.status
    and h.counterfactualObservable' = h.counterfactualObservable
    and h.alternativeConsidered' = h.alternativeConsidered
    and h.counterfactualVerified' = h.counterfactualVerified
    and h.dynamicDataReady' = h.dynamicDataReady
    and h.loggedMechanism' = h.loggedMechanism
    and h.loggedCounterfactual' = h.loggedCounterfactual
    and h.loggedObservability' = h.loggedObservability
    and h.loggedAlternative' = h.loggedAlternative
}

pred frameFacts {
  all f: Fact | f.integrated' = f.integrated and f.stale' = f.stale
}

pred frameInvestigation {
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
}

pred stutter { frameHypotheses and frameFacts and frameInvestigation }

pred frameOtherHypotheses[h: Hypothesis] {
  all h2: Hypothesis - h |
    h2.status' = h2.status
    and h2.counterfactualObservable' = h2.counterfactualObservable
    and h2.alternativeConsidered' = h2.alternativeConsidered
    and h2.counterfactualVerified' = h2.counterfactualVerified
    and h2.dynamicDataReady' = h2.dynamicDataReady
    and h2.loggedMechanism' = h2.loggedMechanism
    and h2.loggedCounterfactual' = h2.loggedCounterfactual
    and h2.loggedObservability' = h2.loggedObservability
    and h2.loggedAlternative' = h2.loggedAlternative
}

pred preserveHypFlags[h: Hypothesis] {
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dynamicDataReady' = h.dynamicDataReady
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
}

-- ============================================================
-- Step transitions
-- ============================================================

fun nextStep[s: Step]: lone Step {
  s = S0_Symptom     => S1_Model else
  s = S1_Model       => S2_Hypotheses else
  s = S2_Hypotheses  => S3_Checks else
  s = S3_Checks      => S4_Facts else
  s = S4_Facts       => S5_Update else
  s = S5_Update      => S6_Equivalence else
  s = S6_Equivalence => S7_Deepen else
  s = S7_Deepen      => S2_Hypotheses else
  s = S8_Terminate   => none else
  none
}

pred advanceStep {
  let curr = Investigation.currentStep |
    some nextStep[curr]
    and curr != S1_Model
    and (curr = S0_Symptom => (Investigation.toolingInventoried = True
                               and Investigation.symptomVerified = True))
    and Investigation.currentStep' = nextStep[curr]
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  (Investigation.currentStep = S5_Update) =>
    Investigation.modelRerunAfterFacts' = True
  else
    Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

pred verifySymptom[f: Fact] {
  Investigation.currentStep = S0_Symptom
  Investigation.stubFilesCreated = True   -- PW0-init gate
  Investigation.toolingInventoried = True
  f.reliability = Direct
  f.integrated = False
  f.integrated' = True
  Investigation.symptomVerified' = True
  Investigation.hasProductionEvidence' = True
  Investigation.evidenceLogHasDirect' = True
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  f.stale' = False
  all f2: Fact - f | f2.integrated' = f2.integrated and f2.stale' = f2.stale
  frameHypotheses
}

pred systemChange {
  some f: Fact | f.integrated = True and f.reliability = Direct and f.stale = False
  all f: Fact | (f.integrated = True and f.reliability = Direct) =>
    f.stale' = True
  else
    f.stale' = f.stale
  all f: Fact | f.integrated' = f.integrated
  frameHypotheses
  frameInvestigation
}

pred reverifyFact[f: Fact] {
  f.stale = True
  f.integrated = True
  f.stale' = False
  all f2: Fact - f | f2.integrated' = f2.integrated and f2.stale' = f2.stale
  frameHypotheses
  frameInvestigation
}

-- PW0-init/TC29: create the four log files (evidence-log, hypothesis-log,
-- model-change-log, investigation-report) before any other Step 0 action.
-- Monotonic: once created, stays created.
pred createStubs {
  Investigation.currentStep = S0_Symptom
  Investigation.stubFilesCreated = False
  Investigation.stubFilesCreated' = True
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  frameHypotheses
  frameFacts
}

pred inventoryTooling {
  Investigation.currentStep = S0_Symptom
  Investigation.stubFilesCreated = True   -- PW0-init gate: stubs must exist
  Investigation.toolingInventoried = False
  Investigation.toolingInventoried' = True
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

-- Build model (sets both modelBuilt and modelOrSkipReady)
pred buildModel {
  Investigation.currentStep = S1_Model
  Investigation.hasProductionEvidence = True  -- FM1 gate
  Investigation.currentStep' = S2_Hypotheses
  Investigation.modelBuilt' = True
  Investigation.modelOrSkipReady' = True     -- TC24 satisfied via build
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

-- Skip model (collapsed: sets modelOrSkipReady without building)
-- Segment fdp_skip_protocol.als proved the propose→acknowledge ordering
pred skipModel {
  Investigation.currentStep = S1_Model
  Investigation.hasProductionEvidence = True  -- PV2 gate
  Investigation.currentStep' = S2_Hypotheses
  Investigation.modelBuilt' = False
  Investigation.modelOrSkipReady' = True     -- TC24 satisfied via acknowledged skip
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

pred tryTerminate {
  Investigation.currentStep = S6_Equivalence
  no h: Hypothesis | h.status = Undistinguished
  Investigation.currentStep' = S8_Terminate
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

-- ============================================================
-- Fact integration (ordering guards proved by fdp_fact_ordering.als)
-- ============================================================

pred integrateFact[f: Fact] {
  Investigation.currentStep = S4_Facts
  f.integrated = False
  -- TC19/F4 ordering guards (proved in segment, enforced here structurally)
  (Investigation.firstS4FactCollected = False)
    => f.reliability in (Direct + Inferred)
  f.integrated' = True
  (f.reliability = Direct) => (
    Investigation.hasProductionEvidence' = True
    and Investigation.evidenceLogHasDirect' = True
  ) else (
    Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
    and Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  )
  Investigation.modelRerunAfterFacts' = False
  Investigation.firstS4FactCollected' = True
  f.stale' = False
  all f2: Fact - f | f2.integrated' = f2.integrated and f2.stale' = f2.stale
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
}

-- ============================================================
-- Hypothesis transitions
-- ============================================================

pred rejectHypothesis[h: Hypothesis] {
  Investigation.currentStep = S5_Update
  h.status = Active or h.status = Weakened or h.status = Compatible
  h.status' = Rejected
  preserveHypFlags[h]
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred weakenHypothesis[h: Hypothesis] {
  Investigation.currentStep = S5_Update
  h.status = Active or h.status = Compatible
  h.status' = Weakened
  preserveHypFlags[h]
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred markCompatible[h: Hypothesis] {
  Investigation.currentStep = S5_Update
  h.status = Active
  h.status' = Compatible
  preserveHypFlags[h]
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred markUndistinguished[h: Hypothesis] {
  Investigation.currentStep = S6_Equivalence
  h.status = Compatible
  some h2: Hypothesis - h | h2.status = Compatible
  h.status' = Undistinguished
  preserveHypFlags[h]
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred considerAlternative[h: Hypothesis] {
  Investigation.currentStep in (S6_Equivalence + S8_Terminate)
  h.alternativeConsidered = False
  h.alternativeConsidered' = True
  h.loggedAlternative' = True
  h.counterfactualObservable' = h.counterfactualObservable
  h.counterfactualVerified' = h.counterfactualVerified
  h.dynamicDataReady' = h.dynamicDataReady
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred logMechanism[h: Hypothesis] {
  Investigation.currentStep = S2_Hypotheses
  h.hasMechanism = True
  h.loggedMechanism = False
  h.loggedMechanism' = True
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dynamicDataReady' = h.dynamicDataReady
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred logCounterfactual[h: Hypothesis] {
  Investigation.currentStep = S2_Hypotheses
  h.hasCounterfactual = True
  h.loggedCounterfactual = False
  h.loggedCounterfactual' = True
  h.loggedMechanism' = h.loggedMechanism
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dynamicDataReady' = h.dynamicDataReady
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred logEquivalenceCheck {
  Investigation.currentStep = S6_Equivalence
  Investigation.equivalenceChecked = False
  Investigation.equivalenceChecked' = True
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

pred assessObservability[h: Hypothesis] {
  Investigation.currentStep in (S2_Hypotheses + S3_Checks + S4_Facts + S5_Update + S6_Equivalence + S7_Deepen)
  h.hasCounterfactual = True
  h.counterfactualObservable = False
  h.counterfactualObservable' = True
  h.loggedObservability' = True
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dynamicDataReady' = h.dynamicDataReady
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedAlternative' = h.loggedAlternative
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred verifyCounterfactual[h: Hypothesis] {
  Investigation.currentStep in (S4_Facts + S5_Update)
  h.hasCounterfactual = True
  h.counterfactualObservable = True
  h.counterfactualVerified = False
  Investigation.hasProductionEvidence = True
  h.counterfactualVerified' = True
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.dynamicDataReady' = h.dynamicDataReady
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- TC23 collapsed: set dynamicDataReady (segment proved the 3-check logic)
pred setDynamicDataReady[h: Hypothesis] {
  Investigation.currentStep in (S4_Facts + S5_Update)
  h.dynamicDataDependent = True
  h.dynamicDataReady = False
  Investigation.hasProductionEvidence = True
  h.dynamicDataReady' = True
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

pred coverCauseClass[c: CauseClass] {
  Investigation.currentStep = S6_Equivalence or Investigation.currentStep = S8_Terminate
  c not in Investigation.causesCovered
  Investigation.causesCovered' = Investigation.causesCovered + c
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.modelOrSkipReady' = Investigation.modelOrSkipReady
  Investigation.stubFilesCreated' = Investigation.stubFilesCreated
  frameHypotheses
  frameFacts
}

-- ============================================================
-- Acceptance gate (all conditions)
-- ============================================================

pred acceptHypothesis[h: Hypothesis] {
  Investigation.currentStep = S8_Terminate
  h.hasMechanism = True                -- TC2/H1
  h.hasCounterfactual = True           -- TC3/H2
  h.counterfactualObservable = True    -- TC4/FZ2
  h.counterfactualVerified = True      -- TC5
  h.alternativeConsidered = True       -- TC7/M2
  h.status = Compatible
  no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active)  -- TC1+TC6
  CauseClass = Investigation.causesCovered                -- TC8/M1
  Investigation.hasProductionEvidence = True              -- TC9/PV1
  Investigation.evidenceLogHasDirect = True               -- TC11/PW1
  (Investigation.modelBuilt = True) => Investigation.modelRerunAfterFacts = True  -- TC12/PW2
  no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True  -- TC10/F5
  h.loggedMechanism = True             -- TC13/PW3
  h.loggedCounterfactual = True        -- TC14/PW3
  h.loggedObservability = True         -- TC15/PW3
  h.loggedAlternative = True           -- TC16/PW3
  Investigation.equivalenceChecked = True  -- TC17/PW3
  -- TC23: F3 dynamic data gate (proved in fdp_dynamic_data.als)
  (h.dynamicDataDependent = True) => h.dynamicDataReady = True
  -- TC24: formal model or skip (proved in fdp_skip_protocol.als)
  Investigation.modelOrSkipReady = True
  -- Execute
  h.status' = Accepted
  preserveHypFlags[h]
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- ============================================================
-- Transition system
-- ============================================================

fact Transitions {
  always (
    stutter
    or advanceStep
    or createStubs
    or (some f: Fact | verifySymptom[f])
    or inventoryTooling
    or systemChange
    or (some f: Fact | reverifyFact[f])
    or buildModel
    or skipModel
    or tryTerminate
    or (some c: CauseClass | coverCauseClass[c])
    or (some h: Hypothesis | considerAlternative[h])
    or (some h: Hypothesis | logMechanism[h])
    or (some h: Hypothesis | logCounterfactual[h])
    or logEquivalenceCheck
    or (some h: Hypothesis | assessObservability[h])
    or (some h: Hypothesis | verifyCounterfactual[h])
    or (some h: Hypothesis | setDynamicDataReady[h])
    or (some f: Fact | integrateFact[f])
    or (some h: Hypothesis | rejectHypothesis[h])
    or (some h: Hypothesis | weakenHypothesis[h])
    or (some h: Hypothesis | markCompatible[h])
    or (some h: Hypothesis | markUndistinguished[h])
    or (some h: Hypothesis | acceptHypothesis[h])
  )
}

-- ============================================================
-- SAFETY ASSERTIONS (temporal — require full step machine)
-- ============================================================

-- PW0-init / TC29: tooling inventory and symptom verification cannot have
-- happened without stubs being in place (by monotonicity, any state where
-- tooling=T or symptomVerified=T must have stubs=T, since the only
-- transitions that set those flags require stubs=T).
assert PW0Init_StubsBeforeTooling {
  always (Investigation.toolingInventoried = True
          => Investigation.stubFilesCreated = True)
}
check PW0Init_StubsBeforeTooling for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert PW0Init_StubsBeforeSymptomVerification {
  always (Investigation.symptomVerified = True
          => Investigation.stubFilesCreated = True)
}
check PW0Init_StubsBeforeSymptomVerification for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- TC29: before leaving S0_Symptom, stubs must exist.
assert PW0Init_StubsBeforeLeavingS0 {
  always (
    (Investigation.currentStep = S0_Symptom and Investigation.currentStep' = S1_Model)
    => Investigation.stubFilesCreated = True
  )
}
check PW0Init_StubsBeforeLeavingS0 for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert S0V_SymptomVerificationRequired {
  always (
    (Investigation.currentStep = S0_Symptom and Investigation.currentStep' = S1_Model)
    => Investigation.symptomVerified = True
  )
}
check S0V_SymptomVerificationRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert S0aT_ToolingInventoryRequired {
  always (
    (Investigation.currentStep = S0_Symptom and Investigation.currentStep' = S1_Model)
    => Investigation.toolingInventoried = True
  )
}
check S0aT_ToolingInventoryRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert FM1_GroundBeforeModeling {
  always (
    (Investigation.currentStep = S1_Model and Investigation.modelBuilt' = True)
    => Investigation.hasProductionEvidence = True
  )
}
check FM1_GroundBeforeModeling for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert PV1_ProductionEvidenceRequired {
  always (all h: Hypothesis | h.status' = Accepted =>
    Investigation.hasProductionEvidence = True)
}
check PV1_ProductionEvidenceRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert PV2_ModelSkipRequiresEvidence {
  always (
    (Investigation.currentStep = S1_Model
     and Investigation.currentStep' = S2_Hypotheses
     and Investigation.modelBuilt' = False)
    => Investigation.hasProductionEvidence = True
  )
}
check PV2_ModelSkipRequiresEvidence for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert U1_NoAcceptanceWithAlternatives {
  always (all h: Hypothesis | h.status' = Accepted =>
    no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active))
}
check U1_NoAcceptanceWithAlternatives for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert H1_MechanismRequired {
  always (all h: Hypothesis | h.status' = Accepted => h.hasMechanism = True)
}
check H1_MechanismRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert H2_FZ1_CounterfactualRequired {
  always (all h: Hypothesis | h.status' = Accepted => h.hasCounterfactual = True)
}
check H2_FZ1_CounterfactualRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert M1_AllCauseClassesCovered {
  always (all h: Hypothesis | h.status' = Accepted =>
    CauseClass = Investigation.causesCovered)
}
check M1_AllCauseClassesCovered for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

assert M2_AlternativeRequired {
  always (all h: Hypothesis | h.status' = Accepted => h.alternativeConsidered = True)
}
check M2_AlternativeRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert PW1_EvidenceLogHasDirect {
  always (all h: Hypothesis | h.status' = Accepted =>
    Investigation.evidenceLogHasDirect = True)
}
check PW1_EvidenceLogHasDirect for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert PW2_ModelRerunAfterFacts {
  always (all h: Hypothesis | h.status' = Accepted =>
    (Investigation.modelBuilt = True => Investigation.modelRerunAfterFacts = True))
}
check PW2_ModelRerunAfterFacts for 4 but 3 Hypothesis, 3 Fact, 4 Check, 12 steps

assert PW3_HypothesisLogComplete {
  always (all h: Hypothesis | h.status' = Accepted => (
    h.loggedMechanism = True
    and h.loggedCounterfactual = True
    and h.loggedObservability = True
    and h.loggedAlternative = True
    and Investigation.equivalenceChecked = True
  ))
}
check PW3_HypothesisLogComplete for 4 but 3 Hypothesis, 3 Fact, 4 Check, 12 steps

assert F5_NoStaleEvidenceAtAcceptance {
  always (all h: Hypothesis | h.status' = Accepted =>
    no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True)
}
check F5_NoStaleEvidenceAtAcceptance for 4 but 2 Hypothesis, 2 Fact, 1 Check, 14 steps

assert FZ2_ObservabilityRequired {
  always (all h: Hypothesis | h.counterfactualVerified' = True =>
    h.counterfactualObservable = True)
}
check FZ2_ObservabilityRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert FZ2_UnobservableBlocksAcceptance {
  always (all h: Hypothesis | h.status' = Accepted =>
    h.counterfactualObservable = True)
}
check FZ2_UnobservableBlocksAcceptance for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert CounterfactualMustBeVerified {
  always (all h: Hypothesis | h.status' = Accepted => h.counterfactualVerified = True)
}
check CounterfactualMustBeVerified for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- TC23 in temporal context: dynamic data gate at acceptance
assert TC23_DynamicDataGateHolds {
  always (all h: Hypothesis | h.status' = Accepted =>
    (h.dynamicDataDependent = True => h.dynamicDataReady = True))
}
check TC23_DynamicDataGateHolds for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

-- TC24 in temporal context: model or skip ready at acceptance
assert TC24_ModelOrSkipReady {
  always (all h: Hypothesis | h.status' = Accepted =>
    Investigation.modelOrSkipReady = True)
}
check TC24_ModelOrSkipReady for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

-- Full acceptance gate (all 24 conditions — integration test)
assert FullAcceptanceGate {
  always (all h: Hypothesis | h.status' = Accepted => (
    h.hasMechanism = True
    and h.hasCounterfactual = True
    and h.counterfactualObservable = True
    and h.counterfactualVerified = True
    and h.alternativeConsidered = True
    and CauseClass = Investigation.causesCovered
    and Investigation.hasProductionEvidence = True
    and no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active)
    and no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True
    and Investigation.evidenceLogHasDirect = True
    and (Investigation.modelBuilt = True => Investigation.modelRerunAfterFacts = True)
    and h.loggedMechanism = True
    and h.loggedCounterfactual = True
    and h.loggedObservability = True
    and h.loggedAlternative = True
    and Investigation.equivalenceChecked = True
    and (h.dynamicDataDependent = True => h.dynamicDataReady = True)
    and Investigation.modelOrSkipReady = True
  ))
}
check FullAcceptanceGate for 4 but 2 Hypothesis, 2 Fact, 2 Check, 14 steps

assert InterpretedAloneCantAccept {
  always (
    (all f: Fact | f.integrated = True => f.reliability in (Interpreted + UnreliableSource))
    => (no h: Hypothesis | h.status = Accepted)
  )
}
check InterpretedAloneCantAccept for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

assert MustCollectFactsBeforeTermination {
  always (Investigation.currentStep' = S8_Terminate =>
    once Investigation.currentStep = S4_Facts)
}
check MustCollectFactsBeforeTermination for 4 but 2 Hypothesis, 2 Fact, 2 Check, 12 steps

-- ============================================================
-- SCENARIOS
-- ============================================================

run AllRejected {
  some f: Fact | f.reliability = Direct
  eventually (all h: Hypothesis | h.status = Rejected)
} for 4 but exactly 3 Hypothesis, exactly 2 Fact, 2 Check, 14 steps

run TerminateWithoutModel {
  some f: Fact | f.reliability = Direct
  and eventually (Investigation.currentStep = S8_Terminate
    and Investigation.modelBuilt = False)
} for 4 but exactly 2 Hypothesis, exactly 1 Fact, 1 Check, 12 steps

run EquivalenceForcesDeepening {
  some disj h1, h2: Hypothesis |
    eventually (h1.status = Undistinguished
      and eventually Investigation.currentStep = S7_Deepen)
} for 4 but exactly 2 Hypothesis, exactly 1 Fact, 2 Check, 16 steps
