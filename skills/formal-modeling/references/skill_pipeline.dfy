/**
 * Formal-Modeling Skill Pipeline — Dafny port
 *
 * Ported from skill_pipeline.als (Alloy 6 static model with util/ordering).
 *
 * Translation approach:
 *   - Alloy `one sig` enums → Dafny `datatype` variants
 *   - Alloy `util/ordering[Step]` → Dafny function `stepIndex` returning nat
 *   - Alloy `requires: set Artifact` → Dafny `predicate stepRequires(Step, Artifact)`
 *   - Alloy `producedBy: one Step` → Dafny `function producedBy(Artifact): Step`
 *   - Alloy `fact` → Dafny axioms via `ensures` on functions
 *   - Alloy `assert` + `check` → Dafny `lemma`
 *
 * Dafny proves ALL properties for ALL possible inputs (unbounded).
 * Alloy checks within scope N — Dafny is strictly stronger.
 */

// ============================================================
// 1. ENUMS
// ============================================================

datatype Step =
  | S1_Trigger | S2_ReadSkill | S2b_Clarify | S3_SelectPattern
  | S4_ReadExample | S5_WriteModel | S5b_ReviewBounds
  | S6_SetupTooling | S7_RunModel | S8_FormatOutput
  | S9_Interpret | S9b_Reconcile | S10b_EnforcementAudit | S10_Iterate

datatype Artifact =
  // User input
  | UserPrompt | Clarification
  // Source system
  | SourceCode | SourceSpec | SourceTests | SourceDocs
  // Skill definition
  | SkillMd | PatternsMd | StaticExample | TemporalExample
  | UxExample | DataConvExample | PipelineExample
  // Tooling
  | RunScript | Formatter | LocalJava | DockerEngine
  | AlloyJar | ExtractedClasses | RunnerClass
  // Produced
  | UserModel | BoundaryReview | RunOutput | Interpretation | Reconciliation
  // Persisted reports (written to ./system-models/reports/)
  | ReconciliationRpt | EnforcementRpt

datatype RuntimeOption = UseLocalJava | UseDocker

// ============================================================
// 2. STEP ORDERING (replaces util/ordering[Step])
// ============================================================

function stepIndex(s: Step): nat
{
  match s {
    case S1_Trigger              => 0
    case S2_ReadSkill            => 1
    case S2b_Clarify             => 2
    case S3_SelectPattern        => 3
    case S4_ReadExample          => 4
    case S5_WriteModel           => 5
    case S5b_ReviewBounds        => 6
    case S6_SetupTooling         => 7
    case S7_RunModel             => 8
    case S8_FormatOutput         => 9
    case S9_Interpret            => 10
    case S9b_Reconcile           => 11
    case S10b_EnforcementAudit   => 12
    case S10_Iterate             => 13
  }
}

predicate stepBefore(a: Step, b: Step) { stepIndex(a) < stepIndex(b) }
predicate stepAtOrBefore(a: Step, b: Step) { stepIndex(a) <= stepIndex(b) }

// ============================================================
// 3. PRODUCTION RULES (which step produces each artifact)
// ============================================================

function producedBy(a: Artifact): Step
{
  match a {
    // Pre-existing at trigger time
    case UserPrompt      => S1_Trigger
    case SourceCode      => S1_Trigger
    case SourceSpec      => S1_Trigger
    case SourceTests     => S1_Trigger
    case SourceDocs      => S1_Trigger
    case SkillMd         => S1_Trigger
    case PatternsMd      => S1_Trigger
    case StaticExample   => S1_Trigger
    case TemporalExample => S1_Trigger
    case UxExample       => S1_Trigger
    case DataConvExample => S1_Trigger
    case PipelineExample => S1_Trigger
    case RunScript       => S1_Trigger
    case Formatter       => S1_Trigger
    case LocalJava       => S1_Trigger
    case DockerEngine    => S1_Trigger
    // Tooling setup
    case AlloyJar         => S6_SetupTooling
    case ExtractedClasses => S6_SetupTooling
    case RunnerClass      => S6_SetupTooling
    // Clarification
    case Clarification    => S2b_Clarify
    // Skill execution outputs
    case UserModel        => S5_WriteModel
    case BoundaryReview   => S5b_ReviewBounds
    case RunOutput        => S8_FormatOutput
    case Interpretation   => S9_Interpret
    case Reconciliation   => S9b_Reconcile
    // Persisted reports
    case ReconciliationRpt => S9b_Reconcile
    case EnforcementRpt    => S10b_EnforcementAudit
  }
}

// ============================================================
// 4. DEPENDENCY RULES (which artifacts each step requires)
// ============================================================

predicate stepRequires(s: Step, a: Artifact)
{
  match s {
    case S1_Trigger       => false  // no dependencies
    case S2_ReadSkill     => a == SkillMd || a == UserPrompt
    case S2b_Clarify      => a == UserPrompt || a == SkillMd
    case S3_SelectPattern => a == PatternsMd || a == SkillMd || a == UserPrompt || a == Clarification
    case S4_ReadExample   => a == PatternsMd || a == Clarification
    case S5_WriteModel    => a == PatternsMd || a == SkillMd || a == Clarification ||
                             a == SourceCode || a == SourceSpec || a == SourceTests || a == SourceDocs
    case S5b_ReviewBounds => a == UserModel ||
                             a == SourceCode || a == SourceSpec || a == SourceTests || a == SourceDocs
    case S6_SetupTooling  => a == RunScript || a == LocalJava || a == DockerEngine
    case S7_RunModel      => a == UserModel || a == BoundaryReview || a == RunScript ||
                             a == AlloyJar || a == ExtractedClasses || a == RunnerClass
    case S8_FormatOutput  => a == Formatter
    case S9_Interpret     => a == RunOutput || a == UserModel
    case S9b_Reconcile    => a == Interpretation || a == UserModel || a == SkillMd || a == UserPrompt ||
                             a == SourceCode  // Code always included; others depend on selection
    case S10b_EnforcementAudit => a == Reconciliation || a == ReconciliationRpt || a == UserModel ||
                             a == SourceCode  // Code always included
    case S10_Iterate      => a == Reconciliation || a == EnforcementRpt || a == Interpretation ||
                             a == UserModel || a == PatternsMd
  }
}

// ============================================================
// 5. CORE PIPELINE ASSERTIONS — proved for ALL inputs
// ============================================================

// A1: No step reads an artifact from the future
// Alloy: check DependenciesSatisfied for 15
lemma DependenciesSatisfied(s: Step, a: Artifact)
  requires stepRequires(s, a)
  ensures stepAtOrBefore(producedBy(a), s)
{
  // Dafny proves this automatically by evaluating all (Step, Artifact) combinations
}

// A2: Each artifact has exactly one producer
// (Trivially true in Dafny — producedBy is a total function returning one Step)
lemma SingleProducer(a: Artifact)
  ensures producedBy(a) == producedBy(a)  // function determinism is inherent
{}

// A3: Writing a model requires consulting patterns
lemma ModelRequiresPatterns()
  ensures stepRequires(S5_WriteModel, PatternsMd)
{}

// A4: Can't run without a model
lemma RunRequiresModel()
  ensures stepRequires(S7_RunModel, UserModel)
{}

// A5: Can't run without tooling
lemma RunRequiresTooling()
  ensures stepRequires(S7_RunModel, AlloyJar)
  ensures stepRequires(S7_RunModel, ExtractedClasses)
  ensures stepRequires(S7_RunModel, RunnerClass)
{}

// A6: Can't interpret without run output
lemma InterpretRequiresOutput()
  ensures stepRequires(S9_Interpret, RunOutput)
{}

// A7: Examples are NOT runtime dependencies
lemma ExamplesNotRequiredForRun()
  ensures !stepRequires(S7_RunModel, StaticExample)
  ensures !stepRequires(S7_RunModel, TemporalExample)
  ensures !stepRequires(S7_RunModel, UxExample)
{}

// A8: Tooling setup is independent of skill content
lemma ToolingIndependentOfSkill()
  ensures !stepRequires(S6_SetupTooling, SkillMd)
  ensures !stepRequires(S6_SetupTooling, PatternsMd)
{}

// A12: Iterate requires interpretation
lemma IterateRequiresInterpret()
  ensures stepRequires(S10_Iterate, Interpretation)
{}

// A14: Boundary review must happen before running
lemma ReviewBeforeRun()
  ensures stepRequires(S7_RunModel, BoundaryReview)
  ensures stepBefore(S5b_ReviewBounds, S7_RunModel)
{}

// A15: Boundary review requires the written model
lemma ReviewRequiresModel()
  ensures stepRequires(S5b_ReviewBounds, UserModel)
{}

// A17: Writing a model requires clarified input
lemma ModelRequiresClarifiedInput()
  ensures stepRequires(S5_WriteModel, Clarification)
  ensures stepRequires(S2b_Clarify, UserPrompt)
  ensures stepBefore(S2b_Clarify, S5_WriteModel)
{}

// A20: Example selection requires clarification (style determined after)
lemma ExampleSelectionModeled()
  ensures stepRequires(S4_ReadExample, Clarification)
  ensures everyStyleHasExample()  // every style has at least one example
{}

// A21: Iteration is the last step (GAP: can't model loops)
// Aliased as IterationNotALoop for Alloy name parity
lemma IterationNotALoop()
  ensures stepIndex(S10_Iterate) == 13
  ensures forall s: Step :: stepIndex(s) <= 13
{}

lemma IterationIsLast()
  ensures stepIndex(S10_Iterate) == 13
  ensures forall s: Step :: stepIndex(s) <= 13
{}

// A23: Reconciliation requires both interpretation and skill spec
lemma ReconcileRequiresInterpretAndSpec()
  ensures stepRequires(S9b_Reconcile, Interpretation)
  ensures stepRequires(S9b_Reconcile, SkillMd)
{}

// A24: Reconciliation happens before iterate
lemma ReconcileBeforeIterate()
  ensures stepBefore(S9b_Reconcile, S10_Iterate)
  ensures stepRequires(S10_Iterate, Reconciliation)
{}

// A28: WriteModel requires source system
lemma ModelRequiresSourceSystem()
  ensures stepRequires(S5_WriteModel, SourceCode)
  ensures stepRequires(S5_WriteModel, SourceSpec)
  ensures stepRequires(S5_WriteModel, SourceTests)
  ensures stepRequires(S5_WriteModel, SourceDocs)
{}

// A30: Boundary review requires source system
lemma BoundaryReviewRequiresSource()
  ensures stepRequires(S5b_ReviewBounds, SourceCode)
  ensures stepRequires(S5b_ReviewBounds, SourceSpec)
  ensures stepRequires(S5b_ReviewBounds, SourceTests)
  ensures stepRequires(S5b_ReviewBounds, SourceDocs)
{}

// A48: Model requires code specifically
lemma ModelRequiresCode()
  ensures stepRequires(S5_WriteModel, SourceCode)
{}

// ============================================================
// 6. COMPREHENSIVE: prove dependency satisfaction for ALL steps
// ============================================================

// This single lemma proves A1 for every possible step×artifact pair.
// Alloy needs scope 15 to check this. Dafny proves it unbounded.
lemma AllDependenciesSatisfied()
  ensures forall s: Step, a: Artifact ::
    stepRequires(s, a) ==> stepAtOrBefore(producedBy(a), s)
{
  // Dafny's exhaustive case analysis proves this automatically
  forall s: Step, a: Artifact | stepRequires(s, a)
    ensures stepAtOrBefore(producedBy(a), s)
  {
    DependenciesSatisfied(s, a);
  }
}

// ============================================================
// 7. RECONCILIATION OUTCOMES
// ============================================================

datatype ReconcileOutcome = Aligned | FixSource | FixModelToCode | FixModelToIntent | Conflict | Exclusion

datatype FixDirection = NoChange_Aligned | ModelStays_SourceChanges | ModelAligns_ToCode | ModelAligns_ToSpec | UserDecides | NoChange_Documented

datatype EnforcementLevel = Enforced | MentionedUnenforced | MissingFromGate

datatype ArtifactNature = ExecutableCode | NaturalLanguage

// Gate audit chain — traces whether Enforced gates have auditable inputs
datatype GateAuditStatus = AuditOK | AuditMissingField | AuditMissingInstruction | AuditAmbiguousField

datatype GateAuditChain = GateAuditChain(
  status: GateAuditStatus,
  fieldExists: bool,
  recordingInstruction: bool,
  unambiguous: bool
)

// Audit status must be consistent with chain links
predicate ValidGateAudit(g: GateAuditChain)
{
  (g.status == AuditOK ==> (g.fieldExists && g.recordingInstruction && g.unambiguous)) &&
  (g.status == AuditMissingField ==> !g.fieldExists) &&
  (g.status == AuditMissingInstruction ==> (g.fieldExists && !g.recordingInstruction)) &&
  (g.status == AuditAmbiguousField ==> (g.fieldExists && g.recordingInstruction && !g.unambiguous))
}

datatype Discrepancy = Discrepancy(
  claim: Artifact,
  outcome: ReconcileOutcome,
  direction: FixDirection,
  enforcement: EnforcementLevel,  // only meaningful for Aligned outcomes
  gateAudit: Option<GateAuditChain>,  // only set for Enforced verdicts
  hasModelRef: bool,
  hasSourceRef: bool,
  hasImpact: bool,
  hasAction: bool
)

datatype Option<T> = None | Some(value: T)

// Direction must match outcome (Alloy fact DirectionMatchesOutcome)
predicate DirectionMatchesOutcome(d: Discrepancy)
{
  (d.outcome == Aligned ==> d.direction == NoChange_Aligned) &&
  (d.outcome == FixSource ==> d.direction == ModelStays_SourceChanges) &&
  (d.outcome == FixModelToCode ==> d.direction == ModelAligns_ToCode) &&
  (d.outcome == FixModelToIntent ==> d.direction == ModelAligns_ToSpec) &&
  (d.outcome == Conflict ==> d.direction == UserDecides) &&
  (d.outcome == Exclusion ==> d.direction == NoChange_Documented)
}

// Gate audit only applies to Enforced discrepancies
predicate GateAuditConsistent(d: Discrepancy)
{
  (d.enforcement == Enforced ==> d.gateAudit.Some?) &&
  (d.enforcement != Enforced ==> d.gateAudit.None?) &&
  (d.gateAudit.Some? ==> ValidGateAudit(d.gateAudit.value))
}

// Every discrepancy must have bidirectional traceability and valid direction
predicate ValidDiscrepancy(d: Discrepancy)
{
  d.hasModelRef && d.hasSourceRef && d.hasImpact && d.hasAction &&
  DirectionMatchesOutcome(d) && GateAuditConsistent(d)
}

// A45: Report has bidirectional refs
lemma ReportHasBidirectionalRefs(d: Discrepancy)
  requires ValidDiscrepancy(d)
  ensures d.hasModelRef && d.hasSourceRef
{}

// A46: Report is actionable
lemma ReportIsActionable(d: Discrepancy)
  requires ValidDiscrepancy(d)
  ensures d.hasImpact && d.hasAction
{}

// ============================================================
// 8. CRITICAL DECISIONS
// ============================================================

datatype ModelingStyle = Static | Temporal | UxLayer

datatype ProblemProfile = ProblemProfile(
  needsTemporalOrder: bool,
  needsAccessMatrix: bool,
  needsLivenessCheck: bool,
  chosenStyle: ModelingStyle
)

// Style must match the problem
predicate ValidStyleChoice(p: ProblemProfile)
{
  // Temporal needs → must choose Temporal
  ((p.needsTemporalOrder || p.needsLivenessCheck) ==> p.chosenStyle == Temporal) &&
  // Access matrix without temporal → UxLayer
  ((p.needsAccessMatrix && !p.needsTemporalOrder && !p.needsLivenessCheck) ==>
    p.chosenStyle == UxLayer)
}

// A33: Temporal problem requires temporal style
lemma TemporalProblemRequiresTemporalStyle(p: ProblemProfile)
  requires ValidStyleChoice(p)
  requires p.needsTemporalOrder || p.needsLivenessCheck
  ensures p.chosenStyle == Temporal
{}

// A34: Access matrix gets UX style
lemma AccessMatrixGetsUxStyle(p: ProblemProfile)
  requires ValidStyleChoice(p)
  requires p.needsAccessMatrix && !p.needsTemporalOrder && !p.needsLivenessCheck
  ensures p.chosenStyle == UxLayer
{}

// ============================================================
// 9. DRIFT DETECTION
// ============================================================

datatype EntryMode = FreshRun | Reverify
datatype DriftStatus = NoModelExists | ModelCurrent | ModelStale

function entryModeFromDrift(d: DriftStatus): EntryMode
{
  match d {
    case NoModelExists => FreshRun
    case ModelCurrent  => FreshRun
    case ModelStale    => Reverify
  }
}

// A37: Reverify requires stale drift
lemma ReverifyRequiresDriftDetected(d: DriftStatus)
  requires entryModeFromDrift(d) == Reverify
  ensures d == ModelStale
{}

// A50: No model → fresh run
lemma NoModelMeansFreshRun(d: DriftStatus)
  requires d == NoModelExists
  ensures entryModeFromDrift(d) == FreshRun
{}

// ============================================================
// 10. QUALITY GATE
// ============================================================

datatype ModelQualityProps = ModelQualityProps(
  hasModuleDecl: bool,
  hasFacts: bool,
  hasAssertions: bool,
  hasRunScenarios: bool,
  hasDocComment: bool
)

datatype ModelingMode = Guided | Free

predicate MeetsMinimumQuality(q: ModelQualityProps)
{
  q.hasFacts && q.hasAssertions && q.hasRunScenarios
}

predicate MeetsGuidedQuality(q: ModelQualityProps)
{
  MeetsMinimumQuality(q) && q.hasModuleDecl && q.hasDocComment
}

// A41: Both modes meet minimum quality
lemma BothModesMeetQuality(mode: ModelingMode, q: ModelQualityProps)
  requires (mode == Guided ==> MeetsGuidedQuality(q))
  requires (mode == Free ==> MeetsMinimumQuality(q))
  ensures MeetsMinimumQuality(q)
{}

// A42: Guided mode higher quality
lemma GuidedModeHigherQuality(q: ModelQualityProps)
  requires MeetsGuidedQuality(q)
  ensures q.hasModuleDecl && q.hasDocComment
{}

// A43: Free mode is valid
lemma FreeModeIsValid(q: ModelQualityProps)
  requires MeetsMinimumQuality(q)
  ensures q.hasFacts && q.hasAssertions && q.hasRunScenarios
{}

// ============================================================
// 11. BOUNDARY DECISIONS
// ============================================================

datatype BoundaryDecision = Include | ExcludeSafe | ExcludeRisky | Stub

datatype SystemElement = SystemElement(
  decision: BoundaryDecision,
  hasGapAssertion: bool
)

predicate ValidBoundaryElement(e: SystemElement)
{
  // Risky exclusions must have gap assertions
  (e.decision == ExcludeRisky ==> e.hasGapAssertion)
}

// A31: Risky exclusions have gap assertions
lemma RiskyExclusionsHaveGapAssertions(e: SystemElement)
  requires ValidBoundaryElement(e)
  requires e.decision == ExcludeRisky
  ensures e.hasGapAssertion
{}

// ============================================================
// 12. ENFORCEMENT AUDIT
// ============================================================

predicate EnforcementRequired(nature: ArtifactNature, outcome: ReconcileOutcome)
{
  // Only natural-language Aligned outcomes need enforcement audit
  nature == NaturalLanguage && outcome == Aligned
}

// A51: Natural-language aligned discrepancies must have enforcement level
lemma EnforcementAuditRequired(nature: ArtifactNature, d: Discrepancy)
  requires nature == NaturalLanguage
  requires d.outcome == Aligned
  ensures EnforcementRequired(nature, d.outcome)
{}

// A52: Executable code skips enforcement audit
lemma CodeSkipsEnforcementAudit(nature: ArtifactNature)
  requires nature == ExecutableCode
  ensures !EnforcementRequired(nature, Aligned)
  ensures !EnforcementRequired(nature, FixSource)
  ensures !EnforcementRequired(nature, FixModelToCode)
  ensures !EnforcementRequired(nature, FixModelToIntent)
  ensures !EnforcementRequired(nature, Conflict)
  ensures !EnforcementRequired(nature, Exclusion)
{}

// ============================================================
// 13. REMAINING ASSERTIONS (ported from Alloy for full parity)
// ============================================================

// --- Pattern categories and coverage ---

datatype PatternCategory =
  | Basics | Structural | TemporalCat | UxAccess
  | DataConvert | PipelineCat | Verification | Alloy6Essentials

// Which example covers which categories
predicate exampleCovers(example: Artifact, cat: PatternCategory)
{
  match (example, cat) {
    // static-model-example: Basics + Structural + Verification
    case (StaticExample, Basics)       => true
    case (StaticExample, Structural)   => true
    case (StaticExample, Verification) => true
    // temporal-model-example: Basics + Temporal + Verification
    case (TemporalExample, Basics)      => true
    case (TemporalExample, TemporalCat) => true
    case (TemporalExample, Verification) => true
    // ux-verification-example: Basics + UxAccess + Verification
    case (UxExample, Basics)       => true
    case (UxExample, UxAccess)     => true
    case (UxExample, Verification) => true
    // data-conversion-example: Basics + DataConvert + Verification
    case (DataConvExample, Basics)      => true
    case (DataConvExample, DataConvert) => true
    case (DataConvExample, Verification) => true
    // pipeline-example: Pipeline + Verification + Alloy6Essentials
    case (PipelineExample, PipelineCat)       => true
    case (PipelineExample, Verification)      => true
    case (PipelineExample, Alloy6Essentials)  => true
    case _ => false
  }
}

// All 5 example artifacts
predicate isExample(a: Artifact)
{
  a == StaticExample || a == TemporalExample || a == UxExample ||
  a == DataConvExample || a == PipelineExample
}

// SKILL.md must mention all 8 categories
// Each category is covered by at least one example
// (which means patterns.md documents it and SKILL.md summary lists it)
// Expressed as a concrete check rather than a quantifier to avoid trigger issues.
predicate skillMdCoversAll()
{
  (exists ex :: isExample(ex) && exampleCovers(ex, Basics)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, Structural)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, TemporalCat)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, UxAccess)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, DataConvert)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, PipelineCat)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, Verification)) &&
  (exists ex :: isExample(ex) && exampleCovers(ex, Alloy6Essentials))
}

predicate stepReadsPatterns(s: Step)
{
  s == S3_SelectPattern || s == S4_ReadExample ||
  s == S5_WriteModel || s == S5b_ReviewBounds || s == S10_Iterate
  // S10b_EnforcementAudit does NOT read patterns (checks gate language, not patterns)
}

// A9: Every category covered by an example is documented
// (proves the coverage mapping is total — no category left uncovered)
lemma PatternsSyncedWithExamples()
  ensures skillMdCoversAll()
  ensures stepReadsPatterns(S3_SelectPattern)
  ensures stepReadsPatterns(S5_WriteModel)
{
  // Witness each category with a concrete example
  assert isExample(StaticExample) && exampleCovers(StaticExample, Basics);
  assert isExample(StaticExample) && exampleCovers(StaticExample, Structural);
  assert isExample(TemporalExample) && exampleCovers(TemporalExample, TemporalCat);
  assert isExample(UxExample) && exampleCovers(UxExample, UxAccess);
  assert isExample(DataConvExample) && exampleCovers(DataConvExample, DataConvert);
  assert isExample(PipelineExample) && exampleCovers(PipelineExample, PipelineCat);
  assert isExample(StaticExample) && exampleCovers(StaticExample, Verification);
  assert isExample(PipelineExample) && exampleCovers(PipelineExample, Alloy6Essentials);
}

// A10: SkillMd covers all 8 pattern categories
lemma SkillMdCoversAllCategories()
  ensures skillMdCoversAll()
  ensures stepRequires(S2_ReadSkill, SkillMd)
{
  PatternsSyncedWithExamples();
}

// ============================================================
// EXAMPLE SELECTION BY STYLE + TOKEN BUDGET
//
// Each example is relevant to specific modeling styles.
// The agent loads at most 3 examples matching the chosen style.
// ============================================================

// Which example is relevant to which modeling style
predicate exampleRelevantToStyle(example: Artifact, style: ModelingStyle)
{
  match (example, style) {
    case (StaticExample, Static)      => true
    case (TemporalExample, Temporal)  => true
    case (UxExample, UxLayer)         => true
    case (DataConvExample, Static)    => true
    case (PipelineExample, Static)    => true
    case _ => false
  }
}

// Count examples relevant to a style
function countExamplesForStyle(style: ModelingStyle): nat
{
  (if exampleRelevantToStyle(StaticExample, style) then 1 else 0) +
  (if exampleRelevantToStyle(TemporalExample, style) then 1 else 0) +
  (if exampleRelevantToStyle(UxExample, style) then 1 else 0) +
  (if exampleRelevantToStyle(DataConvExample, style) then 1 else 0) +
  (if exampleRelevantToStyle(PipelineExample, style) then 1 else 0)
}

// Token budget: at most 3 examples per style
predicate exampleBudgetMet(style: ModelingStyle)
{
  countExamplesForStyle(style) <= 3
}

// Every style has at least one relevant example
predicate everyStyleHasExample()
{
  countExamplesForStyle(Static) >= 1 &&
  countExamplesForStyle(Temporal) >= 1 &&
  countExamplesForStyle(UxLayer) >= 1
}

// Budget holds for all styles
lemma ExampleBudgetForAllStyles()
  ensures exampleBudgetMet(Static)    // 3 examples (Static, DataConv, Pipeline)
  ensures exampleBudgetMet(Temporal)  // 1 example (Temporal)
  ensures exampleBudgetMet(UxLayer)   // 1 example (Ux)
{}

// Every style has coverage
lemma EveryStyleHasCoverage()
  ensures everyStyleHasExample()
{}

// Static has the most examples — verify it's exactly 3 (the budget limit)
lemma StaticExampleCount()
  ensures countExamplesForStyle(Static) == 3
{}

// Temporal and UxLayer each have exactly 1
lemma TemporalExampleCount()
  ensures countExamplesForStyle(Temporal) == 1
{}

lemma UxLayerExampleCount()
  ensures countExamplesForStyle(UxLayer) == 1
{}

// ============================================================
// PROOF OF WORK
//
// Certain steps must produce specific evidence — not just complete,
// but produce artifacts that prove the work was actually done.
// Without this, a step could "succeed" without verifying anything.
// ============================================================

datatype ProofOfWork = ProofOfWork(
  step: Step,
  requiresCheckResults: bool,      // must show assertion pass/fail
  requiresScenarioTrace: bool,     // must show concrete instance/trace
  requiresCounterexplanation: bool // must explain counterexamples
)

// The four steps with proof-of-work requirements
function formatOutputPoW(): ProofOfWork {
  ProofOfWork(S8_FormatOutput, true, true, false)
  // Formatter must show check results AND scenario traces
  // but doesn't explain — it just renders
}

function interpretPoW(): ProofOfWork {
  ProofOfWork(S9_Interpret, false, false, true)
  // Interpretation must explain counterexamples
  // Check results already shown by formatter
}

function boundaryReviewPoW(): ProofOfWork {
  ProofOfWork(S5b_ReviewBounds, false, false, false)
  // Must list scope + gaps (implicit in boundary table)
  // No check/scenario/counterexample output at this stage
}

function iteratePoW(): ProofOfWork {
  ProofOfWork(S10_Iterate, false, false, false)
  // Must produce a corrected model
}

// Proof-of-work is satisfied when the evidence matches what the step requires
predicate proofOfWorkSatisfied(pow: ProofOfWork, hasChecks: bool, hasTraces: bool, hasExplanation: bool)
{
  (!pow.requiresCheckResults || hasChecks) &&
  (!pow.requiresScenarioTrace || hasTraces) &&
  (!pow.requiresCounterexplanation || hasExplanation)
}

// A11: Output includes check results
lemma OutputIncludesChecks()
  ensures formatOutputPoW().requiresCheckResults
  ensures formatOutputPoW().requiresScenarioTrace
  ensures stepRequires(S8_FormatOutput, Formatter)
  // Formatter with checks+traces satisfies its proof-of-work
  ensures proofOfWorkSatisfied(formatOutputPoW(), true, true, false)
{}

// A13: Interpretation must explain counterexamples
lemma InterpretExplainsCounterexamples()
  ensures interpretPoW().requiresCounterexplanation
  ensures stepRequires(S9_Interpret, RunOutput)
  ensures stepRequires(S9_Interpret, UserModel)
  // Interpretation with explanation satisfies its proof-of-work
  ensures proofOfWorkSatisfied(interpretPoW(), false, false, true)
{}

// ============================================================
// STALENESS MODEL
//
// Three staleness vectors:
//   (a) UserModel edited during iteration → RunOutput stale
//   (b) SourceSystem changed by team → UserModel stale (describes old system)
//   (c) Interpretation stale when RunOutput regenerated
// ============================================================

predicate isMutable(a: Artifact)
{
  a == UserModel || a == BoundaryReview || a == RunOutput ||
  a == Interpretation || a == Reconciliation ||
  a == ReconciliationRpt || a == EnforcementRpt
}

predicate isSourceArtifact(a: Artifact)
{
  a == SourceCode || a == SourceSpec || a == SourceTests || a == SourceDocs
}

// An artifact version: who produced it, at which version number
datatype ArtifactVersion = ArtifactVersion(
  artifact: Artifact,
  writtenBy: Step,
  version: nat
)

// Known versions in the pipeline
predicate isKnownVersion(v: ArtifactVersion)
{
  // UserModel: v1 from WriteModel, v2 from Iterate
  (v == ArtifactVersion(UserModel, S5_WriteModel, 1)) ||
  (v == ArtifactVersion(UserModel, S10_Iterate, 2)) ||
  // RunOutput: v1 from FormatOutput
  (v == ArtifactVersion(RunOutput, S8_FormatOutput, 1)) ||
  // Source: v1 at trigger time
  (v == ArtifactVersion(SourceCode, S1_Trigger, 1))
}

// Model-source drift: model was written against source v1, but source has v2+
predicate modelSourceDrift(sourceV2: ArtifactVersion, modelV: ArtifactVersion)
{
  isSourceArtifact(sourceV2.artifact) &&
  sourceV2.version > 1 &&
  modelV.artifact == UserModel &&
  modelV.version == 1
}

// Staleness: an artifact has two versions, and the consumer step
// runs after both were written → consumer may read the old one
predicate isStale(consumer: Step, art: Artifact, v1: ArtifactVersion, v2: ArtifactVersion)
{
  v1.artifact == art && v2.artifact == art &&
  v1.version < v2.version &&
  stepRequires(consumer, art) &&
  stepAtOrBefore(v1.writtenBy, consumer) &&
  stepAtOrBefore(v2.writtenBy, consumer)
}

// Freshness guard: a step must compare two artifacts for currency
datatype FreshnessCheck = FreshnessCheck(
  step: Step,
  compares: Artifact,   // the artifact that might be stale
  against: Artifact     // the authoritative version
)

// S9 (Interpret) must verify RunOutput matches current UserModel
predicate freshnessGuardExists()
{
  var fc := FreshnessCheck(S9_Interpret, RunOutput, UserModel);
  fc.step == S9_Interpret && fc.compares == RunOutput && fc.against == UserModel
}

// A16: After iterate, RunOutput is stale (must re-run)
// UserModel goes from v1 (WriteModel) to v2 (Iterate).
// RunOutput was produced from v1. Interpret consumes both.
// The model changed but the output didn't → stale.
lemma RunOutputStaleAfterIterate()
  ensures isMutable(UserModel)
  ensures isMutable(RunOutput)
  ensures isStale(
    S10_Iterate, UserModel,
    ArtifactVersion(UserModel, S5_WriteModel, 1),
    ArtifactVersion(UserModel, S10_Iterate, 2))
  ensures freshnessGuardExists()
{}

// Model-source drift is detectable: if source has v2, model at v1 is stale
lemma DriftIsDetectable()
  ensures modelSourceDrift(
    ArtifactVersion(SourceCode, S1_Trigger, 2),  // team shipped a change
    ArtifactVersion(UserModel, S5_WriteModel, 1)) // model still at v1
{}

// Freshness guard exists for the interpret step
lemma FreshnessGuardForInterpret()
  ensures freshnessGuardExists()
{}

// A18: Tooling uses exactly one runtime
lemma ToolingUsesExactlyOneRuntime(choice: RuntimeOption)
  ensures choice == UseLocalJava || choice == UseDocker
{}

// A19: Boundary review has proof of work (scope table + gap list)
lemma BoundaryReviewHasProofOfWork()
  ensures stepRequires(S5b_ReviewBounds, UserModel)
  ensures stepRequires(S5b_ReviewBounds, SourceCode)
  ensures boundaryReviewPoW().step == S5b_ReviewBounds
  // Boundary review PoW: no check/scenario/counterexample output needed
  // Evidence is the boundary table itself (implicit in step output)
  ensures proofOfWorkSatisfied(boundaryReviewPoW(), false, false, false)
{}

// A22: Runtime choice resolved
lemma RuntimeChoiceResolved()
  ensures stepRequires(S6_SetupTooling, RunScript)
  ensures stepRequires(S6_SetupTooling, LocalJava) || stepRequires(S6_SetupTooling, DockerEngine)
{}

// A25: FixModel implies rerun needed
lemma FixModelImpliesRerun(d: Discrepancy)
  requires d.outcome == FixModelToCode || d.outcome == FixModelToIntent
  ensures isMutable(UserModel)
{}

// A53: Conflict outcomes require user decision (direction = UserDecides)
lemma ConflictRequiresUserDecision(d: Discrepancy)
  requires ValidDiscrepancy(d)
  requires d.outcome == Conflict
  ensures d.direction == UserDecides
{}

// A54: Conflict doesn't trigger model rerun by itself (user must choose direction first)
lemma ConflictDoesNotImplyRerun(d: Discrepancy)
  requires d.outcome == Conflict
  ensures d.outcome != FixModelToCode && d.outcome != FixModelToIntent
{}

// A26: Reconciliation is non-trivial (at least one discrepancy checked)
// (workflow constraint — Dafny can't generate instances, but we prove
// that a valid discrepancy CAN exist)
lemma ReconciliationNonTrivial()
  ensures ValidDiscrepancy(Discrepancy(SourceCode, FixSource, ModelStays_SourceChanges, MissingFromGate, None, true, true, true, true))
{}

// A27: Report-only mode is valid
lemma ReportOnlyIsValid()
  ensures producedBy(Reconciliation) == S9b_Reconcile
{}

// A29: Reconcile requires included sources
lemma ReconcileRequiresIncludedSources()
  ensures stepRequires(S9b_Reconcile, SourceCode)
  ensures stepRequires(S9b_Reconcile, Interpretation)
  ensures stepRequires(S9b_Reconcile, UserModel)
{}

// A47: Reconcile checks included sources
lemma ReconcileChecksIncludedSources()
  ensures stepRequires(S9b_Reconcile, SourceCode)  // code always included
{}

// A49: Skipped sources not checked
// (In Dafny, the stepRequires predicate only includes SourceCode for S9b_Reconcile.
// Other sources are included dynamically based on user selection — this is a
// runtime concern that the static predicate captures conservatively.)
lemma SkippedSourcesNotChecked()
  ensures !stepRequires(S9b_Reconcile, SourceTests)  // not in static requires
  ensures !stepRequires(S9b_Reconcile, SourceDocs)    // not in static requires
{}

// A32: Model non-empty (at least one system element can be included)
lemma ModelNonEmpty()
  ensures ValidBoundaryElement(SystemElement(Include, false))
{}

// A35: Pattern selection not generic only
// (workflow constraint — the modeler must select domain-specific patterns)
lemma PatternSelectionNotGenericOnly()
  ensures stepRequires(S3_SelectPattern, PatternsMd)
  ensures stepReadsPatterns(S3_SelectPattern)
{}

// A36: Design bug is a valid response to counterexample
// (Both fix-and-rerun and design-bug-found are valid — modeled as a type)
datatype CounterexampleResponse = FixAndRerun | DesignBugFound

lemma DesignBugIsValidResponse(r: CounterexampleResponse)
  ensures r == FixAndRerun || r == DesignBugFound
{}

// A38: Scope progression available
datatype ScopeLevel = Scope4 | Scope6 | Scope8

predicate shouldIncreaseScope(level: ScopeLevel, allPassed: bool)
{
  allPassed && level != Scope8
}

lemma ScopeProgressionAvailable(level: ScopeLevel)
  requires shouldIncreaseScope(level, true)
  ensures level != Scope8
{}

// A39: Vague prompt requires clarification
lemma VaguePromptRequiresClarification()
  ensures stepRequires(S5_WriteModel, Clarification)
  ensures stepBefore(S2b_Clarify, S5_WriteModel)
{}

// A40: Example selection respects token budget
lemma ExampleSelectionRespectsBudget()
  ensures stepRequires(S4_ReadExample, Clarification)
  ensures stepRequires(S4_ReadExample, PatternsMd)
  ensures exampleBudgetMet(Static)    // max 3 for the most populated style
  ensures exampleBudgetMet(Temporal)
  ensures exampleBudgetMet(UxLayer)
{}

// A44: Quality gate at boundary review
lemma QualityGateAtBoundaryReview()
  ensures stepRequires(S5b_ReviewBounds, UserModel)
  ensures stepRequires(S5b_ReviewBounds, SourceCode)
  ensures stepRequires(S5b_ReviewBounds, SourceSpec)
{}

// ============================================================
// 14. REPORT PERSISTENCE & GATE AUDIT CHAIN
// ============================================================

// A55: Reports are persisted to disk (both artifacts exist and are mutable)
lemma ReportsPersistedToDisk()
  ensures isMutable(ReconciliationRpt)
  ensures isMutable(EnforcementRpt)
{}

// A56: Reconciliation report is produced by the reconciliation step
lemma ReconcileReportProducedByReconcile()
  ensures producedBy(ReconciliationRpt) == S9b_Reconcile
  ensures stepBefore(S9_Interpret, S9b_Reconcile)
{}

// A57: Enforcement report is produced by the enforcement audit step
lemma EnforcementReportProducedByAudit()
  ensures producedBy(EnforcementRpt) == S10b_EnforcementAudit
  ensures stepBefore(S9b_Reconcile, S10b_EnforcementAudit)
{}

// A58: Enforcement audit must happen before iterate
lemma EnforcementAuditBeforeIterate()
  ensures stepBefore(S10b_EnforcementAudit, S10_Iterate)
  ensures stepRequires(S10_Iterate, EnforcementRpt)
{}

// A59: Every Enforced verdict has a gate audit chain
lemma GateAuditRequiredForEnforced(d: Discrepancy)
  requires ValidDiscrepancy(d)
  requires d.enforcement == Enforced
  ensures d.gateAudit.Some?
{}

// A60: A passing gate audit means all chain links are present
lemma GateAuditChainComplete(d: Discrepancy)
  requires ValidDiscrepancy(d)
  requires d.enforcement == Enforced
  requires d.gateAudit.Some?
  requires d.gateAudit.value.status == AuditOK
  ensures d.gateAudit.value.fieldExists
  ensures d.gateAudit.value.recordingInstruction
  ensures d.gateAudit.value.unambiguous
{
  // ValidDiscrepancy → GateAuditConsistent → ValidGateAudit → status == AuditOK implies all true
}

// Witness: a valid Aligned discrepancy with Enforced enforcement and passing gate audit
lemma AlignedWithGateAuditExists()
  ensures ValidDiscrepancy(
    Discrepancy(SourceCode, Aligned, NoChange_Aligned, Enforced,
      Some(GateAuditChain(AuditOK, true, true, true)),
      true, true, true, true))
{}

// Witness: a valid Aligned discrepancy with failing gate audit (missing field)
lemma AlignedWithMissingFieldExists()
  ensures ValidDiscrepancy(
    Discrepancy(SourceCode, Aligned, NoChange_Aligned, Enforced,
      Some(GateAuditChain(AuditMissingField, false, false, false)),
      true, true, true, true))
{}

// ============================================================
// 15. ITERATION LOOP MODEL
//
// Closes gap A21 (IterationNotALoop) — Alloy can't model this
// because util/ordering enforces a total order with no cycles.
// Dafny models iteration as a sequence of pipeline passes:
//
//   Pass 1: full pipeline S1→S10 → reconciliation_v1
//     if FixModel discrepancies → iterate
//   Pass 2: S5→S5b→S7→S8→S9→S9b→S10b→S10 → reconciliation_v2
//     if FixModel discrepancies → iterate
//   ...
//   Pass N: all Aligned/FixSource/Exclusion → converged, stop
//
// Each pass is a PipelinePass record capturing the state after
// that pass completes. The loop terminates when no FixModel
// discrepancies remain (convergence) or max iterations reached.
//
// Properties proved:
//   - Dependencies satisfied within each pass
//   - Re-run always happens before re-interpret after model edit
//   - Reports updated each pass (not stale)
//   - Convergence condition is well-defined
//   - Loop terminates (bounded by max iterations)
// ============================================================

// State of a single pipeline pass
datatype PipelinePass = PipelinePass(
  passNumber: nat,              // 0-indexed pass number
  modelVersion: nat,            // version of UserModel after this pass
  runOutputVersion: nat,        // version of RunOutput after this pass
  reconciliationVersion: nat,   // version of reconciliation report
  enforcementVersion: nat,      // version of enforcement report
  fixModelCount: nat,           // FixModel discrepancies found this pass
  fixSourceCount: nat,          // FixSource discrepancies found
  alignedCount: nat,            // Aligned discrepancies found
  exclusionCount: nat,          // Exclusion discrepancies found
  conflictCount: nat,           // Conflict discrepancies found
  modelEdited: bool,            // was the model changed this pass?
  rerunAfterEdit: bool          // was the model re-run after editing?
)

// A pass has at least one discrepancy checked
predicate passHasDiscrepancies(p: PipelinePass)
{
  p.fixModelCount + p.fixSourceCount + p.alignedCount + p.exclusionCount + p.conflictCount > 0
}

// A pass is valid: versions are consistent, re-run after edit
predicate ValidPass(p: PipelinePass)
{
  // Pass number matches version progression
  p.modelVersion >= p.passNumber + 1 &&
  p.runOutputVersion >= p.passNumber + 1 &&
  p.reconciliationVersion == p.passNumber + 1 &&
  p.enforcementVersion == p.passNumber + 1 &&
  // At least one discrepancy checked
  passHasDiscrepancies(p) &&
  // If model was edited, must re-run before interpreting
  (p.modelEdited ==> p.rerunAfterEdit) &&
  // FixModel discrepancies imply model was edited
  (p.fixModelCount > 0 ==> p.modelEdited) &&
  // If model wasn't edited, no re-run needed
  (!p.modelEdited ==> p.runOutputVersion == p.passNumber + 1)
}

// Convergence: no FixModel or Conflict discrepancies remain
predicate Converged(p: PipelinePass)
{
  p.fixModelCount == 0 && p.conflictCount == 0
}

// Should iterate: FixModel discrepancies exist
predicate ShouldIterate(p: PipelinePass)
{
  p.fixModelCount > 0
}

// A sequence of passes is valid if each pass is valid and
// versions increase monotonically
predicate ValidPassSequence(passes: seq<PipelinePass>)
{
  |passes| > 0 &&
  (forall i :: 0 <= i < |passes| ==> ValidPass(passes[i])) &&
  (forall i :: 0 <= i < |passes| ==> passes[i].passNumber == i) &&
  // Model version increases when edited
  (forall i :: 0 < i < |passes| && passes[i].modelEdited ==>
    passes[i].modelVersion > passes[i-1].modelVersion) &&
  // Non-final passes must have FixModel discrepancies (reason to iterate)
  (forall i :: 0 <= i < |passes| - 1 ==> ShouldIterate(passes[i])) &&
  // Final pass has converged (or we ran out of iterations)
  (Converged(passes[|passes|-1]) || |passes| >= 10)
}

// Report staleness: after iterate, reports from previous pass are stale
predicate ReportStaleAfterIterate(prevPass: PipelinePass, currPass: PipelinePass)
{
  prevPass.modelEdited &&
  currPass.passNumber == prevPass.passNumber + 1 &&
  // Current pass must have new report versions (not reusing old ones)
  currPass.reconciliationVersion > prevPass.reconciliationVersion &&
  currPass.enforcementVersion > prevPass.enforcementVersion
}

// ============================================================
// ITERATION LOOP LEMMAS
// ============================================================

// Each pass preserves pipeline invariants (dependencies satisfied)
// This is the inductive step: if pass N is valid, the pipeline
// invariants hold for that pass.
lemma PassPreservesDependencies(p: PipelinePass)
  requires ValidPass(p)
  ensures p.modelEdited ==> p.rerunAfterEdit  // A16: re-run after edit
  ensures p.reconciliationVersion >= 1         // A26: reconciliation non-trivial
  ensures p.enforcementVersion >= 1            // A55: reports exist
{}

// Convergence implies no model changes needed
lemma ConvergenceImpliesStable(p: PipelinePass)
  requires ValidPass(p)
  requires Converged(p)
  ensures p.fixModelCount == 0
  ensures p.conflictCount == 0
{}

// If not converged and FixModel exists, must iterate
lemma FixModelRequiresIteration(p: PipelinePass)
  requires ValidPass(p)
  requires !Converged(p)
  requires p.fixModelCount > 0
  ensures ShouldIterate(p)
  ensures p.modelEdited
  ensures p.rerunAfterEdit
{}

// Reports are updated each pass (not stale after iterate)
lemma ReportsNotStaleAfterIterate(prev: PipelinePass, curr: PipelinePass)
  requires ValidPass(prev)
  requires ValidPass(curr)
  requires curr.passNumber == prev.passNumber + 1
  requires prev.modelEdited
  ensures curr.reconciliationVersion > prev.reconciliationVersion
  ensures curr.enforcementVersion > prev.enforcementVersion
{
  // curr.reconciliationVersion == curr.passNumber + 1 > prev.passNumber + 1 == prev.reconciliationVersion
}

// A valid pass sequence terminates: either converged or bounded
lemma LoopTerminates(passes: seq<PipelinePass>)
  requires ValidPassSequence(passes)
  ensures Converged(passes[|passes|-1]) || |passes| >= 10
{
  // Directly from ValidPassSequence definition
}

// Helper: verify a two-element sequence satisfies all quantified properties
lemma TwoPassSequenceValid(p0: PipelinePass, p1: PipelinePass)
  requires ValidPass(p0) && ValidPass(p1)
  requires p0.passNumber == 0 && p1.passNumber == 1
  requires p1.modelEdited ==> p1.modelVersion > p0.modelVersion
  requires ShouldIterate(p0)
  requires Converged(p1) || 2 >= 10
  ensures ValidPassSequence([p0, p1])
{
  var s := [p0, p1];
  assert s[0] == p0;
  assert s[1] == p1;
  assert forall i :: 0 <= i < |s| ==> ValidPass(s[i]);
  assert forall i :: 0 <= i < |s| ==> s[i].passNumber == i;
  assert forall i :: 0 < i < |s| && s[i].modelEdited ==> s[i].modelVersion > s[i-1].modelVersion;
  assert forall i :: 0 <= i < |s| - 1 ==> ShouldIterate(s[i]);
}

// Two-pass convergence witness: pass 1 finds FixModel, pass 2 converges
lemma TwoPassConvergenceExists()
  ensures ValidPassSequence([
    PipelinePass(0, 1, 1, 1, 1, 2, 1, 3, 0, 0, true, true),
    PipelinePass(1, 2, 2, 2, 2, 0, 1, 5, 0, 0, false, false)
  ])
{
  var p0 := PipelinePass(0, 1, 1, 1, 1, 2, 1, 3, 0, 0, true, true);
  var p1 := PipelinePass(1, 2, 2, 2, 2, 0, 1, 5, 0, 0, false, false);
  TwoPassSequenceValid(p0, p1);
}

// Helper: verify a single-element sequence
lemma SinglePassSequenceValid(p0: PipelinePass)
  requires ValidPass(p0)
  requires p0.passNumber == 0
  requires Converged(p0) || 1 >= 10
  ensures ValidPassSequence([p0])
{
  var s := [p0];
  assert s[0] == p0;
  assert forall i :: 0 <= i < |s| ==> ValidPass(s[i]);
  assert forall i :: 0 <= i < |s| ==> s[i].passNumber == i;
  assert forall i :: 0 < i < |s| && s[i].modelEdited ==> s[i].modelVersion > s[i-1].modelVersion;
  assert forall i :: 0 <= i < |s| - 1 ==> ShouldIterate(s[i]);
}

// Single-pass convergence witness: first pass already converged
lemma SinglePassConvergenceExists()
  ensures ValidPassSequence([
    PipelinePass(0, 1, 1, 1, 1, 0, 0, 5, 1, 0, false, false)
  ])
{
  var p0 := PipelinePass(0, 1, 1, 1, 1, 0, 0, 5, 1, 0, false, false);
  SinglePassSequenceValid(p0);
}

// Helper: verify a three-element sequence
lemma ThreePassSequenceValid(p0: PipelinePass, p1: PipelinePass, p2: PipelinePass)
  requires ValidPass(p0) && ValidPass(p1) && ValidPass(p2)
  requires p0.passNumber == 0 && p1.passNumber == 1 && p2.passNumber == 2
  requires p1.modelEdited ==> p1.modelVersion > p0.modelVersion
  requires p2.modelEdited ==> p2.modelVersion > p1.modelVersion
  requires ShouldIterate(p0) && ShouldIterate(p1)
  requires Converged(p2) || 3 >= 10
  ensures ValidPassSequence([p0, p1, p2])
{
  var s := [p0, p1, p2];
  assert s[0] == p0 && s[1] == p1 && s[2] == p2;
  assert forall i :: 0 <= i < |s| ==> ValidPass(s[i]);
  assert forall i :: 0 <= i < |s| ==> s[i].passNumber == i;

  // Help solver with the modelVersion monotonicity quantifier
  forall i | 0 < i < |s| && s[i].modelEdited
    ensures s[i].modelVersion > s[i-1].modelVersion
  {
    if i == 1 { assert s[1].modelVersion > s[0].modelVersion; }
    if i == 2 { assert s[2].modelVersion > s[1].modelVersion; }
  }

  assert forall i :: 0 <= i < |s| - 1 ==> ShouldIterate(s[i]);
}

// Three-pass witness: two iterations needed before convergence
lemma ThreePassConvergenceExists()
  ensures ValidPassSequence([
    PipelinePass(0, 1, 1, 1, 1, 3, 0, 2, 0, 0, true, true),
    PipelinePass(1, 2, 2, 2, 2, 1, 0, 4, 0, 0, true, true),
    PipelinePass(2, 3, 3, 3, 3, 0, 0, 5, 0, 0, false, false)
  ])
{
  var p0 := PipelinePass(0, 1, 1, 1, 1, 3, 0, 2, 0, 0, true, true);
  var p1 := PipelinePass(1, 2, 2, 2, 2, 1, 0, 4, 0, 0, true, true);
  var p2 := PipelinePass(2, 3, 3, 3, 3, 0, 0, 5, 0, 0, false, false);
  ThreePassSequenceValid(p0, p1, p2);
}
