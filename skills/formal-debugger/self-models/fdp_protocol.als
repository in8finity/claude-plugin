module FormalDebuggerProtocol

/*
 * Formal model of the Formal Debugger skill's investigation protocol.
 *
 * Models the outer loop (Steps 0-8), hypothesis lifecycle, fact collection,
 * and the anti-false-positive rules (H1/H2, T1/T2, U1/U2, M1/M2, F1/F2, PV1/PV2).
 *
 * Naming: SKILL.md defines H2 as the falsifiability rule ("state what observation
 * would make it false"). FZ1/FZ2 elaborate H2 — FZ1 requires a counterfactual,
 * FZ2 distinguishes observable vs theoretical falsifiability. The model uses
 * H2_FZ1 for the combined gate.
 *
 * Key safety properties verified:
 *   - Symptom must be verified by direct evidence before Step 1 (S0-V)
 *   - Model cannot be built without production evidence (FM1)
 *   - No hypothesis accepted without production-grade evidence (PV1)
 *   - No hypothesis accepted with undistinguished alternatives (U1)
 *   - No termination without blind-spot review (M1)
 *   - Model cannot be skipped without production evidence (PV2)
 *   - Every accepted hypothesis has mechanism + counterfactual (H1, H2/FZ1)
 *   - Unobservable counterfactual blocks verification and acceptance (FZ2)
 *   - Evidence log must have direct entry (PW1), model re-run after facts (PW2)
 *   - Interpreted evidence alone cannot drive acceptance
 *
 * Gaps / exclusions:
 *   - Alloy model construction details (solver interaction) not modeled
 *   - User interaction (supervised vs autonomous mode) abstracted
 *   - Specific cause classes in M1 checklist abstracted to a boolean
 */

-- ============================================================
-- Domain enums
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

-- Investigation steps (outer loop)
abstract sig Step {}
one sig S0_Symptom, S1_Model, S2_Hypotheses, S3_Checks,
        S4_Facts, S5_Update, S6_Equivalence, S7_Deepen,
        S8_Terminate extends Step {}

-- Hypothesis status
abstract sig HStatus {}
one sig Active, Rejected, Weakened, Compatible, Undistinguished, Accepted extends HStatus {}

-- Fact reliability
abstract sig Reliability {}
one sig Direct, Inferred, Interpreted, UnreliableSource extends Reliability {}

-- Diagnostic strength of a check
abstract sig DiagStrength {}
one sig Strong, Weak, Irrelevant extends DiagStrength {}

-- F4: task type determines whether production-first ordering applies
abstract sig TaskType {}
one sig Investigate, Fix extends TaskType {}

-- M1: 14 cause classes from the blind-spot checklist (SKILL.md)
-- Each must be explicitly covered (or excluded with reason) before acceptance.
abstract sig CauseClass {}
one sig CC_Concurrency, CC_SharedMutableState, CC_ObjectLifecycle, CC_Caching,
        CC_AsyncBoundaries, CC_ExternalSystem, CC_PartialObservability,
        CC_ConfigFeatureFlags, CC_DataMigration, CC_TenantIsolation,
        CC_AuthState, CC_DeploymentDrift, CC_MultiArtifact, CC_BuildPipeline
  extends CauseClass {}

-- F3: source types with prescribed reliability levels (SKILL.md lines 178-193)
abstract sig SourceType {}
one sig ProductionDB,             -- direct
        RecentProductionLogs,     -- direct  (<7d)
        OldProductionLogs,        -- inferred (>7d)
        LiveAPIResponse,          -- direct
        DeployedConfig,           -- direct
        RepoCode,                 -- interpreted
        LocalGitHistory,          -- interpreted
        PriorReport,              -- interpreted
        SpecDesignDoc,            -- interpreted
        AlloyModelResult,         -- inferred
        UserVerbalDescription,    -- interpreted
        MobileAppCode,            -- unreliable-source
        ThirdPartyDocs,           -- interpreted
        UserReport                -- inferred
  extends SourceType {}

-- F3: the classification function — encodes the source→reliability table
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
-- Core entities
-- ============================================================

sig Hypothesis {
  hasMechanism: one Bool,         -- H1: must have causal chain
  hasCounterfactual: one Bool,    -- H2: must state what falsifies it (elaborated by FZ1/FZ2)
  dynamicDataDependent: one Bool, -- F3 (TC23): does this hypothesis depend on dynamic data?
  var counterfactualObservable: one Bool,  -- FZ2: can the counterfactual be checked with current telemetry?
  var alternativeConsidered: one Bool,  -- M2: at least one alternative mechanism was named
  var counterfactualVerified: one Bool,  -- Termination #5: counterfactual checked and not observed
  -- F3 (TC23): dynamic data verification — three checks from SKILL.md
  var dataCurrentValueVerified: one Bool,    -- (a) current value queried from production
  var dataChangeHistoryVerified: one Bool,   -- (b) audit trail / revision table checked
  var dataTimelineCoverageVerified: one Bool, -- (c) triggering condition covers symptom window
  -- PW3: hypothesis log events (each tracks whether the event was logged)
  var loggedMechanism: one Bool,          -- mechanism-stated event logged
  var loggedCounterfactual: one Bool,     -- counterfactual-stated event logged
  var loggedObservability: one Bool,      -- observability-assessed event logged
  var loggedAlternative: one Bool,        -- alternative-considered event logged
  var status: one HStatus
}

sig Fact {
  source: one SourceType,         -- F3: where this evidence came from
  reliability: one Reliability,   -- derived from source via F3 table
  var integrated: one Bool,       -- has it been added to the model?
  var stale: one Bool             -- F5: has the system changed since collection?
}

-- F3 constraint: reliability must match the source classification table
fact F3_ReliabilityMatchesSource {
  all f: Fact | f.reliability = sourceReliability[f.source]
}

sig Check {
  strength: one DiagStrength,
  -- which hypotheses this check distinguishes
  distinguishes: set Hypothesis
}

-- The investigation itself (singleton)
one sig Investigation {
  taskType: one TaskType,               -- F4: investigate-only or fix
  var currentStep: one Step,
  var modelBuilt: one Bool,
  var causesCovered: set CauseClass,    -- M1: which blind-spot cause classes have been reviewed
  var hasProductionEvidence: one Bool,  -- at least one Direct fact integrated
  var symptomVerified: one Bool,        -- S0-V: symptom confirmed by direct evidence
  var toolingInventoried: one Bool,     -- S0a-T: available tooling assessed
  var evidenceLogHasDirect: one Bool,   -- PW1: evidence log contains >= 1 direct entry
  var modelRerunAfterFacts: one Bool,   -- PW2: model was re-run after fact integration
  var firstS4FactCollected: one Bool,   -- F4: has any fact been integrated at S4?
  var equivalenceChecked: one Bool,     -- PW3: equivalence-checked event logged
  -- TC24: formal model requirement with user-acknowledged skip
  var skipProposed: one Bool,           -- Claude proposed to skip formal modeling
  var skipAcknowledged: one Bool        -- User explicitly accepted the skip
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
  Investigation.skipProposed = False
  Investigation.skipAcknowledged = False
  all h: Hypothesis | h.status = Active and h.counterfactualObservable = False
    and h.alternativeConsidered = False and h.counterfactualVerified = False
    and h.dataCurrentValueVerified = False and h.dataChangeHistoryVerified = False
    and h.dataTimelineCoverageVerified = False
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
    and h.dataCurrentValueVerified' = h.dataCurrentValueVerified
    and h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
    and h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
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
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
}

pred stutter {
  frameHypotheses and frameFacts and frameInvestigation
}

-- ============================================================
-- Step transitions (outer loop)
-- ============================================================

-- Step ordering: each step can only advance to the next
fun nextStep[s: Step]: lone Step {
  s = S0_Symptom     => S1_Model else
  s = S1_Model       => S2_Hypotheses else
  s = S2_Hypotheses  => S3_Checks else
  s = S3_Checks      => S4_Facts else
  s = S4_Facts       => S5_Update else
  s = S5_Update      => S6_Equivalence else
  s = S6_Equivalence => S7_Deepen else
  s = S7_Deepen      => S2_Hypotheses else  -- loop back for deepening
  s = S8_Terminate   => none else
  none
}

pred advanceStep {
  let curr = Investigation.currentStep |
    some nextStep[curr]
    -- S1_Model has dedicated transitions (buildModel / skipModel)
    and curr != S1_Model
    -- S0a-T + S0-V: cannot leave S0 without tooling inventory AND verified symptom
    -- Order: tooling first (Step 0a), then verify symptom using those tools (Step 0b)
    and (curr = S0_Symptom => (Investigation.toolingInventoried = True
                               and Investigation.symptomVerified = True))
    and Investigation.currentStep' = nextStep[curr]
  -- rest unchanged
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  -- PW2: leaving S5 (update) means model was re-run after facts
  (Investigation.currentStep = S5_Update) =>
    Investigation.modelRerunAfterFacts' = True
  else
    Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
  frameFacts
}

-- S0-V: verify symptom against production. Requires integrating a Direct fact
-- while still at S0. This grounds the symptom description before any modeling.
pred verifySymptom[f: Fact] {
  Investigation.currentStep = S0_Symptom
  Investigation.toolingInventoried = True  -- must inventory tools before verifying (Step 0a before 0b)
  f.reliability = Direct
  f.integrated = False
  -- integrate the fact and mark symptom verified
  f.integrated' = True
  Investigation.symptomVerified' = True
  Investigation.hasProductionEvidence' = True  -- Direct fact → production evidence
  Investigation.evidenceLogHasDirect' = True   -- PW1: direct entry in evidence log
  -- rest unchanged
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  f.stale' = False  -- freshly collected
  all f2: Fact - f | f2.integrated' = f2.integrated and f2.stale' = f2.stale
  frameHypotheses
}

-- F5: system change (deploy/migration) stales all integrated Direct facts.
-- Can happen at any step — production doesn't pause for investigations.
pred systemChange {
  -- at least one integrated direct fact exists to stale
  some f: Fact | f.integrated = True and f.reliability = Direct and f.stale = False
  -- stale all integrated direct facts
  all f: Fact | (f.integrated = True and f.reliability = Direct) =>
    f.stale' = True
  else
    f.stale' = f.stale
  -- integrated status unchanged
  all f: Fact | f.integrated' = f.integrated
  frameHypotheses
  frameInvestigation
}

-- F5: re-verify a stale fact (re-run the same query, get fresh result)
pred reverifyFact[f: Fact] {
  f.stale = True
  f.integrated = True
  f.stale' = False
  -- other facts unchanged
  all f2: Fact - f | f2.integrated' = f2.integrated and f2.stale' = f2.stale
  frameHypotheses
  frameInvestigation
}

-- S0a-T: inventory available tooling and observability at S0.
-- Must happen before leaving S0. Establishes what direct evidence is collectible.
pred inventoryTooling {
  Investigation.currentStep = S0_Symptom
  Investigation.toolingInventoried = False
  Investigation.toolingInventoried' = True
  -- rest unchanged
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
  frameFacts
}

-- Special: skip model (PV2 — only if production evidence already exists)
pred skipModel {
  Investigation.currentStep = S1_Model
  Investigation.hasProductionEvidence = True  -- PV2 gate
  Investigation.currentStep' = S2_Hypotheses
  Investigation.modelBuilt' = False
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
  frameFacts
}

-- Build the model at step 1
-- FM1: ground before modeling — production evidence must exist before building
pred buildModel {
  Investigation.currentStep = S1_Model
  Investigation.hasProductionEvidence = True  -- FM1 gate
  Investigation.currentStep' = S2_Hypotheses
  Investigation.modelBuilt' = True
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
  frameFacts
}

-- Equivalence check leads to termination attempt (instead of deepening)
pred tryTerminate {
  Investigation.currentStep = S6_Equivalence
  -- no undistinguished hypotheses remain
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
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
  frameFacts
}

-- ============================================================
-- Fact integration
-- ============================================================

pred integrateFact[f: Fact] {
  Investigation.currentStep = S4_Facts
  f.integrated = False
  -- TC19: production-first — first S4 fact must be production-grade for ALL tasks.
  -- Direct or Inferred, never Interpreted or UnreliableSource.
  (Investigation.firstS4FactCollected = False)
    => f.reliability in (Direct + Inferred)
  -- F4: Fix tasks are stricter — first fact must be Direct specifically
  -- (production observation of current behavior, not old logs)
  (Investigation.taskType = Fix and Investigation.firstS4FactCollected = False)
    => f.reliability = Direct
  f.integrated' = True
  -- If this is a direct fact, mark production evidence + evidence log
  (f.reliability = Direct) => (
    Investigation.hasProductionEvidence' = True
    and Investigation.evidenceLogHasDirect' = True   -- PW1
  ) else (
    Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
    and Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  )
  -- PW2: new fact integrated → model is stale until re-run at S5
  Investigation.modelRerunAfterFacts' = False
  -- F4: mark that at least one fact has been collected at S4
  Investigation.firstS4FactCollected' = True
  -- other facts unchanged; freshly collected fact is not stale
  f.stale' = False
  all f2: Fact - f | f2.integrated' = f2.integrated and f2.stale' = f2.stale
  -- step and model unchanged
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
}

-- ============================================================
-- Hypothesis status updates
-- ============================================================

pred frameOtherHypotheses[h: Hypothesis] {
  all h2: Hypothesis - h |
    h2.status' = h2.status
    and h2.counterfactualObservable' = h2.counterfactualObservable
    and h2.alternativeConsidered' = h2.alternativeConsidered
    and h2.counterfactualVerified' = h2.counterfactualVerified
    and h2.dataCurrentValueVerified' = h2.dataCurrentValueVerified
    and h2.dataChangeHistoryVerified' = h2.dataChangeHistoryVerified
    and h2.dataTimelineCoverageVerified' = h2.dataTimelineCoverageVerified
    and h2.loggedMechanism' = h2.loggedMechanism
    and h2.loggedCounterfactual' = h2.loggedCounterfactual
    and h2.loggedObservability' = h2.loggedObservability
    and h2.loggedAlternative' = h2.loggedAlternative
}

pred preserveHypFlags[h: Hypothesis] {
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
}

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
  -- there exists another compatible hypothesis (diagnostic equivalence)
  some h2: Hypothesis - h | h2.status = Compatible
  h.status' = Undistinguished
  preserveHypFlags[h]
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- M2: investigator names at least one alternative mechanism for a hypothesis.
-- Can happen at S6 (equivalence) or S8 (termination) — the two points where
-- the protocol assesses whether the hypothesis space is complete.
pred considerAlternative[h: Hypothesis] {
  Investigation.currentStep in (S6_Equivalence + S8_Terminate)
  h.alternativeConsidered = False
  h.alternativeConsidered' = True
  h.loggedAlternative' = True  -- PW3: log the alternative
  h.counterfactualObservable' = h.counterfactualObservable
  h.counterfactualVerified' = h.counterfactualVerified
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- PW3: log mechanism for a hypothesis (happens at hypothesis generation, Step 2)
pred logMechanism[h: Hypothesis] {
  Investigation.currentStep = S2_Hypotheses
  h.hasMechanism = True
  h.loggedMechanism = False
  h.loggedMechanism' = True
  -- rest unchanged
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- PW3: log counterfactual for a hypothesis (happens at hypothesis generation, Step 2)
pred logCounterfactual[h: Hypothesis] {
  Investigation.currentStep = S2_Hypotheses
  h.hasCounterfactual = True
  h.loggedCounterfactual = False
  h.loggedCounterfactual' = True
  -- rest unchanged
  h.loggedMechanism' = h.loggedMechanism
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- PW3: log equivalence check (happens at Step 6)
pred logEquivalenceCheck {
  Investigation.currentStep = S6_Equivalence
  Investigation.equivalenceChecked = False
  Investigation.equivalenceChecked' = True
  -- rest unchanged
  Investigation.currentStep' = Investigation.currentStep
  Investigation.modelBuilt' = Investigation.modelBuilt
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  -- NOTE: equivalenceChecked' already set to True above, do NOT preserve here
  frameHypotheses
  frameFacts
}

-- TC24: propose to skip formal modeling (Claude proposes, user hasn't decided yet)
pred proposeModelSkip {
  Investigation.currentStep = S1_Model
  Investigation.skipProposed = False
  Investigation.skipProposed' = True
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  -- rest unchanged
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
  frameHypotheses
  frameFacts
}

-- TC24: user acknowledges model skip (only valid after Claude proposed)
pred acknowledgeModelSkip {
  Investigation.currentStep = S1_Model
  Investigation.skipProposed = True    -- must have been proposed first
  Investigation.skipAcknowledged = False
  Investigation.skipAcknowledged' = True
  -- advance past model step without building
  Investigation.currentStep' = S2_Hypotheses
  Investigation.modelBuilt' = False
  Investigation.skipProposed' = Investigation.skipProposed
  -- rest unchanged
  Investigation.causesCovered' = Investigation.causesCovered
  Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
  Investigation.symptomVerified' = Investigation.symptomVerified
  Investigation.toolingInventoried' = Investigation.toolingInventoried
  Investigation.evidenceLogHasDirect' = Investigation.evidenceLogHasDirect
  Investigation.modelRerunAfterFacts' = Investigation.modelRerunAfterFacts
  Investigation.firstS4FactCollected' = Investigation.firstS4FactCollected
  Investigation.equivalenceChecked' = Investigation.equivalenceChecked
  frameHypotheses
  frameFacts
}

-- FZ2: assess whether a hypothesis's counterfactual can be checked with
-- current telemetry. This can happen during model build, fact collection,
-- model update, or deepening — any point where observability is evaluated.
-- Setting this to True means "yes, we have the telemetry to check this."
-- If it stays False, verifyCounterfactual is blocked → acceptance is blocked.
pred assessObservability[h: Hypothesis] {
  Investigation.currentStep in (S2_Hypotheses + S3_Checks + S4_Facts + S5_Update + S6_Equivalence + S7_Deepen)
  h.hasCounterfactual = True
  h.counterfactualObservable = False
  h.counterfactualObservable' = True
  h.loggedObservability' = True  -- PW3: log the assessment
  -- rest unchanged
  h.alternativeConsidered' = h.alternativeConsidered
  h.counterfactualVerified' = h.counterfactualVerified
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedAlternative' = h.loggedAlternative
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- Termination condition 5: verify that a hypothesis's counterfactual is not
-- observed in production. Requires: (a) the hypothesis has a counterfactual,
-- (b) production evidence exists (direct fact), (c) we're at the fact/update stage.
-- This is the bridge between "I can state what falsifies this" and "I checked
-- and the falsifying condition doesn't hold."
pred verifyCounterfactual[h: Hypothesis] {
  Investigation.currentStep in (S4_Facts + S5_Update)
  h.hasCounterfactual = True
  h.counterfactualObservable = True  -- FZ2: can only verify if observable
  h.counterfactualVerified = False
  -- requires production evidence to ground the verification
  Investigation.hasProductionEvidence = True
  h.counterfactualVerified' = True
  h.counterfactualObservable' = h.counterfactualObservable
  h.alternativeConsidered' = h.alternativeConsidered
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
  h.loggedMechanism' = h.loggedMechanism
  h.loggedCounterfactual' = h.loggedCounterfactual
  h.loggedObservability' = h.loggedObservability
  h.loggedAlternative' = h.loggedAlternative
  h.status' = h.status
  frameOtherHypotheses[h]
  frameFacts
  frameInvestigation
}

-- F3 (TC23): verify dynamic data inputs for a hypothesis.
-- When a hypothesis depends on dynamic data (DB templates, config, feature flags),
-- the investigator must verify: (a) current value, (b) change history, (c) timeline coverage.
-- Can happen at S4 (facts) or S5 (update) — where evidence is being collected and integrated.
-- Each sub-check can be done independently (separate verifyDynamicData calls).
pred verifyDynamicDataCurrentValue[h: Hypothesis] {
  Investigation.currentStep in (S4_Facts + S5_Update)
  h.dynamicDataDependent = True
  h.dataCurrentValueVerified = False
  Investigation.hasProductionEvidence = True  -- needs production data to verify
  h.dataCurrentValueVerified' = True
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
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

pred verifyDynamicDataChangeHistory[h: Hypothesis] {
  Investigation.currentStep in (S4_Facts + S5_Update)
  h.dynamicDataDependent = True
  h.dataChangeHistoryVerified = False
  h.dataChangeHistoryVerified' = True
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataTimelineCoverageVerified' = h.dataTimelineCoverageVerified
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

pred verifyDynamicDataTimeline[h: Hypothesis] {
  Investigation.currentStep in (S4_Facts + S5_Update)
  h.dynamicDataDependent = True
  h.dataTimelineCoverageVerified = False
  h.dataTimelineCoverageVerified' = True
  h.dataCurrentValueVerified' = h.dataCurrentValueVerified
  h.dataChangeHistoryVerified' = h.dataChangeHistoryVerified
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

-- M1: cover a single cause class (replaces the old boolean blindSpotReviewed).
-- Each class must be individually addressed — can happen at S6 or S8.
-- This forces the investigator to review all 14 classes, not just flip a flag.
pred coverCauseClass[c: CauseClass] {
  Investigation.currentStep = S6_Equivalence or Investigation.currentStep = S8_Terminate
  c not in Investigation.causesCovered  -- only cover each class once
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
  Investigation.skipProposed' = Investigation.skipProposed
  Investigation.skipAcknowledged' = Investigation.skipAcknowledged
  frameHypotheses
  frameFacts
}

-- Accept: the critical transition with all gates
pred acceptHypothesis[h: Hypothesis] {
  Investigation.currentStep = S8_Terminate

  -- H1: mechanism required
  h.hasMechanism = True

  -- H2 (FZ1): counterfactual required
  h.hasCounterfactual = True

  -- FZ2 (TC4): counterfactual is observable with current telemetry
  h.counterfactualObservable = True

  -- Termination #5: counterfactual was checked and not observed
  h.counterfactualVerified = True

  -- M2: at least one alternative was considered
  h.alternativeConsidered = True

  -- U1: no compatible or undistinguished alternatives
  h.status = Compatible
  no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active)

  -- M1: all 14 cause classes reviewed
  CauseClass = Investigation.causesCovered

  -- PV1: production-grade evidence exists
  Investigation.hasProductionEvidence = True

  -- PW1: evidence log has at least one direct entry
  Investigation.evidenceLogHasDirect = True

  -- PW2: model was re-run after facts (if model was built)
  (Investigation.modelBuilt = True) => Investigation.modelRerunAfterFacts = True

  -- F5: no stale direct evidence
  no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True

  -- PW3: hypothesis log has required entries
  h.loggedMechanism = True
  h.loggedCounterfactual = True
  h.loggedObservability = True
  h.loggedAlternative = True
  Investigation.equivalenceChecked = True

  -- TC23: F3 data-input verification — if hypothesis depends on dynamic data,
  -- all three checks must be verified (current value, change history, timeline coverage)
  (h.dynamicDataDependent = True) => (
    h.dataCurrentValueVerified = True
    and h.dataChangeHistoryVerified = True
    and h.dataTimelineCoverageVerified = True
  )

  -- TC24: formal model exists OR user acknowledged skip
  (Investigation.modelBuilt = True) or (Investigation.skipAcknowledged = True)
  -- TC24 corollary: skip requires proposal (can't skip silently)
  (Investigation.skipAcknowledged = True) => (Investigation.skipProposed = True)

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
    or (some f: Fact | verifySymptom[f])
    or inventoryTooling
    or systemChange
    or (some f: Fact | reverifyFact[f])
    or buildModel
    or skipModel
    or proposeModelSkip
    or acknowledgeModelSkip
    or tryTerminate
    or (some c: CauseClass | coverCauseClass[c])
    or (some h: Hypothesis | considerAlternative[h])
    or (some h: Hypothesis | logMechanism[h])
    or (some h: Hypothesis | logCounterfactual[h])
    or logEquivalenceCheck
    or (some h: Hypothesis | assessObservability[h])
    or (some h: Hypothesis | verifyCounterfactual[h])
    or (some h: Hypothesis | verifyDynamicDataCurrentValue[h])
    or (some h: Hypothesis | verifyDynamicDataChangeHistory[h])
    or (some h: Hypothesis | verifyDynamicDataTimeline[h])
    or (some f: Fact | integrateFact[f])
    or (some h: Hypothesis | rejectHypothesis[h])
    or (some h: Hypothesis | weakenHypothesis[h])
    or (some h: Hypothesis | markCompatible[h])
    or (some h: Hypothesis | markUndistinguished[h])
    or (some h: Hypothesis | acceptHypothesis[h])
  )
}

-- ============================================================
-- SAFETY ASSERTIONS
-- ============================================================

-- S0-V: Cannot leave Step 0 without verifying symptom with direct evidence
assert S0V_SymptomVerificationRequired {
  always (
    (Investigation.currentStep = S0_Symptom and Investigation.currentStep' = S1_Model)
    => Investigation.symptomVerified = True
  )
}
check S0V_SymptomVerificationRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- S0a-T: Cannot leave S0 without tooling inventory
assert S0aT_ToolingInventoryRequired {
  always (
    (Investigation.currentStep = S0_Symptom and Investigation.currentStep' = S1_Model)
    => Investigation.toolingInventoried = True
  )
}
check S0aT_ToolingInventoryRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- FM1: Cannot build the model without production evidence (ground before modeling)
assert FM1_GroundBeforeModeling {
  always (
    (Investigation.currentStep = S1_Model and Investigation.modelBuilt' = True)
    => Investigation.hasProductionEvidence = True
  )
}
check FM1_GroundBeforeModeling for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- PV1: No hypothesis accepted without production evidence
assert PV1_ProductionEvidenceRequired {
  always (all h: Hypothesis | h.status' = Accepted =>
    Investigation.hasProductionEvidence = True)
}
check PV1_ProductionEvidenceRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- PV2: Model skip requires production evidence
-- A "skip" is specifically: moving past S1 without building the model.
-- buildModel sets modelBuilt'=True; skipModel sets modelBuilt'=False.
-- advanceStep from S1 also preserves modelBuilt (could be False), so we
-- must prevent advanceStep from S1 entirely — only buildModel or skipModel allowed.
assert PV2_ModelSkipRequiresEvidence {
  always (
    (Investigation.currentStep = S1_Model
     and Investigation.currentStep' = S2_Hypotheses
     and Investigation.modelBuilt' = False)
    =>
    Investigation.hasProductionEvidence = True
  )
}
check PV2_ModelSkipRequiresEvidence for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- U1: No acceptance while undistinguished alternatives exist
assert U1_NoAcceptanceWithAlternatives {
  always (all h: Hypothesis | h.status' = Accepted =>
    no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active))
}
check U1_NoAcceptanceWithAlternatives for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- H1: Accepted hypothesis must have mechanism
assert H1_MechanismRequired {
  always (all h: Hypothesis | h.status' = Accepted => h.hasMechanism = True)
}
check H1_MechanismRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- H2/FZ1: Accepted hypothesis must have counterfactual
-- SKILL.md calls this H2 (Hypothesis rules section); FZ1 elaborates the
-- counterfactual requirement, FZ2 adds the observable-vs-theoretical distinction.
assert H2_FZ1_CounterfactualRequired {
  always (all h: Hypothesis | h.status' = Accepted => h.hasCounterfactual = True)
}
check H2_FZ1_CounterfactualRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- M1: No acceptance without all 14 cause classes reviewed
assert M1_AllCauseClassesCovered {
  always (all h: Hypothesis | h.status' = Accepted =>
    CauseClass = Investigation.causesCovered)
}
check M1_AllCauseClassesCovered for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

-- M2: No acceptance without considering an alternative
assert M2_AlternativeRequired {
  always (all h: Hypothesis | h.status' = Accepted => h.alternativeConsidered = True)
}
check M2_AlternativeRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- PW1: evidence log must have at least one direct entry before acceptance
assert PW1_EvidenceLogHasDirect {
  always (all h: Hypothesis | h.status' = Accepted =>
    Investigation.evidenceLogHasDirect = True)
}
check PW1_EvidenceLogHasDirect for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- PW2: if model was built, it must have been re-run after fact integration
assert PW2_ModelRerunAfterFacts {
  always (all h: Hypothesis | h.status' = Accepted =>
    (Investigation.modelBuilt = True => Investigation.modelRerunAfterFacts = True))
}
check PW2_ModelRerunAfterFacts for 4 but 3 Hypothesis, 3 Fact, 4 Check, 12 steps

-- PW3: hypothesis log must have all required entries before acceptance
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

-- F5: no stale direct evidence at acceptance
assert F5_NoStaleEvidenceAtAcceptance {
  always (all h: Hypothesis | h.status' = Accepted =>
    no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True)
}
check F5_NoStaleEvidenceAtAcceptance for 4 but 2 Hypothesis, 2 Fact, 1 Check, 14 steps

-- F4: in Fix tasks, the first fact collected at S4 must be Direct (production)
assert F4_FixTaskProductionFirst {
  always (
    (Investigation.taskType = Fix
     and Investigation.currentStep = S4_Facts
     and Investigation.firstS4FactCollected = False
     and Investigation.firstS4FactCollected' = True)
    =>
    (some f: Fact | f.integrated = False and f.integrated' = True and f.reliability = Direct)
  )
}
check F4_FixTaskProductionFirst for 4 but 2 Hypothesis, 3 Fact, 2 Check, 12 steps

-- TC19: first S4 fact must be production-grade (Direct or Inferred) for all tasks
assert TC19_ProductionFirstOrdering {
  always (
    (Investigation.currentStep = S4_Facts
     and Investigation.firstS4FactCollected = False
     and Investigation.firstS4FactCollected' = True)
    =>
    (some f: Fact | f.integrated = False and f.integrated' = True
                    and f.reliability in (Direct + Inferred))
  )
}
check TC19_ProductionFirstOrdering for 4 but 2 Hypothesis, 3 Fact, 2 Check, 12 steps

-- TC19 consequence: Investigate tasks can no longer start with Interpreted evidence.
-- (Before TC19, F4 only constrained Fix tasks. Now all tasks require production-first.)
-- This run should find a trace where Interpreted evidence is integrated AFTER
-- the first production-grade fact.
run InvestigateInterpretedAfterFirst {
  Investigation.taskType = Investigate
  and some f: Fact | f.source = RepoCode
    and eventually (f.integrated = True)
} for 4 but exactly 2 Hypothesis, exactly 2 Fact, exactly 1 Check, 16 steps

-- F3: reliability is always consistent with source type
assert F3_ReliabilityConsistent {
  always (all f: Fact | f.reliability = sourceReliability[f.source])
}
check F3_ReliabilityConsistent for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- F3 consequence: integrating a repo-code fact cannot set hasProductionEvidence
-- (the flag only changes to True when a Direct fact is integrated)
assert F3_RepoCodeCantSetProductionEvidence {
  always (
    (some f: Fact | f.source = RepoCode and f.integrated = False and f.integrated' = True)
    =>
    (Investigation.hasProductionEvidence' = Investigation.hasProductionEvidence
     or Investigation.hasProductionEvidence = True)  -- either unchanged or was already true
  )
}
check F3_RepoCodeCantSetProductionEvidence for 4 but 2 Hypothesis, 3 Fact, 2 Check, 10 steps

-- FZ2: counterfactual can only be verified if it's observable
-- (unobservable counterfactual = blind spot, not confirmation)
assert FZ2_ObservabilityRequired {
  always (all h: Hypothesis | h.counterfactualVerified' = True =>
    h.counterfactualObservable = True)
}
check FZ2_ObservabilityRequired for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- FZ2 consequence: unobservable counterfactual blocks acceptance
assert FZ2_UnobservableBlocksAcceptance {
  always (all h: Hypothesis | h.status' = Accepted =>
    h.counterfactualObservable = True)
}
check FZ2_UnobservableBlocksAcceptance for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- Termination #5: counterfactual must be verified (not just stated)
assert CounterfactualMustBeVerified {
  always (all h: Hypothesis | h.status' = Accepted => h.counterfactualVerified = True)
}
check CounterfactualMustBeVerified for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- Combined: the full acceptance gate (all 24 termination conditions from SKILL.md)
-- TC19 (production-first) is enforced structurally in integrateFact.
-- TC20-22 (F1, transitions, F4) are enforced structurally in other predicates.
assert FullAcceptanceGate {
  always (all h: Hypothesis | h.status' = Accepted => (
    -- Protocol rules (TC1-TC9)
    h.hasMechanism = True                                                      -- TC2/H1
    and h.hasCounterfactual = True                                              -- TC3/H2
    and h.counterfactualObservable = True                                       -- TC4/FZ2
    and h.counterfactualVerified = True                                         -- TC5
    and h.alternativeConsidered = True                                          -- TC7/M2
    and CauseClass = Investigation.causesCovered                                -- TC8/M1
    and Investigation.hasProductionEvidence = True                              -- TC9/PV1
    and no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active)  -- TC1+TC6+TC18
    -- Evidence quality (TC10)
    and no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True  -- TC10/F5
    -- Proof of work (TC11-TC17)
    and Investigation.evidenceLogHasDirect = True                               -- TC11/PW1
    and (Investigation.modelBuilt = True => Investigation.modelRerunAfterFacts = True)  -- TC12/PW2
    and h.loggedMechanism = True                                                -- TC13/PW3
    and h.loggedCounterfactual = True                                           -- TC14/PW3
    and h.loggedObservability = True                                            -- TC15/PW3
    and h.loggedAlternative = True                                              -- TC16/PW3
    and Investigation.equivalenceChecked = True                                 -- TC17/PW3
    -- TC23: F3 data-input verification (if dynamic data dependent)
    and ((h.dynamicDataDependent = True) => (
      h.dataCurrentValueVerified = True
      and h.dataChangeHistoryVerified = True
      and h.dataTimelineCoverageVerified = True
    ))
    -- TC24: formal model exists OR user-acknowledged skip
    and (Investigation.modelBuilt = True or Investigation.skipAcknowledged = True)
    -- TC24 corollary: skip requires proposal (no silent skip)
    and (Investigation.skipAcknowledged = True => Investigation.skipProposed = True)
  ))
}
check FullAcceptanceGate for 4 but 2 Hypothesis, 2 Fact, 2 Check, 14 steps

-- TC23: F3 data-input verification — if hypothesis depends on dynamic data,
-- all three checks must be completed before acceptance
assert TC23_DynamicDataVerified {
  always (all h: Hypothesis | h.status' = Accepted =>
    ((h.dynamicDataDependent = True) => (
      h.dataCurrentValueVerified = True
      and h.dataChangeHistoryVerified = True
      and h.dataTimelineCoverageVerified = True
    )))
}
check TC23_DynamicDataVerified for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

-- TC23 consequence: a non-dynamic-data hypothesis can be accepted even with
-- data verification flags at False (F3 gate is vacuously satisfied)
run TC23_NoDynamicDataCanAccept {
  some h: Hypothesis |
    h.dynamicDataDependent = False
    and h.dataCurrentValueVerified = False
    and eventually (h.status = Accepted)
} for 4 but exactly 2 Hypothesis, exactly 1 Fact, 1 Check, 28 steps

-- TC24: formal model or acknowledged skip required for acceptance
assert TC24_FormalModelOrSkip {
  always (all h: Hypothesis | h.status' = Accepted =>
    (Investigation.modelBuilt = True or Investigation.skipAcknowledged = True))
}
check TC24_FormalModelOrSkip for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

-- TC24 corollary: skip without proposal is impossible
assert TC24_NoSilentSkip {
  always (all h: Hypothesis | h.status' = Accepted =>
    (Investigation.skipAcknowledged = True => Investigation.skipProposed = True))
}
check TC24_NoSilentSkip for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps

-- F1/PV1 combined: interpreted-only evidence cannot lead to acceptance
-- (if no Direct fact is integrated, hasProductionEvidence stays False)
assert InterpretedAloneCantAccept {
  always (
    (all f: Fact | f.integrated = True => f.reliability in (Interpreted + UnreliableSource))
    =>
    (no h: Hypothesis | h.status = Accepted)
  )
}
check InterpretedAloneCantAccept for 4 but 3 Hypothesis, 3 Fact, 4 Check, 10 steps

-- Step ordering: can't reach S8_Terminate without passing through S4_Facts
assert MustCollectFactsBeforeTermination {
  always (Investigation.currentStep' = S8_Terminate =>
    once Investigation.currentStep = S4_Facts)
}
check MustCollectFactsBeforeTermination for 4 but 2 Hypothesis, 2 Fact, 2 Check, 12 steps

-- ============================================================
-- GAP ASSERTIONS (known boundaries — expected to fail if relaxed)
-- ============================================================

-- Gap: if we removed PV1 (allowed acceptance without production evidence),
-- a hypothesis could be accepted based only on code reading (interpreted facts)
-- This SHOULD find a counterexample — proving PV1 is load-bearing.
assert GapWithoutPV1 {
  always (all h: Hypothesis | h.status' = Accepted => (
    h.hasMechanism = True
    and h.hasCounterfactual = True
    and h.counterfactualObservable = True
    and h.counterfactualVerified = True
    and h.alternativeConsidered = True
    and CauseClass = Investigation.causesCovered
    and no f: Fact | f.integrated = True and f.reliability = Direct and f.stale = True
    and Investigation.evidenceLogHasDirect = True
    and (Investigation.modelBuilt = True => Investigation.modelRerunAfterFacts = True)
    and h.loggedMechanism = True and h.loggedCounterfactual = True
    and h.loggedObservability = True and h.loggedAlternative = True
    and Investigation.equivalenceChecked = True
    -- PV1 REMOVED: no production evidence check
    and no h2: Hypothesis - h | h2.status in (Compatible + Undistinguished + Active)
  ))
}
-- Don't check this — it's a gap assertion documenting that PV1 is necessary.
-- Uncomment to verify it DOES find a counterexample:
-- check GapWithoutPV1 for 4 but 2 Hypothesis, 2 Fact, 2 Check, 10 steps expect 1

-- ============================================================
-- SCENARIOS (liveness — can the protocol actually reach completion?)
-- ============================================================

-- Happy path: symptom → model → hypotheses → checks → facts → update →
--             equivalence → terminate → accept
-- Debug: can we reach Accepted at all?
-- Debug: can we reach S8 + all PW3 flags?
-- NOTE: HappyPath and DeepeningPath are expensive with 14 CauseClass atoms
-- (each requires 14+ coverCauseClass transitions in the trace).
-- Uncomment to verify liveness — takes 10+ minutes.
-- All 22 safety checks pass without these.

-- run HappyPath {
--   Investigation.taskType = Investigate
--   all f: Fact | f.source = ProductionDB
--   all h: Hypothesis | h.hasMechanism = True and h.hasCounterfactual = True
--   eventually (some h: Hypothesis | h.status = Accepted)
-- } for 4 but exactly 1 Hypothesis, exactly 1 Fact, exactly 1 Check, 30 steps

-- run DeepeningPath {
--   all h: Hypothesis | h.hasMechanism = True and h.hasCounterfactual = True
--   all f: Fact | f.source = ProductionDB
--   eventually (Investigation.currentStep = S7_Deepen
--     and eventually (Investigation.currentStep = S2_Hypotheses
--       and eventually (some h: Hypothesis | h.status = Accepted)))
-- } for 4 but exactly 1 Hypothesis, exactly 1 Fact, exactly 1 Check, 40 steps

-- Can we reach a state where all hypotheses are rejected? (dead end)
run AllRejected {
  some f: Fact | f.source = ProductionDB  -- need a Direct fact for S0-V
  eventually (all h: Hypothesis | h.status = Rejected)
} for 4 but exactly 3 Hypothesis, exactly 2 Fact, 2 Check, 14 steps

-- Can we reach termination without ever building the model? (PV2 path)
run TerminateWithoutModel {
  some f: Fact | f.reliability = Direct
  and eventually (Investigation.currentStep = S8_Terminate
    and Investigation.modelBuilt = False)
} for 4 but exactly 2 Hypothesis, exactly 1 Fact, 1 Check, 12 steps

-- Diagnostic equivalence forces deepening (U2 in action)
run EquivalenceForcesDeepening {
  some disj h1, h2: Hypothesis |
    eventually (h1.status = Undistinguished
      and eventually Investigation.currentStep = S7_Deepen)
} for 4 but exactly 2 Hypothesis, exactly 1 Fact, 2 Check, 16 steps
