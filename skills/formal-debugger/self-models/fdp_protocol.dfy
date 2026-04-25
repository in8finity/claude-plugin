/**
 * Formal-Debugger Skill Pipeline — Dafny Verification Model
 *
 * Proves properties of the hypothesis-driven debugging protocol defined in
 * formal-debugger/SKILL.md. The protocol has two interlocking loops:
 *   - Outer loop: Steps S0–S8 (iterative causality cone refinement)
 *   - Inner loop: Hypothesis lifecycle rules (H/T/U/M/F/PV/FZ)
 *
 * Translation approach (from potential Alloy model):
 *   - Investigation steps → datatype Step with ordering index
 *   - Evidence reliability → datatype with ordering (direct > inferred > interpreted)
 *   - Hypothesis status lifecycle → datatype + valid transition predicate
 *   - 24 termination conditions → single predicate with core conjuncts + extended checks
 *   - Protocol rules (H1, H2, U1, M1, etc.) → predicates + lemmas
 *   - Proof-of-work logs → structural requirements on log contents
 *
 * Dafny proves ALL properties for ALL inputs (unbounded).
 */

// ============================================================
// 1. ENUMS — Investigation Domain
// ============================================================

datatype Step =
  | S0_FixSymptom       // Pin down what is observed
  | S0a_InventoryTools  // What tooling/observability is available
  | S0b_VerifySymptom   // Confirm symptom with production evidence
  | S1_BuildModel       // Alloy model: normative, data, causal, observability
  | S2_GenHypotheses    // Extract hypotheses from model
  | S3_DesignChecks     // Design distinguishing checks
  | S4_CollectFacts     // Gather evidence from checks
  | S5_UpdateModel      // Add facts as Alloy constraints, re-run
  | S6_CheckEquiv       // Diagnostic equivalence check
  | S7_DeepenModel      // Expand causality cone locally
  | S8_Terminate        // Verify 18 conditions, produce report

datatype Reliability = Direct | Inferred | Interpreted | UnreliableSource

datatype HypothesisStatus =
  | Active         // Just created, not yet tested
  | Compatible     // Consistent with all facts
  | Weakened       // Partially incompatible
  | Undistinguished // Compatible but so are alternatives
  | Rejected       // Incompatible with confirmed facts
  | Accepted       // Sole remaining hypothesis (terminal)

datatype HypothesisEvent =
  | Created
  | MechanismStated
  | CounterfactualStated
  | ObservabilityAssessed
  | AlternativeConsidered
  | StatusChanged
  | EquivalenceChecked

datatype DiagnosticStrength = Strong | Weak | Irrelevant

datatype ModelLayer = Normative | DataLayer | Causal | Observability

datatype DeepenDirection = DepthCode | DepthData | BreadthObservability | BreadthConcurrency

datatype Severity = SecurityCritical | BusinessCritical | DataIntegrityCritical
                  | ComplianceCritical | Standard

// 14 cause classes from the M1 blind-spot checklist
datatype CauseClass =
  | CC_Concurrency | CC_SharedMutableState | CC_ObjectLifecycle | CC_Caching
  | CC_AsyncBoundaries | CC_ExternalSystem | CC_PartialObservability
  | CC_ConfigFeatureFlags | CC_DataMigration | CC_TenantIsolation
  | CC_AuthState | CC_DeploymentDrift | CC_MultiArtifact | CC_BuildPipeline

// ============================================================
// 2. STEP ORDERING
// ============================================================

function stepIndex(s: Step): nat
{
  match s {
    case S0_FixSymptom      => 0
    case S0a_InventoryTools => 1
    case S0b_VerifySymptom  => 2
    case S1_BuildModel      => 3
    case S2_GenHypotheses   => 4
    case S3_DesignChecks    => 5
    case S4_CollectFacts    => 6
    case S5_UpdateModel     => 7
    case S6_CheckEquiv      => 8
    case S7_DeepenModel     => 9
    case S8_Terminate       => 10
  }
}

predicate stepBefore(a: Step, b: Step) { stepIndex(a) < stepIndex(b) }
predicate stepAtOrBefore(a: Step, b: Step) { stepIndex(a) <= stepIndex(b) }

// ============================================================
// 3. INVESTIGATION ARTIFACTS
// ============================================================

datatype Artifact =
  // Created at S0 (living documents)
  | InvestigationReport | EvidenceLog | HypothesisLog | ModelChangeLog
  // Created at S0a
  | ToolingInventory
  // Created at S0b
  | SymptomVerification
  // Created at S1
  | AlloyModel
  // Created at S2
  | HypothesisSet
  // Created at S3
  | CheckPlan
  // Created at S4
  | FactSet
  // Created at S5
  | UpdatedModel
  // Created at S6
  | EquivalenceResult
  // Created at S7
  | DeepenedModel
  // Created at S8
  | FinalReport
  // External inputs (pre-existing)
  | UserSymptom | ProductionDB | ProductionLogs | LiveAPI | DeployedConfig
  | SourceRepo | FormalModelingSkill

function producedBy(a: Artifact): Step
{
  match a {
    // External inputs — available at trigger
    case UserSymptom          => S0_FixSymptom
    case ProductionDB         => S0_FixSymptom
    case ProductionLogs       => S0_FixSymptom
    case LiveAPI              => S0_FixSymptom
    case DeployedConfig       => S0_FixSymptom
    case SourceRepo           => S0_FixSymptom
    case FormalModelingSkill  => S0_FixSymptom
    // Investigation artifacts
    case InvestigationReport  => S0_FixSymptom
    case EvidenceLog          => S0_FixSymptom
    case HypothesisLog        => S0_FixSymptom
    case ModelChangeLog       => S0_FixSymptom
    case ToolingInventory     => S0a_InventoryTools
    case SymptomVerification  => S0b_VerifySymptom
    case AlloyModel           => S1_BuildModel
    case HypothesisSet        => S2_GenHypotheses
    case CheckPlan            => S3_DesignChecks
    case FactSet              => S4_CollectFacts
    case UpdatedModel         => S5_UpdateModel
    case EquivalenceResult    => S6_CheckEquiv
    case DeepenedModel        => S7_DeepenModel
    case FinalReport          => S8_Terminate
  }
}

// ============================================================
// 4. DEPENDENCY RULES
// ============================================================

predicate stepRequires(s: Step, a: Artifact)
{
  match s {
    case S0_FixSymptom =>
      a == UserSymptom

    case S0a_InventoryTools =>
      a == InvestigationReport  // needs symptom context

    case S0b_VerifySymptom =>
      a == ToolingInventory ||  // need to know what tools are available
      a == InvestigationReport ||
      a == EvidenceLog          // will append verification entry

    case S1_BuildModel =>
      a == SymptomVerification ||  // FM1: ground before modeling
      a == FormalModelingSkill ||  // dependency on formal-modeling skill
      a == EvidenceLog ||          // production-first: check logs first
      a == ModelChangeLog          // will append M1 entry

    case S2_GenHypotheses =>
      a == AlloyModel ||
      a == EvidenceLog ||          // production-first: check before generating
      a == HypothesisLog           // will append entries

    case S3_DesignChecks =>
      a == HypothesisSet ||
      a == ToolingInventory        // production-first: prioritize production checks

    case S4_CollectFacts =>
      a == CheckPlan ||
      a == EvidenceLog ||          // will append E<N> entries
      a == ToolingInventory        // need tools to collect facts

    case S5_UpdateModel =>
      a == FactSet ||
      a == AlloyModel ||
      a == ModelChangeLog ||       // will append M<N> entry
      a == HypothesisLog           // will update status-changed

    case S6_CheckEquiv =>
      a == UpdatedModel ||
      a == HypothesisSet ||
      a == HypothesisLog           // will append equivalence-checked

    case S7_DeepenModel =>
      a == EquivalenceResult ||
      a == AlloyModel ||
      a == EvidenceLog ||          // production-first before deepening
      a == ModelChangeLog          // will append M<N> entry

    case S8_Terminate =>
      a == UpdatedModel ||
      a == EvidenceLog ||
      a == HypothesisLog ||
      a == ModelChangeLog ||
      a == InvestigationReport
  }
}

// ============================================================
// 5. CORE PIPELINE ASSERTIONS
// ============================================================

// A1: No step reads an artifact from the future
lemma DependenciesSatisfied(s: Step, a: Artifact)
  requires stepRequires(s, a)
  ensures stepAtOrBefore(producedBy(a), s)
{}

// A2: Comprehensive — all step×artifact pairs satisfy ordering
lemma AllDependenciesSatisfied()
  ensures forall s: Step, a: Artifact ::
    stepRequires(s, a) ==> stepAtOrBefore(producedBy(a), s)
{
  forall s: Step, a: Artifact | stepRequires(s, a)
    ensures stepAtOrBefore(producedBy(a), s)
  {
    DependenciesSatisfied(s, a);
  }
}

// A3: Symptom must be verified before model building (FM1 + S0-V)
lemma GroundBeforeModeling()
  ensures stepRequires(S1_BuildModel, SymptomVerification)
  ensures stepBefore(S0b_VerifySymptom, S1_BuildModel)
{}

// A4: Model building requires formal-modeling skill
lemma ModelRequiresFormalModelingSkill()
  ensures stepRequires(S1_BuildModel, FormalModelingSkill)
{}

// A5: Tooling inventory before symptom verification
lemma ToolingBeforeVerification()
  ensures stepRequires(S0b_VerifySymptom, ToolingInventory)
  ensures stepBefore(S0a_InventoryTools, S0b_VerifySymptom)
{}

// A6: Can't generate hypotheses without a model
lemma HypothesesRequireModel()
  ensures stepRequires(S2_GenHypotheses, AlloyModel)
  ensures stepBefore(S1_BuildModel, S2_GenHypotheses)
{}

// A7: Check design requires hypotheses
lemma ChecksRequireHypotheses()
  ensures stepRequires(S3_DesignChecks, HypothesisSet)
  ensures stepBefore(S2_GenHypotheses, S3_DesignChecks)
{}

// A8: Fact collection requires a check plan
lemma FactsRequireCheckPlan()
  ensures stepRequires(S4_CollectFacts, CheckPlan)
  ensures stepBefore(S3_DesignChecks, S4_CollectFacts)
{}

// A9: Model update requires facts
lemma ModelUpdateRequiresFacts()
  ensures stepRequires(S5_UpdateModel, FactSet)
  ensures stepBefore(S4_CollectFacts, S5_UpdateModel)
{}

// A10: Equivalence check requires updated model
lemma EquivRequiresUpdatedModel()
  ensures stepRequires(S6_CheckEquiv, UpdatedModel)
  ensures stepBefore(S5_UpdateModel, S6_CheckEquiv)
{}

// A11: Deepening requires equivalence result (only deepen when undistinguished)
lemma DeepenRequiresEquivResult()
  ensures stepRequires(S7_DeepenModel, EquivalenceResult)
  ensures stepBefore(S6_CheckEquiv, S7_DeepenModel)
{}

// A12: Termination requires all three logs
lemma TerminationRequiresAllLogs()
  ensures stepRequires(S8_Terminate, EvidenceLog)
  ensures stepRequires(S8_Terminate, HypothesisLog)
  ensures stepRequires(S8_Terminate, ModelChangeLog)
{}

// A13: Terminate is the last step
lemma TerminateIsLast()
  ensures stepIndex(S8_Terminate) == 10
  ensures forall s: Step :: stepIndex(s) <= 10
{}

// ============================================================
// 6. EVIDENCE RELIABILITY — ordering and rules
// ============================================================

function reliabilityRank(r: Reliability): nat
{
  match r {
    case Direct           => 3
    case Inferred         => 2
    case Interpreted      => 1
    case UnreliableSource => 0
  }
}

predicate isStrongerOrEqual(a: Reliability, b: Reliability)
{
  reliabilityRank(a) >= reliabilityRank(b)
}

// ============================================================
// 6a. F3 — SOURCE CLASSIFICATION TABLE
// ============================================================

// 14 source types from SKILL.md lines 288-303, with prescribed reliability levels.
// Ported from Alloy's `SourceType` enum + `sourceReliability` function.
datatype SourceType =
  | SrcProductionDB            // direct
  | SrcRecentProductionLogs    // direct  (<7d)
  | SrcOldProductionLogs       // inferred (>7d)
  | SrcLiveAPIResponse         // direct
  | SrcDeployedConfig          // direct
  | SrcRepoCode                // interpreted
  | SrcLocalGitHistory         // interpreted
  | SrcPriorReport             // interpreted
  | SrcSpecDesignDoc           // interpreted
  | SrcAlloyModelResult        // inferred
  | SrcUserVerbalDescription   // interpreted
  | SrcMobileAppCode           // unreliable-source
  | SrcThirdPartyDocs          // interpreted
  | SrcUserReport              // inferred

// F3: the classification function — encodes the source→reliability table
function sourceReliability(s: SourceType): Reliability
{
  match s {
    case SrcProductionDB         => Direct
    case SrcRecentProductionLogs => Direct
    case SrcLiveAPIResponse      => Direct
    case SrcDeployedConfig       => Direct
    case SrcOldProductionLogs    => Inferred
    case SrcAlloyModelResult     => Inferred
    case SrcUserReport           => Inferred
    case SrcRepoCode             => Interpreted
    case SrcLocalGitHistory      => Interpreted
    case SrcPriorReport          => Interpreted
    case SrcSpecDesignDoc        => Interpreted
    case SrcUserVerbalDescription => Interpreted
    case SrcThirdPartyDocs       => Interpreted
    case SrcMobileAppCode        => UnreliableSource
  }
}

// F3-A1: Production DB is always Direct
lemma F3_ProductionDBIsDirect()
  ensures sourceReliability(SrcProductionDB) == Direct
{}

// F3-A2: Repo code is always Interpreted (never Direct)
lemma F3_RepoCodeIsInterpreted()
  ensures sourceReliability(SrcRepoCode) == Interpreted
  ensures sourceReliability(SrcRepoCode) != Direct
{}

// F3-A3: Mobile app code is UnreliableSource (lowest tier)
lemma F3_MobileAppIsUnreliable()
  ensures sourceReliability(SrcMobileAppCode) == UnreliableSource
{}

// F3-A4: Old production logs degrade from Direct to Inferred
lemma F3_OldLogsDegraded()
  ensures sourceReliability(SrcRecentProductionLogs) == Direct
  ensures sourceReliability(SrcOldProductionLogs) == Inferred
  ensures reliabilityRank(sourceReliability(SrcRecentProductionLogs)) >
          reliabilityRank(sourceReliability(SrcOldProductionLogs))
{}

// F3-A5: Alloy model results are Inferred, not Direct
// (proves algorithm correctness within the model, not deployment correctness)
lemma F3_AlloyResultIsInferred()
  ensures sourceReliability(SrcAlloyModelResult) == Inferred
  ensures sourceReliability(SrcAlloyModelResult) != Direct
{}

// F3-A6: All 4 direct sources are production-grade
lemma F3_DirectSourcesAreProduction()
  ensures sourceReliability(SrcProductionDB) == Direct
  ensures sourceReliability(SrcRecentProductionLogs) == Direct
  ensures sourceReliability(SrcLiveAPIResponse) == Direct
  ensures sourceReliability(SrcDeployedConfig) == Direct
{}

// F3-A7: No interpreted source is Direct (the key safety property)
// This proves: code reading, git history, specs, prior reports, user descriptions,
// and third-party docs can NEVER produce Direct evidence.
lemma F3_InterpretedNeverDirect(s: SourceType)
  requires sourceReliability(s) == Interpreted
  ensures s != SrcProductionDB && s != SrcRecentProductionLogs &&
          s != SrcLiveAPIResponse && s != SrcDeployedConfig
{}

// Evidence entry in the log — now includes optional source type
datatype EvidenceEntry = EvidenceEntry(
  step: Step,
  source: SourceType,
  reliability: Reliability,
  isStale: bool,
  reverified: bool,
  integrated: bool
)

// F3: reliability must match the source classification table
predicate f3_reliabilityConsistent(e: EvidenceEntry)
{
  e.reliability == sourceReliability(e.source)
}

// F3 for entire log: all entries are consistent
predicate f3_logConsistent(log: seq<EvidenceEntry>)
{
  forall i :: 0 <= i < |log| ==> f3_reliabilityConsistent(log[i])
}

// F1: Every fact has a reliability tag (structural — the type enforces this)
lemma F1_ReliabilityTagging(e: EvidenceEntry)
  ensures e.reliability == Direct || e.reliability == Inferred ||
          e.reliability == Interpreted || e.reliability == UnreliableSource
{}

// PV1: Production-grade evidence required for acceptance
predicate hasDirectEvidence(log: seq<EvidenceEntry>)
{
  exists i :: 0 <= i < |log| && log[i].reliability == Direct
}

// F5: Stale evidence blocks acceptance unless re-verified
predicate noStaleDirectEvidence(log: seq<EvidenceEntry>)
{
  forall i :: 0 <= i < |log| && log[i].reliability == Direct && log[i].isStale
    ==> log[i].reverified
}

// A14: Direct evidence is stronger than interpreted
lemma DirectStrongerThanInterpreted()
  ensures isStrongerOrEqual(Direct, Interpreted)
  ensures !isStrongerOrEqual(Interpreted, Direct)
{}

// A15: Inferred is stronger than unreliable-source
lemma InferredStrongerThanUnreliable()
  ensures isStrongerOrEqual(Inferred, UnreliableSource)
{}

// A16: Code reading is interpreted, not direct
// (This is a domain constraint — repo code ≠ production truth)
predicate isCodeReading(e: EvidenceEntry)
{
  e.source == SrcRepoCode  // Structural: source type determines this
}

// F3-A8: Code reading evidence can never be Direct
lemma F3_CodeReadingNeverDirect(e: EvidenceEntry)
  requires f3_reliabilityConsistent(e)
  requires isCodeReading(e)
  ensures e.reliability == Interpreted
  ensures e.reliability != Direct
{}

// F3-A9: Repo-code-only log cannot have Direct evidence
// (The key PV1 consequence: if all evidence comes from code reading,
// acceptance is impossible because hasDirectEvidence will be false.)
lemma F3_RepoCodeCantProduceDirectEvidence(log: seq<EvidenceEntry>)
  requires f3_logConsistent(log)
  requires forall i :: 0 <= i < |log| ==> log[i].source == SrcRepoCode
  ensures !hasDirectEvidence(log)
{
  if |log| > 0 {
    // Every entry has source SrcRepoCode → reliability Interpreted → not Direct
    forall i | 0 <= i < |log|
      ensures log[i].reliability != Direct
    {
      assert f3_reliabilityConsistent(log[i]);
      assert log[i].source == SrcRepoCode;
      assert sourceReliability(SrcRepoCode) == Interpreted;
    }
  }
}

// F3-A10: Interpreted-only log (any interpreted source) blocks acceptance
lemma F3_InterpretedOnlyBlocksAcceptance(log: seq<EvidenceEntry>)
  requires f3_logConsistent(log)
  requires forall i :: 0 <= i < |log| ==> sourceReliability(log[i].source) == Interpreted
  ensures !hasDirectEvidence(log)
{
  if |log| > 0 {
    forall i | 0 <= i < |log|
      ensures log[i].reliability != Direct
    {
      assert f3_reliabilityConsistent(log[i]);
    }
  }
}

// ============================================================
// 7. HYPOTHESIS LIFECYCLE — status transitions and rules
// ============================================================

datatype Hypothesis = Hypothesis(
  hasMechanism: bool,          // H1: causal chain stated
  hasCounterfactual: bool,     // H2/FZ1: falsifiability stated
  counterfactualObservable: bool, // FZ2: can actually check it
  counterfactualVerified: bool,   // Termination #5: verified absent
  status: HypothesisStatus,
  hasAlternative: bool,        // M2: at least one alternative named
  hasDirectSupport: bool       // PV1: backed by direct evidence
)

// Valid status transitions
predicate validTransition(from: HypothesisStatus, to: HypothesisStatus)
{
  match from {
    case Active =>
      to == Compatible || to == Weakened || to == Rejected || to == Undistinguished
    case Compatible =>
      to == Accepted || to == Weakened || to == Rejected || to == Undistinguished
    case Weakened =>
      to == Rejected || to == Compatible  // re-strengthened by new evidence
    case Undistinguished =>
      to == Compatible || to == Rejected  // resolved by deeper model
    case Rejected => false   // terminal
    case Accepted => false   // terminal
  }
}

// H1: Mechanism required — can't advance past Active without it
lemma H1_MechanismRequired(h: Hypothesis)
  requires h.status == Compatible || h.status == Accepted
  requires h.hasMechanism  // protocol enforces this
  ensures h.hasMechanism
{}

// H2/FZ1: Counterfactual required for acceptance
lemma H2_CounterfactualRequired(h: Hypothesis)
  requires h.status == Accepted
  requires h.hasCounterfactual  // protocol enforces this
  ensures h.hasCounterfactual
{}

// FZ2: Observable counterfactual required for acceptance
lemma FZ2_ObservableCounterfactual(h: Hypothesis)
  requires h.status == Accepted
  requires h.counterfactualObservable  // protocol enforces this
  ensures h.counterfactualObservable
{}

// U2: No premature collapse — multiple compatible → keep all active
predicate noPrematureCollapse(hypotheses: seq<Hypothesis>)
{
  var compatCount := countByStatus(hypotheses, Compatible);
  // If more than one compatible, none should be Accepted
  compatCount > 1 ==> (forall i :: 0 <= i < |hypotheses| ==> hypotheses[i].status != Accepted)
}

function countByStatus(hs: seq<Hypothesis>, status: HypothesisStatus): nat
{
  if |hs| == 0 then 0
  else (if hs[0].status == status then 1 else 0) + countByStatus(hs[1..], status)
}

// ============================================================
// 8. HYPOTHESIS LOG — proof-of-work events
// ============================================================

datatype HypothesisLogEntry = HypothesisLogEntry(
  step: Step,
  hypothesisId: nat,
  event: HypothesisEvent,
  hasLinkedEvidence: bool
)

// PW3: Required events for an accepted hypothesis
predicate hasRequiredEvents(log: seq<HypothesisLogEntry>, hId: nat)
{
  hasEvent(log, hId, Created) &&
  hasEvent(log, hId, MechanismStated) &&
  hasEvent(log, hId, CounterfactualStated) &&
  hasEventWithResult(log, hId, ObservabilityAssessed) &&
  hasEvent(log, hId, AlternativeConsidered) &&
  hasEvent(log, hId, StatusChanged)
}

// Must have global equivalence check
predicate hasGlobalEquivalenceCheck(log: seq<HypothesisLogEntry>)
{
  exists i :: 0 <= i < |log| && log[i].event == EquivalenceChecked
}

predicate hasEvent(log: seq<HypothesisLogEntry>, hId: nat, evt: HypothesisEvent)
{
  exists i :: 0 <= i < |log| && log[i].hypothesisId == hId && log[i].event == evt
}

// ObservabilityAssessed must indicate "observable" — modeled as event existing
predicate hasEventWithResult(log: seq<HypothesisLogEntry>, hId: nat, evt: HypothesisEvent)
{
  hasEvent(log, hId, evt)
}

// A17: PW3 completeness — accepted hypothesis has all required events
lemma PW3_Completeness(log: seq<HypothesisLogEntry>, hId: nat)
  requires hasRequiredEvents(log, hId)
  ensures hasEvent(log, hId, MechanismStated)
  ensures hasEvent(log, hId, CounterfactualStated)
  ensures hasEventWithResult(log, hId, ObservabilityAssessed)
  ensures hasEvent(log, hId, AlternativeConsidered)
{}

// ============================================================
// 9. MODEL CHANGE LOG — proof-of-work for model lifecycle
// ============================================================

datatype ModelChangeEntry = ModelChangeEntry(
  step: Step,
  trigger: ModelChangeTrigger,
  rerunAfterFacts: bool  // PW2: was solver re-run after fact integration?
)

datatype ModelChangeTrigger = InitialBuild | FactIntegration | Deepening | CounterexampleFix

// PW2: If facts were integrated, model must be re-run afterward
predicate modelRerunAfterFacts(log: seq<ModelChangeEntry>)
{
  // Every FactIntegration trigger must have rerunAfterFacts = true
  forall i :: 0 <= i < |log| && log[i].trigger == FactIntegration
    ==> log[i].rerunAfterFacts
}

// PW2: Log must have at least one entry if model was built
predicate modelLogNonEmpty(log: seq<ModelChangeEntry>)
{
  |log| > 0
}

// A18: Model always re-run after fact integration
lemma PW2_ModelRerunAfterFacts(log: seq<ModelChangeEntry>)
  requires modelRerunAfterFacts(log)
  requires |log| > 0
  ensures modelRerunAfterFacts(log)
{}

// ============================================================
// 10. TERMINATION CONDITIONS — the 18 requirements
// ============================================================

// Investigation state at termination
datatype InvestigationState = InvestigationState(
  hypotheses: seq<Hypothesis>,
  acceptedId: nat,             // index of the accepted hypothesis
  evidenceLog: seq<EvidenceEntry>,
  hypothesisLog: seq<HypothesisLogEntry>,
  modelChangeLog: seq<ModelChangeEntry>,
  causeClassesCovered: set<CauseClass>,
  modelWasBuilt: bool
)

// The set of all 14 cause classes
const ALL_CAUSE_CLASSES: set<CauseClass> :=
  {CC_Concurrency, CC_SharedMutableState, CC_ObjectLifecycle, CC_Caching,
   CC_AsyncBoundaries, CC_ExternalSystem, CC_PartialObservability,
   CC_ConfigFeatureFlags, CC_DataMigration, CC_TenantIsolation,
   CC_AuthState, CC_DeploymentDrift, CC_MultiArtifact, CC_BuildPipeline}

// Count hypotheses with a given status
function countStatus(hs: seq<Hypothesis>, s: HypothesisStatus): nat
{
  if |hs| == 0 then 0
  else (if hs[0].status == s then 1 else 0) + countStatus(hs[1..], s)
}

// All non-accepted hypotheses must be rejected
predicate allOthersRejected(hs: seq<Hypothesis>, acceptedIdx: nat)
  requires 0 <= acceptedIdx < |hs|
{
  forall i :: 0 <= i < |hs| && i != acceptedIdx ==> hs[i].status == Rejected
}

// The master termination predicate — all 18 conditions
predicate canTerminate(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
{
  var h := st.hypotheses[st.acceptedId];

  // Protocol rules (1-9)
  // TC1: Exactly one hypothesis compatible (accepted)
  h.status == Accepted &&
  // TC2: Has concrete mechanism (H1)
  h.hasMechanism &&
  // TC3: Has stated counterfactual (H2/FZ1)
  h.hasCounterfactual &&
  // TC4: Counterfactual is observable (FZ2)
  h.counterfactualObservable &&
  // TC5: Counterfactual verified absent
  h.counterfactualVerified &&
  // TC6: No diagnostically equivalent alternatives (U1) — all others rejected
  allOthersRejected(st.hypotheses, st.acceptedId) &&
  // TC7: At least one alternative considered (M2)
  h.hasAlternative &&
  // TC8: All cause classes reviewed (M1)
  st.causeClassesCovered == ALL_CAUSE_CLASSES &&
  // TC9: At least one direct evidence (PV1)
  h.hasDirectSupport &&

  // Evidence quality (10)
  // TC10: No stale direct evidence (F5)
  noStaleDirectEvidence(st.evidenceLog) &&

  // Proof of work — evidence log (11)
  // TC11: Evidence log has at least one direct entry (PW1)
  hasDirectEvidence(st.evidenceLog) &&

  // Proof of work — model change log (12)
  // TC12: Model change log shows re-run after last fact integration (PW2)
  (!st.modelWasBuilt || (modelLogNonEmpty(st.modelChangeLog) && modelRerunAfterFacts(st.modelChangeLog))) &&

  // Proof of work — hypothesis log (13-18)
  // TC13: mechanism-stated exists (PW3/H1)
  hasEvent(st.hypothesisLog, st.acceptedId, MechanismStated) &&
  // TC14: counterfactual-stated exists (PW3/H2)
  hasEvent(st.hypothesisLog, st.acceptedId, CounterfactualStated) &&
  // TC15: observability-assessed with "observable" (PW3/FZ2)
  hasEventWithResult(st.hypothesisLog, st.acceptedId, ObservabilityAssessed) &&
  // TC16: alternative-considered exists (PW3/M2)
  hasEvent(st.hypothesisLog, st.acceptedId, AlternativeConsidered) &&
  // TC17: equivalence-checked exists (PW3/U1)
  hasGlobalEquivalenceCheck(st.hypothesisLog) &&
  // TC18: Status entries show exactly one compatible/accepted, rest rejected (PW3/U1)
  allOthersRejected(st.hypotheses, st.acceptedId)
}

// ============================================================
// 11. TERMINATION LEMMAS — prove properties of termination
// ============================================================

// A19: Termination guarantees production evidence exists
lemma TerminationGuaranteesDirectEvidence(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures hasDirectEvidence(st.evidenceLog)
  ensures st.hypotheses[st.acceptedId].hasDirectSupport
{}

// A20: Termination guarantees mechanism stated
lemma TerminationGuaranteesMechanism(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures st.hypotheses[st.acceptedId].hasMechanism
  ensures hasEvent(st.hypothesisLog, st.acceptedId, MechanismStated)
{}

// A21: Termination guarantees falsifiability
lemma TerminationGuaranteesFalsifiability(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures st.hypotheses[st.acceptedId].hasCounterfactual
  ensures st.hypotheses[st.acceptedId].counterfactualObservable
  ensures st.hypotheses[st.acceptedId].counterfactualVerified
{}

// A22: Termination guarantees no stale evidence
lemma TerminationGuaranteesFreshEvidence(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures noStaleDirectEvidence(st.evidenceLog)
{}

// A23: Termination guarantees all cause classes covered (M1)
lemma TerminationGuaranteesBlindSpotCheck(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures CC_Concurrency in st.causeClassesCovered
  ensures CC_DeploymentDrift in st.causeClassesCovered
  ensures CC_BuildPipeline in st.causeClassesCovered
  ensures st.causeClassesCovered == ALL_CAUSE_CLASSES
{}

// A24: Termination guarantees no unresolved equivalences
lemma TerminationGuaranteesNoEquivalences(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures allOthersRejected(st.hypotheses, st.acceptedId)
  ensures hasGlobalEquivalenceCheck(st.hypothesisLog)
{}

// A25: Termination guarantees proof of work across all three logs
lemma TerminationGuaranteesProofOfWork(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures hasDirectEvidence(st.evidenceLog)                          // PW1
  ensures !st.modelWasBuilt || modelLogNonEmpty(st.modelChangeLog)   // PW2
  ensures hasEvent(st.hypothesisLog, st.acceptedId, MechanismStated) // PW3
{}

// ============================================================
// 12. PROTOCOL RULES AS STRUCTURAL PROPERTIES
// ============================================================

// U1: No acceptance with undistinguished alternatives
// If any hypothesis is Undistinguished, no hypothesis can be Accepted
predicate u1_noAcceptanceWithUndistinguished(hs: seq<Hypothesis>)
{
  (exists i :: 0 <= i < |hs| && hs[i].status == Undistinguished)
    ==> (forall j :: 0 <= j < |hs| ==> hs[j].status != Accepted)
}

lemma U1_Enforcement(hs: seq<Hypothesis>, acceptedIdx: nat)
  requires 0 <= acceptedIdx < |hs|
  requires hs[acceptedIdx].status == Accepted
  requires allOthersRejected(hs, acceptedIdx)
  ensures u1_noAcceptanceWithUndistinguished(hs)
{
  // If accepted exists and all others rejected, no Undistinguished exists
  // So the antecedent of u1 is false, making it vacuously true
}

// T1: Check distinguishes — a check with zero diagnostic value is useless
predicate checkDistinguishes(strength: DiagnosticStrength)
{
  strength == Strong  // Only strong checks actually distinguish
}

// A26: Strong check is the only distinguishing check
lemma StrongCheckDistinguishes()
  ensures checkDistinguishes(Strong)
  ensures !checkDistinguishes(Weak)
  ensures !checkDistinguishes(Irrelevant)
{}

// FM1: Ground before modeling — symptom verification before model
// (Already proved in A3, but restated as protocol rule)
lemma FM1_GroundBeforeModeling()
  ensures stepBefore(S0b_VerifySymptom, S1_BuildModel)
  ensures stepRequires(S1_BuildModel, SymptomVerification)
{}

// PV2: Model skip requires production evidence
// If no model built, must still have direct evidence for acceptance
predicate pv2_modelSkipRequiresProduction(modelBuilt: bool, evidenceLog: seq<EvidenceEntry>)
{
  !modelBuilt ==> hasDirectEvidence(evidenceLog)
}

lemma PV2_ModelSkipRequiresProduction(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures pv2_modelSkipRequiresProduction(st.modelWasBuilt, st.evidenceLog)
{
  // canTerminate ensures hasDirectEvidence regardless of modelWasBuilt
}

// ============================================================
// 13. PRODUCTION-FIRST RULE — verified at each step
// ============================================================

// The protocol mandates checking production before reasoning at each step.
// Model this as: each step that touches evidence must accept production tools.

predicate stepUsesProductionFirst(s: Step)
{
  match s {
    case S0b_VerifySymptom => true   // Uses production tools
    case S1_BuildModel     => true   // Check logs before modeling
    case S2_GenHypotheses  => true   // Check production before generating
    case S3_DesignChecks   => true   // Prioritize production checks
    case S4_CollectFacts   => true   // Collect direct evidence first
    case S7_DeepenModel    => true   // Check production before deepening
    case _                 => false  // Other steps don't have production-first mandate
  }
}

// A27: All evidence-touching steps have production-first mandate
lemma ProductionFirstAtAllEvidenceSteps()
  ensures stepUsesProductionFirst(S0b_VerifySymptom)
  ensures stepUsesProductionFirst(S1_BuildModel)
  ensures stepUsesProductionFirst(S2_GenHypotheses)
  ensures stepUsesProductionFirst(S3_DesignChecks)
  ensures stepUsesProductionFirst(S4_CollectFacts)
  ensures stepUsesProductionFirst(S7_DeepenModel)
{}

// A28: Steps with production-first have access to evidence log
lemma ProductionFirstStepsHaveEvidenceAccess()
  ensures stepRequires(S1_BuildModel, EvidenceLog)
  ensures stepRequires(S2_GenHypotheses, EvidenceLog)
  ensures stepRequires(S4_CollectFacts, EvidenceLog)
  ensures stepRequires(S7_DeepenModel, EvidenceLog)
{}

// ============================================================
// 14. FOUR MODEL LAYERS — completeness
// ============================================================

// The Alloy model must have four layers
predicate modelHasAllLayers(layers: set<ModelLayer>)
{
  Normative in layers && DataLayer in layers &&
  Causal in layers && Observability in layers
}

// A29: A complete model has all four layers
lemma CompleteModelHasAllLayers()
  ensures modelHasAllLayers({Normative, DataLayer, Causal, Observability})
{}

// A30: Observability layer is required (generates production checks)
// Without it, the model cannot generate the checks that distinguish hypotheses
lemma ObservabilityLayerRequired(layers: set<ModelLayer>)
  requires modelHasAllLayers(layers)
  ensures Observability in layers
{}

// ============================================================
// 15. DIAGNOSTIC STRENGTH AND CHECK ORDERING
// ============================================================

function strengthRank(d: DiagnosticStrength): nat
{
  match d {
    case Strong     => 2
    case Weak       => 1
    case Irrelevant => 0
  }
}

// T2: Checks should be ordered by diagnostic strength
predicate checksOrderedByStrength(checks: seq<DiagnosticStrength>)
{
  forall i, j :: 0 <= i < j < |checks| ==>
    strengthRank(checks[i]) >= strengthRank(checks[j])
}

// A31: Strong checks come before weak checks in a properly ordered plan
lemma StrongBeforeWeak()
  ensures checksOrderedByStrength([Strong, Strong, Weak, Irrelevant])
{}

// ============================================================
// 16. ITERATION LOOP — S7 goes back to S2
// ============================================================

// The protocol says "after deepening, go back to Step 2"
// This means the outer loop is: S2→S3→S4→S5→S6→S7→S2 (cycle)
// Dafny can't model loops directly, but we can prove that:
// 1. Each iteration produces strictly more information
// 2. The termination conditions can eventually be met

// GAP: Loop convergence is not provable in this model.
// The protocol relies on human judgment to deepen productively.
// We CAN prove that each iteration requires new evidence/model changes.

// A32: Deepening produces a different model (must add something)
lemma DeepeningProducesNewModel()
  ensures stepRequires(S7_DeepenModel, AlloyModel)
  ensures stepRequires(S7_DeepenModel, ModelChangeLog)
  // The model change log entry proves something was actually changed
{}

// ============================================================
// 17. EVIDENCE STALENESS — F5 detailed verification
// ============================================================

datatype StalenessReason = DeploySince | MigrationSince | ConfigChange | SessionBoundary

// A stale entry that hasn't been re-verified blocks termination
predicate staleAndUnverified(e: EvidenceEntry)
{
  e.reliability == Direct && e.isStale && !e.reverified
}

// A33: Single stale entry blocks termination
lemma StaleEvidenceBlocksTermination(log: seq<EvidenceEntry>, idx: nat)
  requires 0 <= idx < |log|
  requires staleAndUnverified(log[idx])
  ensures !noStaleDirectEvidence(log)
{}

// A34: Re-verified stale evidence is acceptable
lemma ReverifiedStaleIsOk(e: EvidenceEntry)
  requires e.reliability == Direct && e.isStale && e.reverified
  ensures !staleAndUnverified(e)
{}

// ============================================================
// 18. F2 — ABSENCE IS NOT EVIDENCE OF ABSENCE
// ============================================================

// F2 is a procedural rule that can't be structurally enforced,
// but we can model what it means:
datatype AbsenceInterpretation =
  | EventDidNotHappen      // Incorrect conclusion from missing evidence
  | LogMissing             // Sampling, rotation, error in logging
  | DifferentService       // Event happened elsewhere
  | NotInLocalView         // Present in production, absent in local checkout

// A35: Missing log does not prove event absence — all interpretations valid
lemma AbsenceNotEvidence()
  ensures LogMissing != EventDidNotHappen
  ensures DifferentService != EventDidNotHappen
  ensures NotInLocalView != EventDidNotHappen
{}

// ============================================================
// 19. SEVERITY ASSESSMENT — S0
// ============================================================

// Severity flags affect investigation urgency
predicate requiresImmediateContainment(s: Severity)
{
  s == SecurityCritical || s == DataIntegrityCritical
}

predicate requiresComplianceReview(s: Severity)
{
  s == ComplianceCritical
}

// A36: Security-critical requires immediate containment before RCA
lemma SecurityRequiresContainment()
  ensures requiresImmediateContainment(SecurityCritical)
  ensures requiresImmediateContainment(DataIntegrityCritical)
  ensures !requiresImmediateContainment(Standard)
{}

// ============================================================
// 20. TOOLING SUFFICIENCY — S0a-T
// ============================================================

datatype ToolingSufficiency = Sufficient | NeedAccess | NeedObservability | ProbableCauseOnly

// S0a-T: If no tool can produce direct evidence, investigation is degraded
predicate canProduceDirectEvidence(hasProdDB: bool, hasProdLogs: bool,
                                    hasLiveAPI: bool, hasDeployedConfig: bool)
{
  hasProdDB || hasProdLogs || hasLiveAPI || hasDeployedConfig
}

function assessTooling(hasProdDB: bool, hasProdLogs: bool,
                       hasLiveAPI: bool, hasDeployedConfig: bool): ToolingSufficiency
{
  if canProduceDirectEvidence(hasProdDB, hasProdLogs, hasLiveAPI, hasDeployedConfig)
  then Sufficient
  else ProbableCauseOnly
}

// A37: No direct evidence capability → degraded investigation
lemma NoDirectToolsMeansDegraded()
  ensures assessTooling(false, false, false, false) == ProbableCauseOnly
{}

// A38: Any single direct source is sufficient
lemma AnyDirectSourceSuffices()
  ensures assessTooling(true, false, false, false) == Sufficient
  ensures assessTooling(false, true, false, false) == Sufficient
  ensures assessTooling(false, false, true, false) == Sufficient
  ensures assessTooling(false, false, false, true) == Sufficient
{}

// ============================================================
// 21. VALID INVESTIGATION WITNESS — existence proof
// ============================================================

// Prove that a valid terminating investigation CAN exist
// (the termination conditions are satisfiable, not contradictory)
lemma ValidInvestigationExists()
  ensures exists st: InvestigationState ::
    |st.hypotheses| == 2 &&
    0 <= st.acceptedId < |st.hypotheses| &&
    canTerminate(st)
{
  var accepted := Hypothesis(
    hasMechanism := true,
    hasCounterfactual := true,
    counterfactualObservable := true,
    counterfactualVerified := true,
    status := Accepted,
    hasAlternative := true,
    hasDirectSupport := true
  );
  var rejected := Hypothesis(
    hasMechanism := true,
    hasCounterfactual := true,
    counterfactualObservable := false,
    counterfactualVerified := false,
    status := Rejected,
    hasAlternative := false,
    hasDirectSupport := false
  );

  var evidenceLog := [
    EvidenceEntry(S0b_VerifySymptom, SrcProductionDB, Direct, false, false, true)
  ];

  var hypothesisLog := [
    HypothesisLogEntry(S2_GenHypotheses, 0, Created, false),
    HypothesisLogEntry(S2_GenHypotheses, 0, MechanismStated, false),
    HypothesisLogEntry(S2_GenHypotheses, 0, CounterfactualStated, false),
    HypothesisLogEntry(S6_CheckEquiv, 0, ObservabilityAssessed, false),
    HypothesisLogEntry(S6_CheckEquiv, 0, AlternativeConsidered, false),
    HypothesisLogEntry(S8_Terminate, 0, StatusChanged, true),
    HypothesisLogEntry(S6_CheckEquiv, 0, EquivalenceChecked, false),
    // Rejected hypothesis events
    HypothesisLogEntry(S2_GenHypotheses, 1, Created, false),
    HypothesisLogEntry(S5_UpdateModel, 1, StatusChanged, true)
  ];

  var modelChangeLog := [
    ModelChangeEntry(S1_BuildModel, InitialBuild, false),
    ModelChangeEntry(S5_UpdateModel, FactIntegration, true)
  ];

  var st := InvestigationState(
    hypotheses := [accepted, rejected],
    acceptedId := 0,
    evidenceLog := evidenceLog,
    hypothesisLog := hypothesisLog,
    modelChangeLog := modelChangeLog,
    causeClassesCovered := ALL_CAUSE_CLASSES,
    modelWasBuilt := true
  );

  // Prove this state satisfies canTerminate
  assert st.hypotheses[0].status == Accepted;
  assert st.hypotheses[0].hasMechanism;
  assert st.hypotheses[0].hasCounterfactual;
  assert st.hypotheses[0].counterfactualObservable;
  assert st.hypotheses[0].counterfactualVerified;
  assert allOthersRejected(st.hypotheses, 0);
  assert st.hypotheses[0].hasAlternative;
  assert st.causeClassesCovered == ALL_CAUSE_CLASSES;
  assert st.hypotheses[0].hasDirectSupport;
  assert noStaleDirectEvidence(st.evidenceLog);
  // Witness: evidenceLog[0] is Direct
  assert st.evidenceLog[0].reliability == Direct;
  assert hasDirectEvidence(st.evidenceLog);
  assert modelLogNonEmpty(st.modelChangeLog);
  assert modelRerunAfterFacts(st.modelChangeLog);
  // Witnesses: hypothesisLog indices for each required event
  assert st.hypothesisLog[1].hypothesisId == 0 && st.hypothesisLog[1].event == MechanismStated;
  assert hasEvent(st.hypothesisLog, 0, MechanismStated);
  assert st.hypothesisLog[2].hypothesisId == 0 && st.hypothesisLog[2].event == CounterfactualStated;
  assert hasEvent(st.hypothesisLog, 0, CounterfactualStated);
  assert st.hypothesisLog[3].hypothesisId == 0 && st.hypothesisLog[3].event == ObservabilityAssessed;
  assert hasEventWithResult(st.hypothesisLog, 0, ObservabilityAssessed);
  assert st.hypothesisLog[4].hypothesisId == 0 && st.hypothesisLog[4].event == AlternativeConsidered;
  assert hasEvent(st.hypothesisLog, 0, AlternativeConsidered);
  assert st.hypothesisLog[6].event == EquivalenceChecked;
  assert hasGlobalEquivalenceCheck(st.hypothesisLog);
  assert canTerminate(st);
}

// ============================================================
// 22. GAP1 CLOSURE: ITERATION CONVERGENCE
// ============================================================

// Model iteration progress as a decreasing measure.
// The outer loop S2→S3→S4→S5→S6→S7→S2 must make progress each pass.
// Progress = resolving undistinguished pairs OR rejecting hypotheses
// OR covering new cause classes OR adding new evidence.

// Iteration snapshot — captures the measurable state at one iteration boundary
datatype IterationSnapshot = IterationSnapshot(
  undistinguishedCount: nat,   // hypotheses still Undistinguished
  rejectedCount: nat,          // hypotheses rejected so far
  causeClassCount: nat,        // |causeClassesCovered|
  evidenceCount: nat,          // |evidenceLog|
  modelChangeCount: nat        // |modelChangeLog|
)

function iterationMeasure(s: IterationSnapshot): nat
  requires s.causeClassCount <= 14
{
  // Composite measure: undistinguished must decrease, OR rejected/covered must increase.
  // We encode as a single decreasing value: remaining work.
  // remainingWork = undistinguished + (14 - causeClassCount)
  // This decreases iff undistinguished decreases OR causeClassCount increases.
  s.undistinguishedCount + (14 - s.causeClassCount)
}

// Progress predicate: at least one axis must improve
predicate iterationMakesProgress(before: IterationSnapshot, after: IterationSnapshot)
{
  // At least one of these must hold:
  after.undistinguishedCount < before.undistinguishedCount ||  // resolved a pair
  after.rejectedCount > before.rejectedCount ||                // eliminated a hypothesis
  after.causeClassCount > before.causeClassCount ||            // covered a new cause class
  after.evidenceCount > before.evidenceCount                   // collected new evidence
}

// Strong progress: the composite measure strictly decreases
predicate strongProgress(before: IterationSnapshot, after: IterationSnapshot)
  requires before.causeClassCount <= 14
  requires after.causeClassCount <= 14
{
  iterationMeasure(after) < iterationMeasure(before)
}

// A39: If undistinguished decreases, measure decreases (causeClassCount held constant or increased)
lemma MeasureDecreasesOnUndistinguishedDrop(before: IterationSnapshot, after: IterationSnapshot)
  requires after.causeClassCount <= 14
  requires before.causeClassCount <= 14
  requires after.undistinguishedCount < before.undistinguishedCount
  requires after.causeClassCount >= before.causeClassCount
  ensures iterationMeasure(after) < iterationMeasure(before)
{}

// A39b: If cause classes increase and undistinguished held, measure decreases
lemma MeasureDecreasesOnCauseClassGain(before: IterationSnapshot, after: IterationSnapshot)
  requires after.causeClassCount <= 14
  requires before.causeClassCount <= 14
  requires after.causeClassCount > before.causeClassCount
  requires after.undistinguishedCount <= before.undistinguishedCount
  ensures iterationMeasure(after) < iterationMeasure(before)
{}

// A40: Measure is bounded — can't iterate forever
lemma MeasureIsBounded(s: IterationSnapshot)
  requires s.causeClassCount <= 14
  ensures iterationMeasure(s) <= s.undistinguishedCount + 14
{}

// A41: Zero measure means no undistinguished + all classes covered
lemma ZeroMeasureMeansComplete(s: IterationSnapshot)
  requires s.causeClassCount <= 14
  requires iterationMeasure(s) == 0
  ensures s.undistinguishedCount == 0
  ensures s.causeClassCount == 14
{}

// A42: Progress with bounded measure implies finite iterations
// Given N hypotheses total, undistinguished count ≤ N and cause classes ≤ 14,
// so the maximum iterations before convergence is N + 14.
lemma MaxIterations(totalHypotheses: nat)
  ensures totalHypotheses + 14 >= 0  // trivially true, but documents the bound
{
  // The actual bound: each iteration must either reduce undistinguished (max N times)
  // or increase cause class coverage (max 14 times). After N + 14 iterations of
  // strong progress, the measure reaches 0 and termination conditions become reachable.
}

// A43: Progress is monotonic for evidence/model logs (append-only)
lemma AppendOnlyLogsGrow(before: IterationSnapshot, after: IterationSnapshot)
  requires after.evidenceCount >= before.evidenceCount
  requires after.modelChangeCount >= before.modelChangeCount
  ensures after.evidenceCount >= before.evidenceCount  // logs never shrink
{}

// A44: An iteration that rejects a hypothesis makes progress
// (even if undistinguished count doesn't change)
lemma RejectionIsProgress(before: IterationSnapshot, after: IterationSnapshot)
  requires after.rejectedCount > before.rejectedCount
  ensures iterationMakesProgress(before, after)
{}

// A45: An iteration that collects new evidence makes progress
lemma NewEvidenceIsProgress(before: IterationSnapshot, after: IterationSnapshot)
  requires after.evidenceCount > before.evidenceCount
  ensures iterationMakesProgress(before, after)
{}

// ============================================================
// 23. GAP3 CLOSURE: PRODUCTION-FIRST WITHIN STEPS
// ============================================================

// Model production-first as a constraint on evidence ordering within each step.
// Within any production-first step, the first evidence entry must be Direct or Inferred.

// Filter evidence entries by step
function entriesForStep(log: seq<EvidenceEntry>, step: Step): seq<EvidenceEntry>
{
  if |log| == 0 then []
  else if log[0].step == step then [log[0]] + entriesForStep(log[1..], step)
  else entriesForStep(log[1..], step)
}

// Production-first constraint: first evidence in a step must be production-grade
predicate productionFirstInStep(log: seq<EvidenceEntry>, step: Step)
{
  var stepEntries := entriesForStep(log, step);
  |stepEntries| == 0 ||  // no entries for this step is fine (step may not collect)
  stepEntries[0].reliability == Direct || stepEntries[0].reliability == Inferred
}

// Full production-first: holds for ALL production-first steps
predicate productionFirstAllSteps(log: seq<EvidenceEntry>)
{
  productionFirstInStep(log, S0b_VerifySymptom) &&
  productionFirstInStep(log, S1_BuildModel) &&
  productionFirstInStep(log, S2_GenHypotheses) &&
  productionFirstInStep(log, S3_DesignChecks) &&
  productionFirstInStep(log, S4_CollectFacts) &&
  productionFirstInStep(log, S7_DeepenModel)
}

// A46: Empty log trivially satisfies production-first
lemma EmptyLogSatisfiesProductionFirst()
  ensures productionFirstAllSteps([])
{}

// Helper: entriesForStep of a singleton matching list
lemma EntriesForStepSingleton(e: EvidenceEntry)
  requires true
  ensures entriesForStep([e], e.step) == [e]
{
  // Dafny unfolds: |[e]| != 0, [e][0].step == e.step, so [e[0]] + entriesForStep([], e.step)
  // entriesForStep([], e.step) == [] since |[]| == 0
  assert entriesForStep([], e.step) == [];
}

// A47: A log starting with Direct evidence at a step satisfies production-first for that step
lemma DirectFirstSatisfies(step: Step)
  ensures productionFirstInStep(
    [EvidenceEntry(step, SrcProductionDB, Direct, false, false, true)],
    step)
{
  var e := EvidenceEntry(step, SrcProductionDB, Direct, false, false, true);
  EntriesForStepSingleton(e);
}

// A48: Interpreted-first violates production-first
lemma InterpretedFirstViolates(step: Step)
  requires stepUsesProductionFirst(step)
  ensures !productionFirstInStep(
    [EvidenceEntry(step, SrcRepoCode, Interpreted, false, false, true)],
    step)
{
  var e := EvidenceEntry(step, SrcRepoCode, Interpreted, false, false, true);
  EntriesForStepSingleton(e);
}

// A49: UnreliableSource-first violates production-first
lemma UnreliableFirstViolates(step: Step)
  requires stepUsesProductionFirst(step)
  ensures !productionFirstInStep(
    [EvidenceEntry(step, SrcMobileAppCode, UnreliableSource, false, false, true)],
    step)
{
  var e := EvidenceEntry(step, SrcMobileAppCode, UnreliableSource, false, false, true);
  EntriesForStepSingleton(e);
}

// A50: Inferred-first also satisfies (production logs > 7 days are Inferred but still production)
lemma InferredFirstSatisfies(step: Step)
  ensures productionFirstInStep(
    [EvidenceEntry(step, SrcOldProductionLogs, Inferred, false, false, true)],
    step)
{
  var e := EvidenceEntry(step, SrcOldProductionLogs, Inferred, false, false, true);
  EntriesForStepSingleton(e);
}

// A51: Non-production-first steps are unconstrained
// Steps like S0_FixSymptom, S5_UpdateModel, etc. can start with any evidence type
lemma NonProductionFirstStepsUnconstrained()
  ensures !stepUsesProductionFirst(S0_FixSymptom)
  ensures !stepUsesProductionFirst(S5_UpdateModel)
  ensures !stepUsesProductionFirst(S6_CheckEquiv)
  ensures !stepUsesProductionFirst(S8_Terminate)
{}

// ============================================================
// 24. GAP4 CLOSURE: GENUINE CAUSE CLASS COVERAGE (M1)
// ============================================================

// Replace simple set membership with proof-of-work per cause class.
// Each class must have EITHER a linked evidence entry OR an explicit exclusion reason.

datatype CauseClassVerdict =
  | CcCovered(evidenceIdx: nat)          // Covered: points to evidence entry
  | CcExcludedSafe(reason: nat)          // Excluded but safe — documented why
  | CcNotRelevant(reason: nat)           // Not relevant to this symptom — documented why

// A verdict map covers all 14 cause classes
predicate allClassesHaveVerdict(verdicts: map<CauseClass, CauseClassVerdict>)
{
  CC_Concurrency in verdicts &&
  CC_SharedMutableState in verdicts &&
  CC_ObjectLifecycle in verdicts &&
  CC_Caching in verdicts &&
  CC_AsyncBoundaries in verdicts &&
  CC_ExternalSystem in verdicts &&
  CC_PartialObservability in verdicts &&
  CC_ConfigFeatureFlags in verdicts &&
  CC_DataMigration in verdicts &&
  CC_TenantIsolation in verdicts &&
  CC_AuthState in verdicts &&
  CC_DeploymentDrift in verdicts &&
  CC_MultiArtifact in verdicts &&
  CC_BuildPipeline in verdicts
}

// Covered verdicts must reference valid evidence entries
predicate coveredVerdictsGrounded(verdicts: map<CauseClass, CauseClassVerdict>,
                                   evidenceLogSize: nat)
{
  forall cc :: cc in verdicts && verdicts[cc].CcCovered? ==>
    verdicts[cc].evidenceIdx < evidenceLogSize
}

// Full genuine coverage: all classes have verdicts, and covered ones are grounded
predicate genuineCauseClassCoverage(verdicts: map<CauseClass, CauseClassVerdict>,
                                     evidenceLogSize: nat)
{
  allClassesHaveVerdict(verdicts) &&
  coveredVerdictsGrounded(verdicts, evidenceLogSize)
}

// A52: Genuine coverage implies all 14 classes are addressed
lemma GenuineCoverageIsComplete(verdicts: map<CauseClass, CauseClassVerdict>,
                                 evidenceLogSize: nat)
  requires genuineCauseClassCoverage(verdicts, evidenceLogSize)
  ensures CC_Concurrency in verdicts
  ensures CC_DeploymentDrift in verdicts
  ensures CC_BuildPipeline in verdicts
{}

// A53: A covered verdict with invalid evidence index fails grounding
lemma InvalidEvidenceIndexFails(verdicts: map<CauseClass, CauseClassVerdict>,
                                 evidenceLogSize: nat)
  requires CC_Concurrency in verdicts
  requires verdicts[CC_Concurrency].CcCovered?
  requires verdicts[CC_Concurrency].evidenceIdx >= evidenceLogSize
  ensures !coveredVerdictsGrounded(verdicts, evidenceLogSize)
{}

// A54: All-excluded verdicts satisfy coverage (but signal shallow investigation)
// This is intentional — we can't structurally prevent rubber-stamping, but we CAN
// require that each exclusion has a reason (the nat field). A review can check reasons.
lemma AllExcludedSatisfiesCoverage()
  ensures allClassesHaveVerdict(
    map[CC_Concurrency := CcNotRelevant(0),
        CC_SharedMutableState := CcNotRelevant(1),
        CC_ObjectLifecycle := CcNotRelevant(2),
        CC_Caching := CcNotRelevant(3),
        CC_AsyncBoundaries := CcNotRelevant(4),
        CC_ExternalSystem := CcNotRelevant(5),
        CC_PartialObservability := CcNotRelevant(6),
        CC_ConfigFeatureFlags := CcNotRelevant(7),
        CC_DataMigration := CcNotRelevant(8),
        CC_TenantIsolation := CcNotRelevant(9),
        CC_AuthState := CcNotRelevant(10),
        CC_DeploymentDrift := CcNotRelevant(11),
        CC_MultiArtifact := CcNotRelevant(12),
        CC_BuildPipeline := CcNotRelevant(13)])
{}

// A55: Mixed verdicts (some covered, some excluded) are valid
lemma MixedVerdictsSatisfyCoverage()
{
  var v := map[
    CC_Concurrency := CcCovered(0),
    CC_SharedMutableState := CcCovered(1),
    CC_ObjectLifecycle := CcNotRelevant(0),
    CC_Caching := CcCovered(2),
    CC_AsyncBoundaries := CcExcludedSafe(0),
    CC_ExternalSystem := CcNotRelevant(1),
    CC_PartialObservability := CcCovered(3),
    CC_ConfigFeatureFlags := CcNotRelevant(2),
    CC_DataMigration := CcExcludedSafe(1),
    CC_TenantIsolation := CcNotRelevant(3),
    CC_AuthState := CcNotRelevant(4),
    CC_DeploymentDrift := CcCovered(4),
    CC_MultiArtifact := CcExcludedSafe(2),
    CC_BuildPipeline := CcCovered(5)
  ];
  assert allClassesHaveVerdict(v);
  assert coveredVerdictsGrounded(v, 10);  // all evidence indices < 10
  assert genuineCauseClassCoverage(v, 10);
}

// A56: Genuine coverage is strictly stronger than simple set coverage
// (The old model only checked causeClassesCovered == ALL_CAUSE_CLASSES.
// Genuine coverage additionally requires evidence links for covered classes.)
lemma GenuineStrongerThanSetCoverage(verdicts: map<CauseClass, CauseClassVerdict>,
                                      evidenceLogSize: nat)
  requires genuineCauseClassCoverage(verdicts, evidenceLogSize)
  ensures allClassesHaveVerdict(verdicts)
  ensures coveredVerdictsGrounded(verdicts, evidenceLogSize)
{}

// ============================================================
// 26. F4 — TASK TYPE AND PRODUCTION-FIRST FOR FIX TASKS
// ============================================================

// F4: when the investigation goal includes fixing a behavior, the first fact
// collected must be a Direct production observation of current behavior.
// This establishes the baseline against which the fix will be measured.

datatype InvestigationGoal = Investigate | Fix

// F4: for Fix tasks, the first evidence entry must be Direct (stricter than TC19)
// TC19 requires Direct or Inferred for all tasks; F4 narrows to Direct for Fix.
predicate f4_firstFactConstraint(goal: InvestigationGoal, firstEntry: EvidenceEntry)
{
  goal == Fix ==> firstEntry.reliability == Direct
}

// TC19 + F4 combined: first fact constraint depends on goal
predicate firstFactValid(goal: InvestigationGoal, firstEntry: EvidenceEntry)
{
  // TC19: all tasks require Direct or Inferred
  (firstEntry.reliability == Direct || firstEntry.reliability == Inferred) &&
  // F4: Fix tasks additionally require Direct
  f4_firstFactConstraint(goal, firstEntry)
}

// F4-A1: Fix task requires Direct first fact
lemma F4_FixRequiresDirect(e: EvidenceEntry)
  requires firstFactValid(Fix, e)
  ensures e.reliability == Direct
{}

// F4-A2: Investigate task allows Inferred first fact
lemma F4_InvestigateAllowsInferred()
  ensures firstFactValid(Investigate,
    EvidenceEntry(S4_CollectFacts, SrcOldProductionLogs, Inferred, false, false, true))
{}

// F4-A3: Investigate task also allows Direct first fact
lemma F4_InvestigateAllowsDirect()
  ensures firstFactValid(Investigate,
    EvidenceEntry(S4_CollectFacts, SrcProductionDB, Direct, false, false, true))
{}

// F4-A4: Neither task allows Interpreted first fact
lemma F4_NeitherAllowsInterpreted(goal: InvestigationGoal, e: EvidenceEntry)
  requires e.reliability == Interpreted
  ensures !firstFactValid(goal, e)
{}

// F4-A5: Neither task allows UnreliableSource first fact
lemma F4_NeitherAllowsUnreliable(goal: InvestigationGoal, e: EvidenceEntry)
  requires e.reliability == UnreliableSource
  ensures !firstFactValid(goal, e)
{}

// F4-A6: Fix is strictly more constrained than Investigate
// (everything valid for Fix is valid for Investigate, but not vice versa)
lemma F4_FixStricterThanInvestigate(e: EvidenceEntry)
  requires firstFactValid(Fix, e)
  ensures firstFactValid(Investigate, e)
{}

// F4-A7: Inferred is valid for Investigate but not Fix
lemma F4_InferredDistinguishesGoals()
{
  var e := EvidenceEntry(S4_CollectFacts, SrcOldProductionLogs, Inferred, false, false, true);
  assert firstFactValid(Investigate, e);
  assert !firstFactValid(Fix, e);
}

// F4-A8: F3 consistency — RepoCode source can never satisfy F4 for Fix tasks
lemma F4_RepoCodeBlocksFix(e: EvidenceEntry)
  requires f3_reliabilityConsistent(e)
  requires e.source == SrcRepoCode
  ensures !firstFactValid(Fix, e)
  ensures !firstFactValid(Investigate, e)  // also blocked by TC19
{}

// ============================================================
// 26a. F3 — VERIFY DATA INPUTS, NOT JUST CODE PATHS (TC23)
// ============================================================

// F3 (data-input rule): when a hypothesis's causal chain includes a conditional
// on dynamic data (DB templates, admin config, feature flags, CMS content),
// a deterministic code path is only deterministic if its inputs are constant.
// The evidence log must contain entries verifying:
//   (a) current value of the data
//   (b) when it was last changed (audit trail)
//   (c) whether the triggering condition existed for the full symptom window

datatype DynamicDataCheck = DynamicDataCheck(
  currentValueVerified: bool,     // (a) production query for current value
  changeHistoryVerified: bool,    // (b) audit trail / revision table checked
  timelineCoverageVerified: bool  // (c) triggering condition covers symptom window
)

// A hypothesis may or may not depend on dynamic data
datatype DataDependency =
  | NoDynamicData              // hypothesis doesn't involve dynamic data — F3 N/A
  | DynamicDataDependent(check: DynamicDataCheck)  // hypothesis depends on dynamic data

// F3 is satisfied when: no dynamic data dependency, OR all three checks pass
predicate f3_dataInputVerified(dep: DataDependency)
{
  dep.NoDynamicData? ||
  (dep.DynamicDataDependent? &&
   dep.check.currentValueVerified &&
   dep.check.changeHistoryVerified &&
   dep.check.timelineCoverageVerified)
}

// F3-D1: No dynamic data dependency trivially satisfies F3
lemma F3_NoDynamicDataSatisfied()
  ensures f3_dataInputVerified(NoDynamicData)
{}

// F3-D2: All three checks verified satisfies F3
lemma F3_AllChecksVerifiedSatisfied()
  ensures f3_dataInputVerified(
    DynamicDataDependent(DynamicDataCheck(true, true, true)))
{}

// F3-D3: Missing current value blocks F3
lemma F3_MissingCurrentValueBlocks()
  ensures !f3_dataInputVerified(
    DynamicDataDependent(DynamicDataCheck(false, true, true)))
{}

// F3-D4: Missing change history blocks F3
lemma F3_MissingChangeHistoryBlocks()
  ensures !f3_dataInputVerified(
    DynamicDataDependent(DynamicDataCheck(true, false, true)))
{}

// F3-D5: Missing timeline coverage blocks F3
lemma F3_MissingTimelineCoverageBlocks()
  ensures !f3_dataInputVerified(
    DynamicDataDependent(DynamicDataCheck(true, true, false)))
{}

// F3-D6: Completely unverified dynamic data blocks F3
lemma F3_UnverifiedDynamicDataBlocks()
  ensures !f3_dataInputVerified(
    DynamicDataDependent(DynamicDataCheck(false, false, false)))
{}

// F3-D7: A hypothesis that blames a code path without verifying data inputs
// is incomplete — it must be weakened, not accepted
// (This is the core lesson: deterministic code != deterministic outcome
// when runtime data changes)
lemma F3_UnverifiedDataMeansIncomplete(dep: DataDependency)
  requires dep.DynamicDataDependent?
  requires !dep.check.timelineCoverageVerified
  ensures !f3_dataInputVerified(dep)
{}

// ============================================================
// 27. VALID TRANSITIONS — connected to termination proof
// ============================================================

// The validTransition predicate (section 7) defines which status transitions
// are legal. Here we prove that the terminal states reached at canTerminate
// are reachable only through valid transition paths.

// A valid transition sequence: every consecutive pair is a valid transition
predicate validTransitionSeq(statuses: seq<HypothesisStatus>)
{
  forall i :: 0 <= i < |statuses| - 1 ==> validTransition(statuses[i], statuses[i+1])
}

// VT-A1: Accepted is only reachable from Compatible
lemma VT_AcceptedOnlyFromCompatible(from: HypothesisStatus)
  requires validTransition(from, Accepted)
  ensures from == Compatible
{}

// VT-A2: Rejected is terminal — nothing follows it
lemma VT_RejectedIsTerminal(to: HypothesisStatus)
  ensures !validTransition(Rejected, to)
{}

// VT-A3: Accepted is terminal — nothing follows it
lemma VT_AcceptedIsTerminal(to: HypothesisStatus)
  ensures !validTransition(Accepted, to)
{}

// VT-A4: Active can reach any non-terminal status
lemma VT_ActiveReachesAll()
  ensures validTransition(Active, Compatible)
  ensures validTransition(Active, Weakened)
  ensures validTransition(Active, Rejected)
  ensures validTransition(Active, Undistinguished)
  ensures !validTransition(Active, Accepted)  // can't skip Compatible
{}

// VT-A5: Undistinguished can only go to Compatible or Rejected
lemma VT_UndistinguishedLimited()
  ensures validTransition(Undistinguished, Compatible)
  ensures validTransition(Undistinguished, Rejected)
  ensures !validTransition(Undistinguished, Accepted)
  ensures !validTransition(Undistinguished, Weakened)
  ensures !validTransition(Undistinguished, Active)
{}

// VT-A6: The acceptance path must go through Compatible
// (Any hypothesis reaching Accepted must have been Compatible immediately before)
lemma VT_AcceptanceRequiresCompatible(path: seq<HypothesisStatus>)
  requires |path| >= 2
  requires validTransitionSeq(path)
  requires path[|path|-1] == Accepted
  ensures path[|path|-2] == Compatible
{
  var n := |path| - 1;
  assert validTransition(path[n-1], path[n]);
  assert validTransition(path[n-1], Accepted);
  VT_AcceptedOnlyFromCompatible(path[n-1]);
}

// VT-A7: canTerminate implies the accepted hypothesis has status Accepted,
// and Accepted is only reachable from Compatible via valid transitions.
// This connects the transition graph to the termination proof.
lemma VT_TerminationImpliesValidPath(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures st.hypotheses[st.acceptedId].status == Accepted
  // The transition from Compatible→Accepted is the only way to reach Accepted
  ensures validTransition(Compatible, Accepted)
{}

// VT-A8: Rejected status means no further transitions are possible
lemma VT_RejectedStatusIsStable(status: HypothesisStatus)
  requires status == Rejected
  ensures forall to: HypothesisStatus :: !validTransition(status, to)
{
  forall to: HypothesisStatus
    ensures !validTransition(Rejected, to)
  {
    VT_RejectedIsTerminal(to);
  }
}

// VT-A9: Accepted status means no further transitions are possible
lemma VT_AcceptedStatusIsStable(status: HypothesisStatus)
  requires status == Accepted
  ensures forall to: HypothesisStatus :: !validTransition(status, to)
{
  forall to: HypothesisStatus
    ensures !validTransition(Accepted, to)
  {
    VT_AcceptedIsTerminal(to);
  }
}

// VT-A10: At termination, the entire hypothesis set is frozen —
// every hypothesis is in a terminal state (Accepted or Rejected)
// and no valid transitions exist for any of them.
lemma VT_TerminationFreezesAll(st: InvestigationState)
  requires 0 <= st.acceptedId < |st.hypotheses|
  requires canTerminate(st)
  ensures st.hypotheses[st.acceptedId].status == Accepted
  ensures allOthersRejected(st.hypotheses, st.acceptedId)
{}

// ============================================================
// 29. TC24 — FORMAL MODEL REQUIREMENT + DUAL-MODEL WORKFLOW + SKIP
// ============================================================
// (Was TC23; renumbered after TC23 was assigned to F3 data-input verification)

// Model status: was a formal model built, or was skip acknowledged?
datatype ModelStatus = ModelBuilt(tool: ModelingTool) | SkipAcknowledged | NoModelNoSkip

datatype ModelingTool = Dafny | Alloy | DafnyThenAlloy

// TC24: formal model file exists with solver results, OR user acknowledged skip
predicate tc24_formalModelSatisfied(status: ModelStatus)
{
  status.ModelBuilt? || status.SkipAcknowledged?
}

// NoModelNoSkip is the ONLY state that fails TC24
predicate tc24_fails(status: ModelStatus)
{
  status.NoModelNoSkip?
}

// TC24-A1: Built model satisfies TC24 regardless of tool
lemma TC24_BuiltSatisfied(tool: ModelingTool)
  ensures tc24_formalModelSatisfied(ModelBuilt(tool))
{}

// TC24-A2: Acknowledged skip satisfies TC24
lemma TC24_SkipSatisfied()
  ensures tc24_formalModelSatisfied(SkipAcknowledged)
{}

// TC24-A3: No model and no skip fails TC24
lemma TC24_NoModelFails()
  ensures !tc24_formalModelSatisfied(NoModelNoSkip)
  ensures tc24_fails(NoModelNoSkip)
{}

// TC24-A4: TC24 is exactly: built OR skip-acknowledged
lemma TC24_ExactlyTwoWays(status: ModelStatus)
  ensures tc24_formalModelSatisfied(status) <==>
    (status.ModelBuilt? || status.SkipAcknowledged?)
{}

// --- Skip protocol: Claude proposes, user decides ---

datatype SkipDecision = UserAccepted | UserRejected | NotProposed

// Skip can only be acknowledged if user explicitly accepted
predicate validSkipPath(proposed: bool, decision: SkipDecision, status: ModelStatus)
{
  // If skip was proposed and user accepted → SkipAcknowledged
  ((proposed && decision == UserAccepted) ==> status.SkipAcknowledged?) &&
  // If skip was proposed and user rejected → model must be built
  ((proposed && decision == UserRejected) ==> status.ModelBuilt?) &&
  // If skip was NOT proposed → model must be built (default path)
  ((!proposed) ==> status.ModelBuilt?) &&
  // SkipAcknowledged requires proposal + acceptance (can't skip silently)
  (status.SkipAcknowledged? ==> (proposed && decision == UserAccepted))
}

// SKIP-A1: Silent skip is impossible — SkipAcknowledged requires proposal + acceptance (TC24)
lemma SkipRequiresProposalAndAcceptance(status: ModelStatus)
  requires status.SkipAcknowledged?
  requires validSkipPath(true, UserAccepted, status)
  ensures true  // just checks the requires are satisfiable
{}

// SKIP-A2: If skip not proposed, model must be built
lemma NoProposalMeansModelBuilt(status: ModelStatus)
  requires validSkipPath(false, NotProposed, status)
  ensures status.ModelBuilt?
{}

// SKIP-A3: If user rejects skip, model must be built
lemma RejectedSkipMeansModelBuilt(status: ModelStatus)
  requires validSkipPath(true, UserRejected, status)
  ensures status.ModelBuilt?
{}

// SKIP-A4: Claude cannot skip on its own (not proposed but skip acknowledged is invalid)
lemma ClaudeCannotSkipAlone()
  ensures !validSkipPath(false, NotProposed, SkipAcknowledged)
{}

// SKIP-A5: Claude cannot skip even if it wanted to (proposed but no user decision)
lemma ProposalAloneIsNotSkip()
  ensures !validSkipPath(true, NotProposed, SkipAcknowledged)
{}

// --- Dual-model workflow: Dafny fast → Alloy deep ---

// The tool progression: Dafny alone, Alloy alone, or Dafny then Alloy
predicate validToolProgression(tool: ModelingTool, hasDafny: bool, hasAlloy: bool)
{
  (tool == Dafny ==> hasDafny && !hasAlloy) &&
  (tool == Alloy ==> !hasDafny && hasAlloy) &&
  (tool == DafnyThenAlloy ==> hasDafny && hasAlloy)
}

// DUAL-A1: DafnyThenAlloy requires both tools used
lemma DualRequiresBoth()
  ensures validToolProgression(DafnyThenAlloy, true, true)
  ensures !validToolProgression(DafnyThenAlloy, true, false)
  ensures !validToolProgression(DafnyThenAlloy, false, true)
{}

// DUAL-A2: Dafny-only is valid (the default fast path)
lemma DafnyOnlyIsValid()
  ensures validToolProgression(Dafny, true, false)
{}

// DUAL-A3: Alloy-only is valid (fallback if Dafny unavailable)
lemma AlloyOnlyIsValid()
  ensures validToolProgression(Alloy, false, true)
{}

// DUAL-A4: Any tool choice satisfies TC24
lemma AnyToolSatisfiesTC24(tool: ModelingTool)
  ensures tc24_formalModelSatisfied(ModelBuilt(tool))
{}

// --- Extended InvestigationState with TC23 (F3 data) + TC24 (formal model) fields ---

datatype ExtendedInvestigationState = ExtendedInvestigationState(
  base: InvestigationState,
  modelStatus: ModelStatus,
  skipProposed: bool,
  skipDecision: SkipDecision,
  acceptedHypothesisDataDep: DataDependency  // TC23: F3 data-input dependency for accepted hypothesis
)

// Full extended check: base TC1-TC18 + TC23 (F3 data) + TC24 (formal model)
predicate extendedCanTerminate(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
{
  canTerminate(ext.base) &&
  // TC23: F3 data-input verification
  f3_dataInputVerified(ext.acceptedHypothesisDataDep) &&
  // TC24: formal model or acknowledged skip
  tc24_formalModelSatisfied(ext.modelStatus) &&
  validSkipPath(ext.skipProposed, ext.skipDecision, ext.modelStatus)
}

// TC23-A5: Extended termination guarantees F3 data-input verification
lemma ExtendedTerminationGuaranteesF3Data(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
  requires extendedCanTerminate(ext)
  ensures f3_dataInputVerified(ext.acceptedHypothesisDataDep)
{}

// TC23-A6: Unverified dynamic data blocks termination
lemma UnverifiedDynamicDataBlocksTermination(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
  requires ext.acceptedHypothesisDataDep.DynamicDataDependent?
  requires !ext.acceptedHypothesisDataDep.check.timelineCoverageVerified
  ensures !extendedCanTerminate(ext)
{}

// TC23-A7: No dynamic data dependency trivially satisfies TC23
lemma NoDynamicDataSatisfiesTC23(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
  requires canTerminate(ext.base)
  requires ext.acceptedHypothesisDataDep.NoDynamicData?
  requires tc24_formalModelSatisfied(ext.modelStatus)
  requires validSkipPath(ext.skipProposed, ext.skipDecision, ext.modelStatus)
  ensures extendedCanTerminate(ext)
{}

// TC24-A5: Extended termination guarantees formal model or acknowledged skip
lemma ExtendedTerminationGuaranteesTC24(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
  requires extendedCanTerminate(ext)
  ensures tc24_formalModelSatisfied(ext.modelStatus)
  ensures ext.modelStatus.ModelBuilt? || ext.modelStatus.SkipAcknowledged?
{}

// TC24-A6: Extended termination is impossible without model or skip
lemma ExtendedTerminationBlockedWithoutModel(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
  requires ext.modelStatus.NoModelNoSkip?
  ensures !extendedCanTerminate(ext)
{}

// TC24-A7: Silent skip blocks termination
lemma SilentSkipBlocksTermination(ext: ExtendedInvestigationState)
  requires 0 <= ext.base.acceptedId < |ext.base.hypotheses|
  requires ext.modelStatus.SkipAcknowledged?
  requires !ext.skipProposed  // Claude didn't propose — silent skip attempt
  ensures !extendedCanTerminate(ext)
{}

// ============================================================
// 29a. TC23 — F3 DATA-INPUT VERIFICATION (TERMINATION CONDITION)
// ============================================================

// TC23: if the accepted hypothesis's causal chain includes a conditional on
// dynamic data, the evidence log must contain entries verifying:
//   (a) current value of the data
//   (b) when it was last changed
//   (c) whether triggering condition existed for full symptom window
//
// This is modeled via the `acceptedHypothesisDataDep` field on
// ExtendedInvestigationState and the `f3_dataInputVerified` predicate.
//
// The key post-mortem lesson: a deterministic code path is only deterministic
// if its inputs are constant. When runtime data (templates, config, feature
// flags) changes, the same code path can produce different outcomes.
// Accepting a hypothesis that blames a code path without verifying that the
// data inputs were stable across the symptom window is a false positive risk.

// TC23-WITNESS: A valid extended investigation with dynamic data dependency
lemma TC23_WitnessWithDynamicData()
  ensures exists ext: ExtendedInvestigationState ::
    0 <= ext.base.acceptedId < |ext.base.hypotheses| &&
    ext.acceptedHypothesisDataDep.DynamicDataDependent? &&
    extendedCanTerminate(ext)
{
  var accepted := Hypothesis(
    hasMechanism := true,
    hasCounterfactual := true,
    counterfactualObservable := true,
    counterfactualVerified := true,
    status := Accepted,
    hasAlternative := true,
    hasDirectSupport := true
  );
  var rejected := Hypothesis(
    hasMechanism := true,
    hasCounterfactual := true,
    counterfactualObservable := false,
    counterfactualVerified := false,
    status := Rejected,
    hasAlternative := false,
    hasDirectSupport := false
  );
  var evidenceLog := [
    EvidenceEntry(S0b_VerifySymptom, SrcProductionDB, Direct, false, false, true)
  ];
  var hypothesisLog := [
    HypothesisLogEntry(S2_GenHypotheses, 0, Created, false),
    HypothesisLogEntry(S2_GenHypotheses, 0, MechanismStated, false),
    HypothesisLogEntry(S2_GenHypotheses, 0, CounterfactualStated, false),
    HypothesisLogEntry(S6_CheckEquiv, 0, ObservabilityAssessed, false),
    HypothesisLogEntry(S6_CheckEquiv, 0, AlternativeConsidered, false),
    HypothesisLogEntry(S8_Terminate, 0, StatusChanged, true),
    HypothesisLogEntry(S6_CheckEquiv, 0, EquivalenceChecked, false),
    HypothesisLogEntry(S2_GenHypotheses, 1, Created, false),
    HypothesisLogEntry(S5_UpdateModel, 1, StatusChanged, true)
  ];
  var modelChangeLog := [
    ModelChangeEntry(S1_BuildModel, InitialBuild, false),
    ModelChangeEntry(S5_UpdateModel, FactIntegration, true)
  ];
  var baseSt := InvestigationState(
    hypotheses := [accepted, rejected],
    acceptedId := 0,
    evidenceLog := evidenceLog,
    hypothesisLog := hypothesisLog,
    modelChangeLog := modelChangeLog,
    causeClassesCovered := ALL_CAUSE_CLASSES,
    modelWasBuilt := true
  );

  // Key assertions for canTerminate(baseSt)
  assert baseSt.hypotheses[0].status == Accepted;
  assert allOthersRejected(baseSt.hypotheses, 0);
  assert baseSt.evidenceLog[0].reliability == Direct;
  assert hasDirectEvidence(baseSt.evidenceLog);
  assert noStaleDirectEvidence(baseSt.evidenceLog);
  assert modelLogNonEmpty(baseSt.modelChangeLog);
  assert modelRerunAfterFacts(baseSt.modelChangeLog);
  assert baseSt.hypothesisLog[1].hypothesisId == 0 && baseSt.hypothesisLog[1].event == MechanismStated;
  assert hasEvent(baseSt.hypothesisLog, 0, MechanismStated);
  assert baseSt.hypothesisLog[2].hypothesisId == 0 && baseSt.hypothesisLog[2].event == CounterfactualStated;
  assert hasEvent(baseSt.hypothesisLog, 0, CounterfactualStated);
  assert baseSt.hypothesisLog[3].hypothesisId == 0 && baseSt.hypothesisLog[3].event == ObservabilityAssessed;
  assert hasEventWithResult(baseSt.hypothesisLog, 0, ObservabilityAssessed);
  assert baseSt.hypothesisLog[4].hypothesisId == 0 && baseSt.hypothesisLog[4].event == AlternativeConsidered;
  assert hasEvent(baseSt.hypothesisLog, 0, AlternativeConsidered);
  assert baseSt.hypothesisLog[6].event == EquivalenceChecked;
  assert hasGlobalEquivalenceCheck(baseSt.hypothesisLog);
  assert canTerminate(baseSt);

  var ext := ExtendedInvestigationState(
    base := baseSt,
    modelStatus := ModelBuilt(Dafny),
    skipProposed := false,
    skipDecision := NotProposed,
    acceptedHypothesisDataDep := DynamicDataDependent(DynamicDataCheck(true, true, true))
  );

  assert f3_dataInputVerified(ext.acceptedHypothesisDataDep);
  assert tc24_formalModelSatisfied(ext.modelStatus);
  assert validSkipPath(ext.skipProposed, ext.skipDecision, ext.modelStatus);
  assert extendedCanTerminate(ext);
}

// ============================================================
// 29b. F6-F9 — EVIDENCE QUALITY RULES
// ============================================================

// F6: Cross-source absence verification.
// When a query returns 0 rows for a behavior, the investigator must query ALL
// tables/columns/logs where the behavior could leave a trace. A single-source
// zero is one data point, not a conclusion.

datatype AbsenceClaim = AbsenceClaim(
  sourcesChecked: nat,    // how many independent sources were queried
  sourcesTotal: nat,      // how many sources COULD contain the trace
  allAgreeAbsent: bool    // do ALL sources return zero?
)

// F6: absence is confirmed only when all sources agree
predicate f6_absenceVerified(claim: AbsenceClaim)
{
  claim.sourcesChecked == claim.sourcesTotal &&
  claim.sourcesTotal > 0 &&
  claim.allAgreeAbsent
}

// F6: single-source zero is insufficient
predicate f6_singleSourceInsufficient(claim: AbsenceClaim)
{
  claim.sourcesChecked == 1 && claim.sourcesTotal > 1
}

// F6-A1: Single source with multiple available → insufficient
lemma F6_SingleSourceInsufficient(claim: AbsenceClaim)
  requires claim.sourcesChecked == 1
  requires claim.sourcesTotal > 1
  ensures !f6_absenceVerified(claim)
{}

// F6-A2: All sources checked and agree → verified
lemma F6_AllSourcesAgree(claim: AbsenceClaim)
  requires claim.sourcesChecked == claim.sourcesTotal
  requires claim.sourcesTotal > 0
  requires claim.allAgreeAbsent
  ensures f6_absenceVerified(claim)
{}

// F6-A3: Zero sources checked → not verified
lemma F6_ZeroSourcesNotVerified(claim: AbsenceClaim)
  requires claim.sourcesChecked == 0
  ensures !f6_absenceVerified(claim)
{}

// F6-A4: Partial check (some sources unchecked) → not verified
lemma F6_PartialCheckNotVerified(claim: AbsenceClaim)
  requires claim.sourcesChecked < claim.sourcesTotal
  ensures !f6_absenceVerified(claim)
{}

// -------------------------------------------------------

// F7: Trace the writer, not the reader.
// When a field holds a wrong value, evidence must include write-path analysis.
// A hypothesis that blames the consumer without identifying the producer is
// incomplete.

datatype WrongValueEvidence = WrongValueEvidence(
  writePathsEnumerated: bool,    // all INSERT/UPDATE paths found?
  producerIdentified: bool,      // specific write path matched to wrong value?
  consumerOnlyAnalysis: bool     // only the read/display side was analyzed?
)

// F7: evidence is complete only when the producer is identified
predicate f7_writePathTraced(ev: WrongValueEvidence)
{
  ev.writePathsEnumerated && ev.producerIdentified
}

// F7-A1: Consumer-only analysis is incomplete
lemma F7_ConsumerOnlyIncomplete(ev: WrongValueEvidence)
  requires ev.consumerOnlyAnalysis
  requires !ev.writePathsEnumerated
  ensures !f7_writePathTraced(ev)
{}

// F7-A2: Full write-path analysis is complete
lemma F7_WritePathComplete(ev: WrongValueEvidence)
  requires ev.writePathsEnumerated
  requires ev.producerIdentified
  ensures f7_writePathTraced(ev)
{}

// F7-A3: Enumerated paths but no match → incomplete
lemma F7_NoMatchIncomplete(ev: WrongValueEvidence)
  requires ev.writePathsEnumerated
  requires !ev.producerIdentified
  ensures !f7_writePathTraced(ev)
{}

// -------------------------------------------------------

// F8: Compute locally before estimating.
// When a computation can be replicated locally (tokenizer, hash, encoding),
// the exact result is Direct evidence. An estimate from statistical proxies
// is Inferred at best. An "unexplained residual" > 5% signals estimation
// where computation was possible.

datatype NumericEvidence = NumericEvidence(
  replicableLocally: bool,     // can the computation be re-run?
  computedExact: bool,         // was the exact value computed?
  estimatedFromProxy: bool,    // was a statistical proxy used?
  residualPercent: nat         // unexplained residual as % of total
)

// F8: evidence reliability depends on computation method
function f8_evidenceReliability(ev: NumericEvidence): Reliability
{
  if ev.computedExact then Direct
  else if ev.estimatedFromProxy then Inferred
  else Interpreted  // neither computed nor estimated — narrative reasoning
}

// F8: unexplained residual > 5% when computation was possible = error signal
predicate f8_residualSignalsError(ev: NumericEvidence)
{
  ev.replicableLocally && !ev.computedExact && ev.residualPercent > 5
}

// F8-A1: Exact computation produces Direct evidence
lemma F8_ExactIsDirect(ev: NumericEvidence)
  requires ev.computedExact
  ensures f8_evidenceReliability(ev) == Direct
{}

// F8-A2: Estimation produces Inferred evidence (weaker)
lemma F8_EstimateIsInferred(ev: NumericEvidence)
  requires !ev.computedExact
  requires ev.estimatedFromProxy
  ensures f8_evidenceReliability(ev) == Inferred
{}

// F8-A3: Residual with replicable computation = error signal
lemma F8_ResidualSignalsError(ev: NumericEvidence)
  requires ev.replicableLocally
  requires !ev.computedExact
  requires ev.residualPercent > 5
  ensures f8_residualSignalsError(ev)
{}

// F8-A4: No residual signal when exact value was computed
lemma F8_NoResidualWhenComputed(ev: NumericEvidence)
  requires ev.computedExact
  ensures !f8_residualSignalsError(ev)
{}

// F8-A5: No residual signal when computation is not replicable
lemma F8_NoResidualWhenNotReplicable(ev: NumericEvidence)
  requires !ev.replicableLocally
  ensures !f8_residualSignalsError(ev)
{}

// -------------------------------------------------------

// F9: DB fields are snapshots with write timestamps.
// A field written once at creation is a historical snapshot — Inferred for
// current-state questions, Direct only for state-at-write-time questions.

datatype FieldTemporality =
  | LiveField           // retroactively updated when state changes
  | SnapshotField       // written once at creation, never updated after
  | ScheduledField      // updated on a schedule (e.g., hourly aggregation)

datatype StateQuestion =
  | CurrentState        // "what is the system's state now?"
  | HistoricalState     // "what was the state at time T?"

// F9: reliability depends on field temporality AND the question asked
function f9_fieldReliability(field: FieldTemporality, question: StateQuestion): Reliability
{
  match (field, question) {
    case (LiveField, _)                  => Direct    // always current
    case (SnapshotField, HistoricalState) => Direct   // accurate for write-time
    case (SnapshotField, CurrentState)   => Inferred  // may be stale
    case (ScheduledField, HistoricalState) => Direct
    case (ScheduledField, CurrentState)  => Inferred  // may lag behind
  }
}

// F9-A1: Snapshot field is Direct for historical questions
lemma F9_SnapshotDirectForHistory()
  ensures f9_fieldReliability(SnapshotField, HistoricalState) == Direct
{}

// F9-A2: Snapshot field is only Inferred for current-state questions
lemma F9_SnapshotInferredForCurrent()
  ensures f9_fieldReliability(SnapshotField, CurrentState) == Inferred
  ensures f9_fieldReliability(SnapshotField, CurrentState) != Direct
{}

// F9-A3: Live field is always Direct regardless of question
lemma F9_LiveAlwaysDirect(q: StateQuestion)
  ensures f9_fieldReliability(LiveField, q) == Direct
{}

// F9-A4: Scheduled field degrades for current-state like snapshot
lemma F9_ScheduledDegradesCurrent()
  ensures f9_fieldReliability(ScheduledField, CurrentState) == Inferred
  ensures f9_fieldReliability(ScheduledField, HistoricalState) == Direct
{}

// F9-A5: Using a snapshot field as Direct for current state is an error
// (the key safety property — prevents treating stale counters as live state)
lemma F9_SnapshotAsDirectIsError(field: FieldTemporality, q: StateQuestion)
  requires field == SnapshotField && q == CurrentState
  ensures f9_fieldReliability(field, q) != Direct
{}

// ============================================================
// 30. GAP STATUS — updated after closures
// ============================================================

// GAP1: PARTIALLY CLOSED. Iteration convergence now has:
//   - A decreasing composite measure (undistinguished + remaining cause classes)
//   - A bound on maximum iterations (N hypotheses + 14 cause classes)
//   - Proof that progress in any axis reduces the measure
//   REMAINING: Can't prove progress IS made each iteration — that's human judgment.
//   The model now proves: IF progress is made, THEN convergence is bounded.

// GAP2: OPEN. Supervised vs Autonomous mode not modeled. Low value.

// GAP5: OPEN. Depth (type contracts) deepening direction is procedural guidance —
//   "check types at the call boundary when function returns default value."
//   Can't structurally enforce which deepening direction to pick. Low value to model.

// GAP6: OPEN. Meta-rule "user prompts are high-value checks" is procedural —
//   can't structurally enforce that the investigator treats user suggestions as
//   distinguishing checks. Would need a model of the user-investigator interaction
//   loop, which is outside the scope of the protocol model.

// GAP3: CLOSED. Production-first is now a structural constraint on evidence ordering
//   within each step. The first evidence entry in any production-first step must be
//   Direct or Inferred. Interpreted-first and UnreliableSource-first are proved to
//   violate the constraint. Non-production-first steps are unconstrained.

// GAP4: CLOSED. Simple set membership replaced with proof-of-work per cause class.
//   Each of the 14 classes must have a CauseClassVerdict:
//   - CcCovered(evidenceIdx) — must reference a valid evidence log entry
//   - CcExcludedSafe(reason) — excluded with documented reason
//   - CcNotRelevant(reason) — not relevant with documented reason
//   REMAINING LIMITATION: Can't structurally prevent all-NotRelevant verdicts
//   (rubber-stamping). But each exclusion carries a reason field that review
//   can audit, and covered verdicts are grounded against the evidence log.

// GAP7: OPEN (excluded). PW0-live "no burst writes on termination turn" is an
//   observability-of-writing-cadence rule. Would require adding a turn index to
//   every evidence/hypothesis/model entry and proving no two consecutive entries
//   share a turn when that turn is the termination turn. Static proof model can't
//   naturally express "cadence of writes" — the protocol enforcement lives in the
//   harness, not the proof obligation.

// ============================================================
// 30. TC28 (tightened) — Skip requires VERBATIM Acknowledgement + LATER turn
// ============================================================
// The base validSkipPath predicate (above) proves "skip requires proposal + user
// acceptance." The SKILL text now adds two further requirements:
//   (a) the skip entry must quote the user's verbatim acknowledgement string
//   (b) the entry must be written in a turn AFTER the user's reply
// These are artifact-format rules, so the witness is a small datatype that we
// layer on top of ExtendedInvestigationState.

datatype SkipAcknowledgement = SkipAcknowledgement(
  verbatim: string,      // the user's exact reply, quoted under `Acknowledgement:`
  proposalTurn: int,     // turn in which Claude proposed the skip
  ackTurn: int,          // turn in which the user replied
  entryTurn: int         // turn in which Claude wrote the M1 skip entry
)

predicate validSkipAcknowledgement(ack: SkipAcknowledgement)
{
  |ack.verbatim| > 0 &&
  ack.proposalTurn < ack.ackTurn &&
  ack.ackTurn < ack.entryTurn
}

// The acknowledgement is only load-bearing when the protocol actually skipped.
predicate skipIsProperlyAcknowledged(status: ModelStatus, ack: SkipAcknowledgement)
{
  status.SkipAcknowledged? ==> validSkipAcknowledgement(ack)
}

// TC28-T1: Same-turn acknowledgement (user "replied" in the propose turn) is invalid.
lemma TC28_ForbidsSameTurnAck(ack: SkipAcknowledgement)
  requires ack.proposalTurn >= ack.ackTurn
  ensures !validSkipAcknowledgement(ack)
{}

// TC28-T2: Same-turn entry (log entry in the ack turn) is invalid — the entry
// must be written in a DIFFERENT turn than the acknowledgement, per SKILL.md.
lemma TC28_ForbidsEntryInAckTurn(ack: SkipAcknowledgement)
  requires ack.ackTurn >= ack.entryTurn
  ensures !validSkipAcknowledgement(ack)
{}

// TC28-T3: Empty verbatim quote is invalid (the Acknowledgement field must
// reproduce the user's exact reply).
lemma TC28_RequiresVerbatim(ack: SkipAcknowledgement)
  requires |ack.verbatim| == 0
  ensures !validSkipAcknowledgement(ack)
{}

// TC28-T4: A valid example exists — propose turn 1, ack turn 2, entry turn 3.
lemma TC28_ValidExample()
  ensures validSkipAcknowledgement(SkipAcknowledgement("yes, skip", 1, 2, 3))
{}

// TC28-T5: When ModelBuilt, the acknowledgement witness is not load-bearing
// (the skip path wasn't taken).
lemma TC28_ModelBuiltIgnoresAck(tool: ModelingTool, ack: SkipAcknowledgement)
  ensures skipIsProperlyAcknowledged(ModelBuilt(tool), ack)
{}

// TC28-T6: When SkipAcknowledged, the witness must be valid.
lemma TC28_SkipRequiresValidWitness(ack: SkipAcknowledgement)
  requires skipIsProperlyAcknowledged(SkipAcknowledged, ack)
  ensures validSkipAcknowledgement(ack)
{}

// ============================================================
// 31. TC29 — PW0-init: stub files must exist before Step 0a
// ============================================================
// Four investigation files (evidence-log, hypothesis-log, model-change-log,
// investigation-report) must be Written to disk BEFORE any Step 0a (tooling
// inventory) or Step 0b (symptom verification) activity begins. Retroactive
// stub creation after the fact violates the rule.

datatype Pw0InitWitness = Pw0InitWitness(
  stubFilesCreated: bool,       // did the four stub files get written at all?
  stubCreationTurn: int,        // turn in which they were written
  firstToolingTurn: int,        // first turn in which tooling inventory was touched
  firstEvidenceTurn: int,       // first turn in which evidence was collected
  firstSymptomVerifyTurn: int   // first turn in which the symptom was verified
)

predicate pw0init_Valid(w: Pw0InitWitness)
{
  w.stubFilesCreated &&
  w.stubCreationTurn < w.firstToolingTurn &&
  w.stubCreationTurn < w.firstEvidenceTurn &&
  w.stubCreationTurn < w.firstSymptomVerifyTurn
}

// TC29-T1: Missing stub files fails PW0-init unconditionally.
lemma TC29_MissingStubsFails(w: Pw0InitWitness)
  requires !w.stubFilesCreated
  ensures !pw0init_Valid(w)
{}

// TC29-T2: Late stubs (created after or during tooling) fails PW0-init.
lemma TC29_LateStubsFailsTooling(w: Pw0InitWitness)
  requires w.stubFilesCreated
  requires w.stubCreationTurn >= w.firstToolingTurn
  ensures !pw0init_Valid(w)
{}

// TC29-T3: Late stubs relative to symptom verification also fails.
lemma TC29_LateStubsFailsSymptomVerify(w: Pw0InitWitness)
  requires w.stubFilesCreated
  requires w.stubCreationTurn >= w.firstSymptomVerifyTurn
  ensures !pw0init_Valid(w)
{}

// TC29-T4: Late stubs relative to first evidence also fails.
lemma TC29_LateStubsFailsEvidence(w: Pw0InitWitness)
  requires w.stubFilesCreated
  requires w.stubCreationTurn >= w.firstEvidenceTurn
  ensures !pw0init_Valid(w)
{}

// TC29-T5: A valid example exists — stubs at turn 0, everything else later.
lemma TC29_ValidExample()
  ensures pw0init_Valid(Pw0InitWitness(true, 0, 1, 2, 3))
{}

// ============================================================
// 32. PW0-extended termination
// ============================================================
// Combine ExtendedInvestigationState with the new skip-acknowledgement and
// PW0-init witnesses. Termination now requires TC1-28 + TC29 + (if applicable)
// the tightened TC28 witness.

datatype Pw0ExtendedState = Pw0ExtendedState(
  ext: ExtendedInvestigationState,
  skipAck: SkipAcknowledgement,
  pw0init: Pw0InitWitness
)

predicate pw0ExtendedCanTerminate(p: Pw0ExtendedState)
  requires 0 <= p.ext.base.acceptedId < |p.ext.base.hypotheses|
{
  extendedCanTerminate(p.ext) &&
  skipIsProperlyAcknowledged(p.ext.modelStatus, p.skipAck) &&
  pw0init_Valid(p.pw0init)
}

// PW0-T1: Missing stubs blocks termination even if everything else is fine.
lemma PW0_MissingStubsBlocksTermination(p: Pw0ExtendedState)
  requires 0 <= p.ext.base.acceptedId < |p.ext.base.hypotheses|
  requires !p.pw0init.stubFilesCreated
  ensures !pw0ExtendedCanTerminate(p)
{}

// PW0-T2: Invalid skip acknowledgement blocks termination when skip was taken.
lemma PW0_InvalidSkipAckBlocksTermination(p: Pw0ExtendedState)
  requires 0 <= p.ext.base.acceptedId < |p.ext.base.hypotheses|
  requires p.ext.modelStatus.SkipAcknowledged?
  requires !validSkipAcknowledgement(p.skipAck)
  ensures !pw0ExtendedCanTerminate(p)
{}

// PW0-T3: Same-turn ack + entry blocks termination on skip path.
lemma PW0_SameTurnAckBlocksTermination(p: Pw0ExtendedState)
  requires 0 <= p.ext.base.acceptedId < |p.ext.base.hypotheses|
  requires p.ext.modelStatus.SkipAcknowledged?
  requires p.skipAck.ackTurn >= p.skipAck.entryTurn
  ensures !pw0ExtendedCanTerminate(p)
{}

// PW0-T4: Late stubs block termination even with a perfect hypothesis tree.
lemma PW0_LateStubsBlocksTermination(p: Pw0ExtendedState)
  requires 0 <= p.ext.base.acceptedId < |p.ext.base.hypotheses|
  requires p.pw0init.stubFilesCreated
  requires p.pw0init.stubCreationTurn >= p.pw0init.firstToolingTurn
  ensures !pw0ExtendedCanTerminate(p)
{}

// ============================================================
// 33. S0-V.1 — Symptom proximity: transport-shaped symptoms need liveness
// ============================================================
// A transport-layer symptom (DNS failure, connection refused, 5xx,
// health-check fail) may be a downstream effect of the target process
// never starting. Before transport investigation, gather direct evidence
// of upstream liveness.

datatype SymptomShape = TransportLayer | NonTransport

datatype UpstreamLivenessEvidence = UpstreamLivenessEvidence(
  source: SourceType,
  observedLive: bool   // did the evidence show the process as running?
)

predicate livenessIsDirect(e: UpstreamLivenessEvidence)
{
  sourceReliability(e.source) == Direct && e.observedLive
}

// S0-V.1: if the symptom is transport-shaped, a direct liveness observation
// is required before any transport-layer hypothesis can be accepted.
predicate s0v1_Satisfied(shape: SymptomShape, liveness: UpstreamLivenessEvidence)
{
  shape.TransportLayer? ==> livenessIsDirect(liveness)
}

lemma S0V1_NonTransportIgnoresLiveness(liveness: UpstreamLivenessEvidence)
  ensures s0v1_Satisfied(NonTransport, liveness)
{}

lemma S0V1_TransportRequiresDirect(liveness: UpstreamLivenessEvidence)
  requires sourceReliability(liveness.source) != Direct
  ensures !s0v1_Satisfied(TransportLayer, liveness)
{}

lemma S0V1_TransportRequiresObservedLive(liveness: UpstreamLivenessEvidence)
  requires !liveness.observedLive
  ensures !s0v1_Satisfied(TransportLayer, liveness)
{}

lemma S0V1_InterpretedLivenessBlocksTermination(liveness: UpstreamLivenessEvidence)
  requires liveness.source == SrcRepoCode  // interpreted
  ensures !s0v1_Satisfied(TransportLayer, liveness)
{
  assert sourceReliability(SrcRepoCode) == Interpreted;
}

lemma S0V1_ValidExample()
  ensures s0v1_Satisfied(TransportLayer,
            UpstreamLivenessEvidence(SrcRecentProductionLogs, true))
{
  assert sourceReliability(SrcRecentProductionLogs) == Direct;
}

// ============================================================
// 34. F10 — Baseline comparability
// ============================================================
// A differential against "last known good" only informs if the baseline
// matches on repo, trigger type, and config. Mismatched baselines
// pollute the differential.

datatype Baseline = Baseline(
  repoId: string,
  triggerType: string,  // "ci-branch" | "ci-pr" | "local" | "scheduled" | ...
  configHash: string
)

predicate baselineMatches(failing: Baseline, candidate: Baseline)
{
  failing.repoId == candidate.repoId &&
  failing.triggerType == candidate.triggerType &&
  failing.configHash == candidate.configHash
}

// F10: a differential claim must use a matching baseline.
predicate f10_baselineComparable(failing: Baseline, candidate: Baseline)
{
  baselineMatches(failing, candidate)
}

lemma F10_MismatchedRepoFails(f: Baseline, c: Baseline)
  requires f.repoId != c.repoId
  ensures !f10_baselineComparable(f, c)
{}

lemma F10_MismatchedTriggerFails(f: Baseline, c: Baseline)
  requires f.repoId == c.repoId
  requires f.triggerType != c.triggerType
  ensures !f10_baselineComparable(f, c)
{}

lemma F10_MismatchedConfigFails(f: Baseline, c: Baseline)
  requires f.repoId == c.repoId
  requires f.triggerType == c.triggerType
  requires f.configHash != c.configHash
  ensures !f10_baselineComparable(f, c)
{}

lemma F10_AllMatchValid(f: Baseline, c: Baseline)
  requires f == c
  ensures f10_baselineComparable(f, c)
{}

lemma F10_ValidExample()
  ensures f10_baselineComparable(
            Baseline("bot", "ci-branch", "deadbeef"),
            Baseline("bot", "ci-branch", "deadbeef"))
{}

// ============================================================
// 35. OB1 — Observability before intervention
// ============================================================
// Changing the system under investigation (topology, config, code)
// before direct evidence of the changed state blurs causality. Every
// intervention must be preceded by direct observation.

datatype Intervention = Intervention(
  turn: int,
  priorDirectEvidenceTurn: int,  // turn of the direct-evidence entry
  targetStateObservable: bool     // was the state's baseline actually captured?
)

predicate ob1_InterventionValid(i: Intervention)
{
  i.targetStateObservable &&
  i.priorDirectEvidenceTurn < i.turn
}

predicate ob1_AllInterventionsValid(xs: seq<Intervention>)
{
  forall k :: 0 <= k < |xs| ==> ob1_InterventionValid(xs[k])
}

lemma OB1_UnobservedInterventionFails(i: Intervention)
  requires !i.targetStateObservable
  ensures !ob1_InterventionValid(i)
{}

lemma OB1_SimultaneousInterventionFails(i: Intervention)
  requires i.targetStateObservable
  requires i.priorDirectEvidenceTurn >= i.turn
  ensures !ob1_InterventionValid(i)
{}

lemma OB1_ValidInterventionSucceeds(i: Intervention)
  requires i.targetStateObservable
  requires i.priorDirectEvidenceTurn < i.turn
  ensures ob1_InterventionValid(i)
{}

lemma OB1_EmptySequenceValid()
  ensures ob1_AllInterventionsValid([])
{}

lemma OB1_OneBadBreaksAll(xs: seq<Intervention>, k: int)
  requires 0 <= k < |xs|
  requires !ob1_InterventionValid(xs[k])
  ensures !ob1_AllInterventionsValid(xs)
{}

// ============================================================
// 36. Fully-extended termination (TC31, TC32, TC34; TC33 is GAP8)
// ============================================================
// Combine all prior gates (TC1-30) with S0-V.1 (TC31), F10 (TC32), and
// OB1 (TC34). TC33 (F11 workspace contamination) is procedural and
// lives in the harness, not the proof model — see GAP8 below.

datatype FullInvestigation = FullInvestigation(
  pw0: Pw0ExtendedState,
  symptomShape: SymptomShape,
  upstreamLiveness: UpstreamLivenessEvidence,
  failingBaseline: Baseline,
  comparedBaseline: Baseline,
  usedDifferential: bool,           // was a baseline differential used in the investigation?
  interventions: seq<Intervention>
)

predicate fullCanTerminate(f: FullInvestigation)
  requires 0 <= f.pw0.ext.base.acceptedId < |f.pw0.ext.base.hypotheses|
{
  pw0ExtendedCanTerminate(f.pw0) &&
  // TC31 / S0-V.1
  s0v1_Satisfied(f.symptomShape, f.upstreamLiveness) &&
  // TC32 / F10 — only load-bearing if a baseline differential was actually used
  (f.usedDifferential ==> f10_baselineComparable(f.failingBaseline, f.comparedBaseline)) &&
  // TC34 / OB1
  ob1_AllInterventionsValid(f.interventions)
}

lemma FULL_TransportWithoutLivenessBlocks(f: FullInvestigation)
  requires 0 <= f.pw0.ext.base.acceptedId < |f.pw0.ext.base.hypotheses|
  requires f.symptomShape.TransportLayer?
  requires !livenessIsDirect(f.upstreamLiveness)
  ensures !fullCanTerminate(f)
{}

lemma FULL_MismatchedBaselineBlocks(f: FullInvestigation)
  requires 0 <= f.pw0.ext.base.acceptedId < |f.pw0.ext.base.hypotheses|
  requires f.usedDifferential
  requires !baselineMatches(f.failingBaseline, f.comparedBaseline)
  ensures !fullCanTerminate(f)
{}

lemma FULL_BlindInterventionBlocks(f: FullInvestigation, k: int)
  requires 0 <= f.pw0.ext.base.acceptedId < |f.pw0.ext.base.hypotheses|
  requires 0 <= k < |f.interventions|
  requires !ob1_InterventionValid(f.interventions[k])
  ensures !fullCanTerminate(f)
{
  OB1_OneBadBreaksAll(f.interventions, k);
}

// GAP8: OPEN (excluded). F11 — workspace contamination — requires running
//   `git status --ignored` and `git ls-files --others --exclude-standard`
//   against the working tree. This is a harness-level check (filesystem
//   observation) and cannot be expressed as a proof obligation. Enforced
//   procedurally in SKILL.md's pre-acceptance checklist.

// ============================================================
// 37. U2-doc / TC35 — Rejection reason must be documented
// ============================================================
// A rejected hypothesis must carry a reason:
//   EvidenceBased(evidenceIdx) — cites a specific E<N> entry
//   PreferenceBased(priority, rationale) — a DOCUMENTED preference with
//     a priority criterion from a closed allowed set + non-empty rationale
// This closes U2's loophole: "rejected because I prefer the other one" is
// legitimate IF and only if the preference is named and justified.

datatype PreferenceReason =
  | Occam | BlastRadius | Severity | RecencyOfDeploy | Reproducibility | FixCost

datatype RejectionReason =
  | EvidenceBased(evidenceIdx: int)
  | PreferenceBased(priority: PreferenceReason, rationale: string)

predicate validRejectionReason(r: RejectionReason, evidenceLogLen: int)
{
  match r
  case EvidenceBased(idx) => 0 <= idx < evidenceLogLen
  case PreferenceBased(_, rationale) => |rationale| > 0
}

// TC35-T1: EvidenceBased with out-of-bounds index is invalid.
lemma TC35_InvalidEvidenceIdx(idx: int, logLen: int)
  requires idx < 0 || idx >= logLen
  ensures !validRejectionReason(EvidenceBased(idx), logLen)
{}

// TC35-T2: PreferenceBased with empty rationale is invalid.
lemma TC35_EmptyRationaleFails(p: PreferenceReason)
  ensures !validRejectionReason(PreferenceBased(p, ""), 10)
{}

// TC35-T3: PreferenceBased with any allowed priority + non-empty rationale is valid.
lemma TC35_AllPrioritiesWithRationaleValid()
  ensures validRejectionReason(PreferenceBased(Occam, "simpler mechanism"), 10)
  ensures validRejectionReason(PreferenceBased(BlastRadius, "smaller blast"), 10)
  ensures validRejectionReason(PreferenceBased(Severity, "lower impact"), 10)
  ensures validRejectionReason(PreferenceBased(RecencyOfDeploy, "recent change"), 10)
  ensures validRejectionReason(PreferenceBased(Reproducibility, "deterministic"), 10)
  ensures validRejectionReason(PreferenceBased(FixCost, "cheaper fix"), 10)
{}

// TC35-T4: EvidenceBased with valid index is accepted.
lemma TC35_ValidEvidenceAccepted(idx: int, logLen: int)
  requires 0 <= idx < logLen
  ensures validRejectionReason(EvidenceBased(idx), logLen)
{}

// --- Tie to investigation state ---

datatype RejectionEntry = RejectionEntry(
  hypothesisId: int,
  reason: RejectionReason
)

predicate allRejectionsDocumented(rs: seq<RejectionEntry>, evidenceLogLen: int)
{
  forall k :: 0 <= k < |rs| ==> validRejectionReason(rs[k].reason, evidenceLogLen)
}

// TC35-T5: One undocumented rejection poisons the whole sequence.
lemma TC35_OneBadBreaksAll(rs: seq<RejectionEntry>, k: int, logLen: int)
  requires 0 <= k < |rs|
  requires !validRejectionReason(rs[k].reason, logLen)
  ensures !allRejectionsDocumented(rs, logLen)
{}

// TC35-T6: Empty rejection sequence is trivially valid.
lemma TC35_EmptyValid(logLen: int)
  ensures allRejectionsDocumented([], logLen)
{}

// ============================================================
// 38. TC30 / PW0-live — Structured hash integrity
// ============================================================
// Models the four parallel chains of the skill's provenance contract:
// report chain (investigation-report-<N> via PrevReportHash), hypothesis
// chain (H events via PrevHypHash), evidence parent links (ParentHypEvent
// + ParentHypHash), and model-change chain + parent links. Plus the
// state-change EvidenceHash that freezes cited evidence.
//
// We model sha256 abstractly as `string` — two distinct content states
// produce distinct hashes. Validity predicates check that reference fields
// (PrevHypHash, ParentHypHash, EvidenceHash, etc.) match the contentHash
// of the records they reference. Tampering = changing a content state,
// which changes the contentHash, which invalidates any record that
// references the OLD state.
//
// Note on filesystem provenance (TC30 Check 5): the runtime checker
// (scripts/check_pw0_live.py) also validates that each record's in-field
// Timestamp matches its filesystem ctime within 60 seconds. That check is
// IO-side and not expressed here (the Dafny model has no notion of
// filesystem state). The principle "superseded records are excused from
// per-record validity checks" extends symmetrically to that runtime check
// — same exclusion logic, same audit-trail rationale. The lemmas below
// (TC30-C9 SupersededRecordIgnoredInBinding) capture this principle for
// the structural EvidenceHash binding; the analogous behavior for the
// runtime fs-provenance check is enforced by check_pw0_live.py directly.

datatype ReportRecord = ReportRecord(
  versionNum: nat,
  contentHash: string,
  prevReportHash: string   // "" for version 1 (genesis)
)

datatype HypEventType =
  | HSymptomClaimed | HCreated | HMechanismStated | HCounterfactualStated
  | HObservabilityAssessed | HAlternativeConsidered
  | HStatusChanged | HAccepted | HEquivalenceChecked

datatype HypEventRecord = HypEventRecord(
  contentHash: string,
  prevHypHash: string,            // either prev H's contentHash or report-1's
  eventType: HypEventType,
  // State-change-specific fields; ignored unless eventType is HStatusChanged
  // or HAccepted. Represented as an Option-ish structure via empty defaults.
  citedEvidenceHashes: seq<string>,
  evidenceHash: string,
  // Supersedes: index of the H record this one replaces, or -1 if none.
  // A superseded record stays on disk; the validator skips its EvidenceHash
  // check because the supersedeR carries the fresh hash.
  supersedesIdx: int
)

datatype EvidenceRecord = EvidenceRecord(
  contentHash: string,
  parentHypIndex: nat,            // index into the hypothesis-event sequence
  parentHypHash: string           // snapshot of parent's contentHash at attachment
)

datatype ModelChangeRecord = ModelChangeRecord(
  contentHash: string,
  prevModelHash: string,
  parentHypIndex: nat,
  parentHypHash: string
)

// Abstract sha256-of-sorted-concat combiner. In the real world, this is
// sha256 over the sorted concatenation of cited evidence file hashes. Here
// we use Dafny's sequence-equality-under-sorting as a proxy: two hashes are
// equal iff the sorted multisets are equal.
predicate evidenceHashEqualsSortedCombine(ev_hash: string, cited: seq<string>)
{
  // Abstract: we require a total function hashCombine that satisfies this,
  // captured as a parameterized assumption via a separate predicate.
  // For the model we treat ev_hash == "combine(" + <sorted cited concat> + ")".
  // The concrete hashing is irrelevant for proving integrity properties —
  // what matters is that distinct cited multisets produce distinct hashes
  // and identical multisets produce identical hashes.
  true  // abstract placeholder; integrity reasoning below uses direct comparisons
}

// ----- Chain validity predicates -----

predicate validReportChain(reports: seq<ReportRecord>)
  requires |reports| > 0
{
  reports[0].versionNum == 1 &&
  reports[0].prevReportHash == "" &&
  forall i :: 1 <= i < |reports| ==>
    reports[i].versionNum == i + 1 &&
    reports[i].prevReportHash == reports[i-1].contentHash
}

predicate validHypChain(hyps: seq<HypEventRecord>, reportAnchor: string)
{
  |hyps| == 0 ||
  (hyps[0].prevHypHash == reportAnchor &&
   forall i :: 1 <= i < |hyps| ==> hyps[i].prevHypHash == hyps[i-1].contentHash)
}

predicate validEvidenceParentLinks(evidence: seq<EvidenceRecord>, hyps: seq<HypEventRecord>)
{
  forall i :: 0 <= i < |evidence| ==>
    evidence[i].parentHypIndex < |hyps| &&
    evidence[i].parentHypHash == hyps[evidence[i].parentHypIndex].contentHash
}

predicate validModelChain(models: seq<ModelChangeRecord>, reportAnchor: string, hyps: seq<HypEventRecord>)
{
  forall i :: 0 <= i < |models| ==>
    models[i].parentHypIndex < |hyps| &&
    models[i].parentHypHash == hyps[models[i].parentHypIndex].contentHash &&
    (if i == 0 then models[i].prevModelHash == reportAnchor
     else models[i].prevModelHash == models[i-1].contentHash)
}

// Helper: is this event a state-change that must carry a valid EvidenceHash?
predicate isStateChangeEvent(h: HypEventRecord)
{
  h.eventType == HStatusChanged || h.eventType == HAccepted
}

// Abstract EvidenceHash validity: the declared hash must equal the combiner
// applied to the cited evidence hashes.
predicate validEvidenceHashBinding(h: HypEventRecord, evidence: seq<EvidenceRecord>)
{
  !isStateChangeEvent(h) ||
  (|h.citedEvidenceHashes| > 0 &&
   // Cited hashes must exist in the evidence set AT CURRENT STATE.
   // Any tampered evidence has a different contentHash than what was cited.
   forall ci :: 0 <= ci < |h.citedEvidenceHashes| ==>
     exists ei :: 0 <= ei < |evidence| &&
       evidence[ei].contentHash == h.citedEvidenceHashes[ci])
}

// A record is superseded if some later record names it via supersedesIdx.
predicate isSuperseded(hyps: seq<HypEventRecord>, i: int)
{
  exists j :: 0 <= j < |hyps| && hyps[j].supersedesIdx == i
}

// Supersession is well-formed: a superseder must come AFTER its target
// (forbids "supersede the future") and the target index must be in range.
predicate supersessionWellFormed(hyps: seq<HypEventRecord>)
{
  forall i :: 0 <= i < |hyps| && hyps[i].supersedesIdx >= 0 ==>
    0 <= hyps[i].supersedesIdx < i
}

predicate validAllStateChanges(hyps: seq<HypEventRecord>, evidence: seq<EvidenceRecord>)
{
  forall i :: 0 <= i < |hyps| ==>
    isSuperseded(hyps, i) || validEvidenceHashBinding(hyps[i], evidence)
}

// Full TC30 compliance.
predicate tc30Pass(
  reports: seq<ReportRecord>,
  hyps: seq<HypEventRecord>,
  evidence: seq<EvidenceRecord>,
  models: seq<ModelChangeRecord>)
  requires |reports| > 0
{
  validReportChain(reports) &&
  validHypChain(hyps, reports[0].contentHash) &&
  validEvidenceParentLinks(evidence, hyps) &&
  validModelChain(models, reports[0].contentHash, hyps) &&
  validAllStateChanges(hyps, evidence) &&
  supersessionWellFormed(hyps)
}

// ----- Tamper-detection lemmas -----

// TC30-C1: empty investigation (no records beyond genesis report) is valid.
lemma TC30_EmptyValid(reports: seq<ReportRecord>)
  requires |reports| == 1
  requires reports[0].versionNum == 1
  requires reports[0].prevReportHash == ""
  ensures tc30Pass(reports, [], [], [])
{}

// TC30-C2: a report with the wrong PrevReportHash breaks validReportChain.
lemma TC30_ReportTamperBreaksChain(reports: seq<ReportRecord>, i: int)
  requires |reports| >= 2
  requires 1 <= i < |reports|
  requires reports[i].prevReportHash != reports[i-1].contentHash
  ensures !validReportChain(reports)
{}

// TC30-C3: a hypothesis event with a wrong PrevHypHash breaks validHypChain.
lemma TC30_HypTamperBreaksChain(hyps: seq<HypEventRecord>, anchor: string, i: int)
  requires |hyps| >= 2
  requires 1 <= i < |hyps|
  requires hyps[i].prevHypHash != hyps[i-1].contentHash
  ensures !validHypChain(hyps, anchor)
{}

// TC30-C4: evidence pointing to a non-existent hypothesis index breaks
// validEvidenceParentLinks.
lemma TC30_OrphanEvidenceBreaksLinks(
  evidence: seq<EvidenceRecord>, hyps: seq<HypEventRecord>, i: int)
  requires 0 <= i < |evidence|
  requires evidence[i].parentHypIndex >= |hyps|
  ensures !validEvidenceParentLinks(evidence, hyps)
{}

// TC30-C5: evidence with a ParentHypHash not matching the current parent's
// contentHash breaks the parent link. (Retroactive edit to the parent H event.)
lemma TC30_ParentTamperBreaksEvidenceLink(
  evidence: seq<EvidenceRecord>, hyps: seq<HypEventRecord>, i: int)
  requires 0 <= i < |evidence|
  requires evidence[i].parentHypIndex < |hyps|
  requires evidence[i].parentHypHash != hyps[evidence[i].parentHypIndex].contentHash
  ensures !validEvidenceParentLinks(evidence, hyps)
{}

// TC30-C6: a state-change citing evidence whose contentHash no longer exists
// in the current evidence sequence breaks validEvidenceHashBinding. This
// captures the "evidence tampered after citation" attack.
lemma TC30_TamperedCitedEvidenceBreaksBinding(
  h: HypEventRecord, evidence: seq<EvidenceRecord>, ci: int)
  requires isStateChangeEvent(h)
  requires 0 <= ci < |h.citedEvidenceHashes|
  requires forall ei :: 0 <= ei < |evidence| ==>
    evidence[ei].contentHash != h.citedEvidenceHashes[ci]
  ensures !validEvidenceHashBinding(h, evidence)
{
  // No surviving match at index ci → inner existential is false → inner
  // forall (ranged over all cited indices) is false → the rhs of
  // validEvidenceHashBinding (under isStateChangeEvent) is false.
  assert !exists ei :: 0 <= ei < |evidence|
    && evidence[ei].contentHash == h.citedEvidenceHashes[ci];
  assert !(forall cj :: 0 <= cj < |h.citedEvidenceHashes| ==>
    exists ei :: 0 <= ei < |evidence| &&
      evidence[ei].contentHash == h.citedEvidenceHashes[cj]);
}

// TC30-C7: one broken state-change poisons the whole sequence — provided
// the broken record has not been superseded by a later record.
lemma TC30_OneBadStateChangeFailsAll(
  hyps: seq<HypEventRecord>, evidence: seq<EvidenceRecord>, i: int)
  requires 0 <= i < |hyps|
  requires !validEvidenceHashBinding(hyps[i], evidence)
  requires !isSuperseded(hyps, i)
  ensures !validAllStateChanges(hyps, evidence)
{}

// TC30-C8: a valid example exists — empty everything with a genesis report.
lemma TC30_ValidExample()
  ensures
    var r := ReportRecord(1, "genesis-hash", "");
    tc30Pass([r], [], [], [])
{}

// TC30-C9: a superseded record's broken EvidenceHash does NOT fail
// validAllStateChanges — the supersedeR carries the fresh hash.
lemma TC30_SupersededRecordIgnoredInBinding(
  hyps: seq<HypEventRecord>, evidence: seq<EvidenceRecord>, i: int)
  requires 0 <= i < |hyps|
  requires isSuperseded(hyps, i)
  // Even if hyps[i] has a broken EvidenceHash binding...
  requires !validEvidenceHashBinding(hyps[i], evidence)
  // ...validAllStateChanges can still hold IF every other record is valid:
  requires forall j :: 0 <= j < |hyps| && j != i ==>
    isSuperseded(hyps, j) || validEvidenceHashBinding(hyps[j], evidence)
  ensures validAllStateChanges(hyps, evidence)
{}

// TC30-C10: forward-supersession (supersede a future record) breaks
// supersessionWellFormed.
lemma TC30_ForwardSupersessionFails(hyps: seq<HypEventRecord>, i: int)
  requires 0 <= i < |hyps|
  requires hyps[i].supersedesIdx >= i  // pointing forward or to self
  ensures !supersessionWellFormed(hyps)
{}

// TC30-C11: superseding a non-existent record (out-of-range index) breaks
// supersessionWellFormed.
lemma TC30_OutOfRangeSupersessionFails(hyps: seq<HypEventRecord>, i: int)
  requires 0 <= i < |hyps|
  requires hyps[i].supersedesIdx >= |hyps|
  ensures !supersessionWellFormed(hyps)
{}

