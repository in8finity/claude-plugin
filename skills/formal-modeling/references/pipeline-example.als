-- ================================================================
-- Formal Model of the Formal-Modeling Skill Pipeline (core module)
--
-- Self-verification: models this skill's own artifact dependencies,
-- execution flow, staleness risks, and proof-of-work requirements.
--
-- Split into 4 modules for faster solver runs (~2 min vs ~5 min):
--   skill_pipeline.als          — this file: 42 checks, 16 runs (step ordering, deps, staleness)
--   skill_pipeline_boundary.als — 2 checks, 1 run  (boundary decisions — fully isolated)
--   skill_pipeline_quality.als  — 3 checks, 3 runs (quality gate — fully isolated)
--   skill_pipeline_decisions.als — 7 checks, 9 runs (style/pattern/drift — fully isolated)
--
-- Artifacts:
--   SkillMd          — SKILL.md (trigger description + inline examples)
--   PatternsMd       — alloy-patterns.md (40 patterns reference)
--   StaticExample    — static-model-example.als
--   TemporalExample  — temporal-model-example.als
--   UxExample        — ux-verification-example.als
--   RunScript        — alloy_run.sh (execution pipeline)
--   Formatter        — alloy_format.py (XML → tables)
--   AlloyJar         — .alloy/alloy.jar (downloaded on first run)
--   ExtractedClasses — .alloy/extracted/ (OSGi bundle classes)
--   RunnerClass      — .alloy/AlloyRunner.class (compiled runner)
--   UserModel        — user's .als file (produced by the skill)
--   RunOutput        — alloy_run.sh stdout (check/run results)
--   Interpretation   — counterexample analysis / scenario walkthrough
--
-- Steps (total order, 13 steps):
--   S1   Trigger       — user describes a system; skill activates
--   S2   ReadSkill     — load SKILL.md into context
--   S2b  Clarify       — if prompt is vague, ask clarifying questions
--   S3   SelectPattern — consult alloy-patterns.md for relevant patterns
--   S4   ReadExample   — load one or more reference .als files
--   S5   WriteModel    — write the user's .als model
--   S5b  ReviewBounds  — review model scope, identify gaps and shallow assertions
--   S6   SetupTooling  — detect Java / Docker, download jar, extract, compile
--   S7   RunModel      — execute alloy_run.sh on the model
--   S8   FormatOutput  — pipe through alloy_format.py
--   S9   Interpret     — analyze results: explain checks, trace scenarios
--   S9b  Reconcile     — verify text/code/spec matches model assertions; fix discrepancies
--   S10  Iterate       — fix model or text based on reconciliation, re-run
--
-- Assertions (54 total across all modules):
--   THIS FILE (42 checks — require step ordering / artifact dependencies):
--   A1  DependenciesSatisfied        — no step reads a future artifact
--   A2  SingleProducer               — each artifact has one producer
--   A3  ModelRequiresPatterns        — writing a model requires patterns
--   A4  RunRequiresModel             — can't run without a model
--   A5  RunRequiresTooling           — can't run without jar/classes/runner
--   A6  InterpretRequiresOutput      — can't interpret without run output
--   A7  ExamplesNotRequiredForRun    — examples aren't runtime dependencies
--   A8  ToolingIndependentOfSkill    — jar download doesn't need SKILL.md
--   A9  PatternsSyncedWithExamples   — patterns.md covers what examples demonstrate
--   A10 SkillMdCoversAllCategories   — SKILL.md summary covers all pattern categories
--   A11 OutputIncludesChecks         — run output must show check results
--   A12 IterateRequiresInterpret     — can't iterate without understanding results
--   A13 InterpretExplainsCounterex   — interpretation must explain counterexamples
--   A14 ReviewBeforeRun              — boundary review before running
--   A15 ReviewRequiresModel          — can't review what doesn't exist
--   A16 RunOutputStaleAfterIterate   — edited model → stale output
--   A17 ModelRequiresPrompt          — can't model without user description
--   A18 ToolingUsesExactlyOneRuntime — Java OR Docker, resolved by RuntimeChoice
--   A19 BoundaryReviewHasProofOfWork — review must list scope + gaps
--   A20 ExampleSelectionModeled      — example selection by style (gap FIXED)
--   A21 IterationNotALoop            — GAP: total order can't model cycles
--   A22 RuntimeChoiceResolved        — OR-dependency resolved via choice (FIXED)
--   A23 ReconcileRequiresInterpretAndSpec — reconciliation needs model results + source text
--   A24 ReconcileBeforeIterate       — fix text before deciding what else to change
--   A25 FixModelImpliesRerun         — fixing the model (either direction) means output is stale
--   A26 ReconciliationNonTrivial     — at least one claim is checked
--   A27 ReportOnlyIsValid            — gap report can be the final deliverable
--   A28 ModelRequiresSourceSystem    — model must describe the actual system
--   A29 ReconcileRequiresSourceSystem — reconcile compares against current system
--   A30 BoundaryReviewRequiresSource  — scope review checks actual system
--   A39 VaguePromptRequiresClarification — vague prompts need clarification step (FIXED)
--   A40 ExampleSelectionRespectsBudget — token budget enforced via style selection (FIXED)
--   A44 QualityGateAtBoundaryReview   — S5b is the checkpoint for both modes
--   A45 ReportHasBidirectionalRefs   — every discrepancy links to model AND source
--   A46 ReportIsActionable           — every discrepancy has impact + action
--   A47 ReconcileChecksIncludedSources — partial reconciliation
--   A48 ModelRequiresCode            — model needs actual code
--   A49 SkippedSourcesNotChecked     — no false "aligned" for skipped sources
--   A51 EnforcementAuditRequired    — natural-language Aligned items must have enforcement level
--   A52 CodeSkipsEnforcementAudit   — executable code sources skip enforcement audit
--   A53 ConflictRequiresUserDecision — Conflict outcomes map to UserDecides direction
--   A54 ConflictDoesNotImplyRerun   — Conflict is not a FixModel variant
--
--   skill_pipeline_boundary.als (2 checks — no step/artifact deps):
--   A31 RiskyExclusionsHaveGapAssertions — risky exclusions documented
--   A32 ModelNonEmpty                — at least one element included
--
--   skill_pipeline_quality.als (3 checks — no step/artifact deps):
--   A41 BothModesMeetQuality          — Guided and Free both meet minimum quality
--   A42 GuidedModeHigherQuality       — Guided adds module decl + doc comments
--   A43 FreeModeIsValid               — Free mode produces pipeline-compatible models
--
--   skill_pipeline_decisions.als (7 checks — no step/artifact deps):
--   A33 TemporalProblemRequiresTemporalStyle — wrong style can't verify liveness
--   A34 AccessMatrixGetsUxStyle      — UX problems get UX style
--   A35 PatternSelectionNotGenericOnly — domain patterns required
--   A36 DesignBugIsValidResponse     — counterexample can be a real bug, not just model error
--   A37 ReverifyRequiresSourceChange — re-entry requires system to have changed
--   A38 ScopeProgressionAvailable    — higher scope suggested after all pass
--   A50 NoModelMeansFreshRun         — can't reverify what doesn't exist
-- ================================================================

module skill_pipeline

open util/ordering[Step]


-- ================================================================
-- 1. ARTIFACTS
-- ================================================================

abstract sig Artifact {
  producedBy: one Step,
  mutable: one Bool
}

abstract sig Bool {}
one sig Yes, No extends Bool {}

-- User input
one sig UserPrompt      extends Artifact {} { mutable = No }   -- user's system description
one sig Clarification   extends Artifact {} { mutable = No }   -- clarifying answers (if prompt was vague)

-- Prompt quality: determines whether clarification is needed before modeling
abstract sig PromptQuality {}
one sig Clear extends PromptQuality {}   -- prompt has entities, states, rules → can model directly
one sig Vague extends PromptQuality {}   -- prompt is ambiguous → must ask before modeling

one sig PromptAssessment {
  quality: one PromptQuality
}

-- The source system — decomposed into multiple artifacts that may contradict each other.
-- ALL are mutable — team ships code, spec evolves, tests change, docs drift.
-- The formal model reconciles across all of them, not just one.
abstract sig SourceArtifact extends Artifact {
  includedInReconciliation: one Bool   -- user selects which sources to check
} { mutable = Yes }
one sig SourceCode    extends SourceArtifact {}   -- implementation (actual behavior)
one sig SourceSpec    extends SourceArtifact {}   -- spec/requirements (intended behavior)
one sig SourceTests   extends SourceArtifact {}   -- test suite (assumed behavior)
one sig SourceDocs    extends SourceArtifact {}   -- documentation (described behavior)

-- Code is always included — it's the actual behavior, never optional
fact CodeAlwaysIncluded { SourceCode.includedInReconciliation = Yes }

-- At least one source besides code must be included (otherwise no cross-check value)
fact AtLeastTwoSources {
  some sa: SourceArtifact - SourceCode | sa.includedInReconciliation = Yes
}

-- Convenience: full source system and included subset
fun SourceSystem: set Artifact { SourceCode + SourceSpec + SourceTests + SourceDocs }
fun IncludedSources: set SourceArtifact { { sa: SourceArtifact | sa.includedInReconciliation = Yes } }

-- Skill definition artifacts (pre-existing, validated by S2)
one sig SkillMd         extends Artifact {} { mutable = No }
one sig PatternsMd      extends Artifact {} { mutable = No }
one sig StaticExample   extends Artifact {} { mutable = No }
one sig TemporalExample extends Artifact {} { mutable = No }
one sig UxExample       extends Artifact {} { mutable = No }
one sig DataConvExample extends Artifact {} { mutable = No }
one sig PipelineExample extends Artifact {} { mutable = No }

-- Execution tooling (downloaded/compiled on first run)
one sig RunScript       extends Artifact {} { mutable = No }
one sig Formatter       extends Artifact {} { mutable = No }
one sig LocalJava       extends Artifact {} { mutable = No }   -- local Java 17+ (preferred)
one sig DockerEngine    extends Artifact {} { mutable = No }   -- Docker (fallback if no local Java)
one sig AlloyJar        extends Artifact {} { mutable = No }
one sig ExtractedClasses extends Artifact {} { mutable = No }
one sig RunnerClass     extends Artifact {} { mutable = No }

-- Produced during skill execution
one sig UserModel       extends Artifact {} { mutable = Yes }  -- may be edited in iterate
one sig BoundaryReview  extends Artifact {} { mutable = Yes }  -- scope/gap analysis
one sig RunOutput       extends Artifact {} { mutable = Yes }  -- regenerated each run
one sig Interpretation  extends Artifact {} { mutable = Yes }  -- updated each iteration
one sig Reconciliation  extends Artifact {} { mutable = Yes }  -- discrepancy report + fix direction


-- ================================================================
-- RECONCILIATION OUTCOMES
--
-- Each claim in the source text is compared against the model.
-- Five possible outcomes per claim (FixModel has two sub-directions):
--   FixSource        — model captures design intent; source artifact has a bug
--   FixModelToCode   — code changed intentionally; model needs to match current code
--   FixModelToIntent — spec updated; model should enforce the new design intent
--   Conflict         — sources contradict each other; no single artifact is correct
--   Exclusion        — source claims something the model intentionally doesn't cover
--
-- The direction distinction matters: FixModelToCode means "track as-is behavior",
-- FixModelToIntent means "track should-be behavior". These may differ when code
-- and spec disagree.
--
-- Conflict is distinct from FixModel: when code says X and spec says Y, neither
-- is obviously correct. The user must decide which source represents intended
-- behavior before the discrepancy can be resolved into FixSource or FixModel.
--
-- The Reconciliation artifact IS the set of these outcomes.
-- S10_Iterate uses the outcomes to decide what to change.
-- ================================================================

abstract sig ReconcileOutcome {}
one sig FixSource        extends ReconcileOutcome {}  -- model is correct (design intent) → fix source
one sig FixModelToCode   extends ReconcileOutcome {}  -- code changed → model tracks as-is behavior
one sig FixModelToIntent extends ReconcileOutcome {}  -- spec updated → model tracks should-be behavior
one sig Conflict         extends ReconcileOutcome {}  -- sources contradict; user must decide direction
one sig Exclusion        extends ReconcileOutcome {}  -- conscious scope boundary → document, don't fix

-- Direction: explains to the user what will change and why
abstract sig FixDirection {}
one sig ModelStays_SourceChanges extends FixDirection {}  -- FixSource
one sig ModelAligns_ToCode       extends FixDirection {}  -- FixModelToCode
one sig ModelAligns_ToSpec       extends FixDirection {}  -- FixModelToIntent
one sig UserDecides              extends FixDirection {}  -- Conflict: user picks which source is correct
one sig NoChange_Documented      extends FixDirection {}  -- Exclusion

-- Direction must match outcome
fact DirectionMatchesOutcome {
  all d: Discrepancy |
    (d.outcome = FixSource implies d.direction = ModelStays_SourceChanges)
    and (d.outcome = FixModelToCode implies d.direction = ModelAligns_ToCode)
    and (d.outcome = FixModelToIntent implies d.direction = ModelAligns_ToSpec)
    and (d.outcome = Conflict implies d.direction = UserDecides)
    and (d.outcome = Exclusion implies d.direction = NoChange_Documented)
}

-- ================================================================
-- ENFORCEMENT AUDIT (Step 10b)
--
-- After reconciliation marks properties as Aligned, enforcement audit
-- checks whether the source artifact actually GATES on the rule at
-- the decision point, not just mentions it somewhere.
--
-- Three levels:
--   Enforced            — rule at decision point, gate language, reader can't miss
--   MentionedUnenforced — rule in source but not at gate, or advisory language
--   MissingFromGate     — rule proven by model, absent from decision point
--
-- Only "Enforced" means the source will actually prevent the violation.
-- Enforcement audit applies to natural-language artifacts (instructions,
-- checklists, runbooks), not executable code (which enforces structurally).
-- ================================================================

abstract sig EnforcementLevel {}
one sig Enforced            extends EnforcementLevel {}  -- at gate, imperative language
one sig MentionedUnenforced extends EnforcementLevel {}  -- in source but not at gate
one sig MissingFromGate     extends EnforcementLevel {}  -- model proves it, source doesn't gate

-- Source artifact type determines whether enforcement audit applies
abstract sig ArtifactNature {}
one sig ExecutableCode     extends ArtifactNature {}  -- enforces by construction
one sig NaturalLanguage    extends ArtifactNature {}  -- enforces by precision of phrasing

one sig EnforcementConfig {
  sourceNature: one ArtifactNature
}

sig Discrepancy {
  claim:          one Artifact,
  outcome:        one ReconcileOutcome,
  direction:      one FixDirection,
  enforcement:    lone EnforcementLevel,    -- only set for Aligned outcomes
  -- Bidirectional traceability:
  modelRef:       one Bool,
  sourceRef:      one Bool,
  hasImpact:      one Bool,
  hasAction:      one Bool
}

-- Enforcement is only assessed for natural-language sources
-- (executable code enforces by construction — no audit needed)
fact EnforcementOnlyForNaturalLanguage {
  EnforcementConfig.sourceNature = ExecutableCode implies
    all d: Discrepancy | no d.enforcement
}

-- Aligned discrepancies in natural-language sources MUST have enforcement level
fact AlignedNeedsEnforcement {
  EnforcementConfig.sourceNature = NaturalLanguage implies
    all d: Discrepancy | d.outcome not in (FixSource + FixModelToCode + FixModelToIntent + Conflict + Exclusion)
      implies some d.enforcement
}

-- Non-aligned discrepancies don't get enforcement (they're being fixed/resolved, not audited)
fact NonAlignedNoEnforcement {
  all d: Discrepancy | d.outcome in (FixSource + FixModelToCode + FixModelToIntent + Conflict + Exclusion)
    implies no d.enforcement
}

-- Every discrepancy must have both model and source references (bidirectional traceability)
fact DiscrepancyTraceability {
  all d: Discrepancy | d.modelRef = Yes and d.sourceRef = Yes
}

-- Every discrepancy must have impact analysis and recommended action
fact DiscrepancyCompleteness {
  all d: Discrepancy | d.hasImpact = Yes and d.hasAction = Yes
}

-- At least one discrepancy check must be performed (reconciliation is not empty)
fact ReconciliationNonEmpty {
  some Discrepancy
}

-- FixModel outcomes (either direction) require a re-run (model changed → stale output)
fact FixModelRequiresRerun {
  all d: Discrepancy | d.outcome in (FixModelToCode + FixModelToIntent) implies
    UserModel.mutable = Yes   -- model will be edited → RunOutput stale
}

-- The user may stop at the report without iterating.
-- reportOnly = Yes means the reconciliation is the final deliverable.
one sig ReconcileMode {
  reportOnly: one Bool
}


-- ================================================================
-- BOUNDARY DECISIONS
--
-- Each element of the real system gets a boundary decision during S5b:
--   Include  — model this element (adds sigs, facts, assertions)
--   Exclude  — leave it out (safe if no verification value, risky if hides bugs)
--   Stub     — axiomatize properties without full implementation (e.g., timezone)
--
-- Each decision has an impact: what the model can/cannot prove as a result.
-- Risky exclusions should be documented with gap assertions.
-- ================================================================

abstract sig BoundaryDecision {}
one sig Include extends BoundaryDecision {}   -- fully modeled
one sig ExcludeSafe extends BoundaryDecision {}  -- excluded, no verification value lost
one sig ExcludeRisky extends BoundaryDecision {} -- excluded, may hide bugs (needs gap assertion)
one sig Stub extends BoundaryDecision {}      -- axiomatized, not implemented

sig SystemElement {
  decision: one BoundaryDecision,
  hasGapAssertion: one Bool    -- risky exclusions must have a documenting gap assertion
}

-- Risky exclusions must have a gap assertion documenting the risk
fact RiskyExclusionsDocumented {
  all e: SystemElement | e.decision = ExcludeRisky implies e.hasGapAssertion = Yes
}

-- At least one element must be included (otherwise the model is empty)
fact SomeElementsIncluded {
  some e: SystemElement | e.decision = Include
}


-- ================================================================
-- MODEL QUALITY GATE
--
-- Regardless of how the model was produced (Guided or Free),
-- it must meet minimum requirements to be processable by the
-- downstream pipeline (S5b → S7 → S9 → S9b → S10).
-- These are checked during S5b (boundary review).
-- ================================================================

abstract sig ModelProperty {}
one sig HasModuleDecl    extends ModelProperty {}  -- starts with "module Name"
one sig HasFacts         extends ModelProperty {}  -- at least one fact (invariants)
one sig HasAssertions    extends ModelProperty {}  -- at least one assert + check
one sig HasRunScenarios  extends ModelProperty {}  -- at least one run command
one sig HasDocComment    extends ModelProperty {}  -- block comment explaining scope

one sig ModelQuality {
  properties: set ModelProperty
}

-- Minimum quality: must have facts, assertions, and run commands
-- (module decl and doc comments are best practice, not hard requirements)
fact MinimumQuality {
  HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
}

-- Free-mode models that skip patterns may miss best practices but must
-- still be structurally valid for the pipeline
fact FreeModeMeetsMinimum {
  ModeConfig.mode = Free implies
    HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
}

-- Guided-mode models should also have doc comments and module declaration
fact GuidedModeFullQuality {
  ModeConfig.mode = Guided implies
    ModelQuality.properties = HasModuleDecl + HasFacts + HasAssertions + HasRunScenarios + HasDocComment
}


-- ================================================================
-- CRITICAL DECISIONS
--
-- Five decisions in the pipeline that change the outcome fundamentally.
-- Each decision is modeled as a choice with consequences that the
-- solver can reason about.
-- ================================================================

-- ─── D0: Modeling Mode ──────────────────────────────────────────
-- The modeler can choose how to produce the model:
--   Guided  — full pipeline: read skill → clarify → select patterns → read example → write
--   Free    — write model directly from problem knowledge, optionally consulting patterns/examples
--
-- Both modes produce a UserModel that enters the SAME downstream pipeline
-- (S5b boundary review → S7 run → S9 interpret → S9b reconcile → S10 iterate).
-- The quality gate at S5b ensures the model is fit for the pipeline regardless of how it was produced.

abstract sig ModelingMode {}
one sig Guided extends ModelingMode {}   -- full skill pipeline (S2-S5)
one sig Free   extends ModelingMode {}   -- direct modeling, patterns/examples optional

one sig ModeConfig {
  mode: one ModelingMode
}

-- ─── D1: Modeling Style ─────────────────────────────────────────
-- Choosing wrong style = model can't verify the property the user needs.
-- Static can't verify liveness. Temporal can't verify access matrices
-- efficiently. UX can't verify time-ordered traces.

abstract sig ModelingStyle {}
one sig Static   extends ModelingStyle {}   -- snapshot: invariants, access control
one sig Temporal extends ModelingStyle {}   -- traces: state machine, liveness, ordering
one sig UxLayer  extends ModelingStyle {}   -- static but specialized: roles × states × fields

-- What the user's problem needs (derived from UserPrompt)
one sig ProblemProfile {
  needsTemporalOrder:    one Bool,  -- "before/after", "eventually", webhook ordering
  needsAccessMatrix:     one Bool,  -- "which roles", "who can see", "permission"
  needsLivenessCheck:    one Bool,  -- "can we reach state X", "deadlock", "always eventually"
  chosenStyle:           one ModelingStyle
}

-- Style must match the problem
fact StyleMatchesProblem {
  -- If problem needs temporal ordering or liveness → must choose Temporal
  (ProblemProfile.needsTemporalOrder = Yes or ProblemProfile.needsLivenessCheck = Yes)
    implies ProblemProfile.chosenStyle = Temporal
  -- If problem needs access matrix but not temporal → UxLayer is ideal
  (ProblemProfile.needsAccessMatrix = Yes
    and ProblemProfile.needsTemporalOrder = No
    and ProblemProfile.needsLivenessCheck = No)
    implies ProblemProfile.chosenStyle = UxLayer
}

-- ─── D2: Pattern Selection ──────────────────────────────────────
-- Wrong patterns → model misses key techniques (e.g., axioms for TZ, ++ for temporal)

sig SelectedPattern {
  category: one PatternCategory,
  relevantToStyle: one ModelingStyle
}

-- Selected patterns must be relevant to the chosen style
fact PatternsMatchStyle {
  all sp: SelectedPattern | sp.relevantToStyle = ProblemProfile.chosenStyle
    or sp.category = Basics          -- Basics always relevant
    or sp.category = Verification    -- Verification always relevant
}

-- At least one domain-specific pattern must be selected (not just Basics)
fact DomainPatternSelected {
  some sp: SelectedPattern | sp.category != Basics and sp.category != Verification
}

-- ─── D6: Counterexample Response ────────────────────────────────
-- After a counterexample: fix the model OR flag as a design bug.
-- These produce completely different outputs.

abstract sig CounterexampleResponse {}
one sig FixAndRerun   extends CounterexampleResponse {}   -- model was wrong → fix, re-run
one sig DesignBugFound extends CounterexampleResponse {}  -- system has a real bug → produce bug report

-- The response is per-counterexample, not global
sig CounterexampleEvent {
  response: one CounterexampleResponse,
  assertion: one Artifact                -- which assertion failed (proxy: the model)
}

-- DesignBugFound produces a report; doesn't need iteration
-- FixAndRerun requires iteration
fact DesignBugStopsPipeline {
  all ce: CounterexampleEvent | ce.response = DesignBugFound implies
    ReconcileMode.reportOnly = Yes or ReconcileMode.reportOnly = No
    -- (no constraint on mode — but the pipeline can stop here with the bug report)
}

-- ─── D5: Runtime Choice (Java OR Docker) ────────────────────────
-- The OR-dependency is resolved into a concrete choice before S6 runs.
-- The script detects local Java 17+; if absent, falls back to Docker.
-- Modeled as a choice — not a conjunctive requires set.

abstract sig RuntimeOption {}
one sig UseLocalJava extends RuntimeOption {}  -- preferred: local JDK
one sig UseDocker   extends RuntimeOption {}   -- fallback: Docker container

one sig RuntimeChoice {
  chosen: one RuntimeOption
}

-- ─── D9: Entry Mode (fresh vs re-verify) ────────────────────────
-- Detection: git diff between model's last commit and HEAD.
-- If source files changed after the model → Reverify.
-- If no .als model exists for the domain → FreshRun.
-- If .als exists and no source drift → model is current, skip or fresh.

abstract sig EntryMode {}
one sig FreshRun   extends EntryMode {}   -- no existing model, or model is current
one sig Reverify   extends EntryMode {}   -- existing model, source changed (git diff non-empty)

-- Drift detection state (from git diff)
abstract sig DriftStatus {}
one sig NoModelExists extends DriftStatus {}   -- no .als file for this domain
one sig ModelCurrent  extends DriftStatus {}   -- .als exists, no source drift
one sig ModelStale    extends DriftStatus {}   -- .als exists, source files changed after model commit

one sig PipelineConfig {
  entryMode: one EntryMode,
  driftStatus: one DriftStatus
}

-- Entry mode is determined by drift detection
fact EntryModeFromDrift {
  -- No model exists → must be fresh run
  PipelineConfig.driftStatus = NoModelExists implies PipelineConfig.entryMode = FreshRun
  -- Model exists but source changed → re-verify
  PipelineConfig.driftStatus = ModelStale implies PipelineConfig.entryMode = Reverify
  -- Model current → fresh run (model is up to date, no re-verification needed)
  PipelineConfig.driftStatus = ModelCurrent implies PipelineConfig.entryMode = FreshRun
}

-- ─── Example Selection (fixes gap A40) ──────────────────────────
-- Each example is relevant to specific modeling styles.
-- The agent loads at most 2 examples based on the chosen style.

sig ExampleRelevance {
  example: one Artifact,
  forStyle: one ModelingStyle
}

fact ExampleStyleMapping {
  some er: ExampleRelevance | er.example = StaticExample   and er.forStyle = Static
  some er: ExampleRelevance | er.example = TemporalExample and er.forStyle = Temporal
  some er: ExampleRelevance | er.example = UxExample       and er.forStyle = UxLayer
  some er: ExampleRelevance | er.example = DataConvExample and er.forStyle = Static
  some er: ExampleRelevance | er.example = PipelineExample and er.forStyle = Static
}

-- Token budget: load at most 2 examples (prevents context overflow)
fact ExampleBudget {
  #{er: ExampleRelevance | er.forStyle = ProblemProfile.chosenStyle} <= 3
}

-- In Reverify mode, UserModel already exists (from a previous run)
-- The key steps are: boundary review → run → interpret → reconcile
-- Steps S1-S5 (trigger, read, select, example, write) are skipped.
-- Reverify requires drift detection to have found stale model
-- (EntryModeFromDrift fact already enforces ModelStale → Reverify)

-- ─── D10: Scope Progression ─────────────────────────────────────
-- for 4 → for 6 → for 8: higher scope = stronger confidence but slower.
-- Passing at scope 4 does NOT mean the property holds universally.

abstract sig ScopeLevel {}
one sig Scope4 extends ScopeLevel {}   -- fast, low confidence
one sig Scope6 extends ScopeLevel {}   -- moderate
one sig Scope8 extends ScopeLevel {}   -- slow, high confidence (small-scope hypothesis)

one sig SolverConfig {
  currentScope: one ScopeLevel,
  allPassedAtCurrentScope: one Bool
}

-- If all checks pass at current scope, suggest increasing
-- (this is guidance, not a hard constraint — modeled as a predicate)
pred shouldIncreaseScope {
  SolverConfig.allPassedAtCurrentScope = Yes
  and SolverConfig.currentScope != Scope8
}


-- ================================================================
-- 2. STEPS
-- ================================================================

abstract sig Step {
  requires: set Artifact,
  produces: set Artifact,
  readsPatterns: one Bool    -- does this step consult patterns.md?
}

one sig S1_Trigger        extends Step {}
one sig S2_ReadSkill      extends Step {}
one sig S2b_Clarify       extends Step {}  -- ask clarifying questions if prompt is vague
one sig S3_SelectPattern  extends Step {}
one sig S4_ReadExample    extends Step {}
one sig S5_WriteModel     extends Step {}
one sig S5b_ReviewBounds  extends Step {}  -- NEW: review model boundaries before running
one sig S6_SetupTooling   extends Step {}
one sig S7_RunModel       extends Step {}
one sig S8_FormatOutput   extends Step {}
one sig S9_Interpret      extends Step {}
one sig S9b_Reconcile     extends Step {}  -- reconcile text/code/spec against model assertions
one sig S10_Iterate       extends Step {}


-- ================================================================
-- 3. STEP ORDERING
-- ================================================================

fact StepOrder {
  first = S1_Trigger
  next[S1_Trigger]        = S2_ReadSkill
  next[S2_ReadSkill]      = S2b_Clarify
  next[S2b_Clarify]       = S3_SelectPattern
  next[S3_SelectPattern]  = S4_ReadExample
  next[S4_ReadExample]    = S5_WriteModel
  next[S5_WriteModel]     = S5b_ReviewBounds   -- NEW: review before running
  next[S5b_ReviewBounds]  = S6_SetupTooling
  next[S6_SetupTooling]   = S7_RunModel
  next[S7_RunModel]       = S8_FormatOutput
  next[S8_FormatOutput]   = S9_Interpret
  next[S9_Interpret]      = S9b_Reconcile
  next[S9b_Reconcile]     = S10_Iterate
}


-- ================================================================
-- 4. PRODUCTION RULES
-- ================================================================

fact Productions {
  -- User input (pre-exists at trigger time)
  UserPrompt.producedBy      = S1_Trigger
  -- Source artifacts (pre-exist at trigger time; each may be independently modified by the team)
  SourceCode.producedBy    = S1_Trigger
  SourceSpec.producedBy    = S1_Trigger
  SourceTests.producedBy   = S1_Trigger
  SourceDocs.producedBy    = S1_Trigger

  -- Pre-existing skill artifacts (produced at "step 0" = S1_Trigger for modeling purposes)
  SkillMd.producedBy         = S1_Trigger
  PatternsMd.producedBy      = S1_Trigger
  StaticExample.producedBy   = S1_Trigger
  TemporalExample.producedBy = S1_Trigger
  UxExample.producedBy       = S1_Trigger
  DataConvExample.producedBy = S1_Trigger
  PipelineExample.producedBy = S1_Trigger
  RunScript.producedBy       = S1_Trigger
  Formatter.producedBy       = S1_Trigger
  LocalJava.producedBy       = S1_Trigger     -- pre-exists; auto-detected from system
  DockerEngine.producedBy    = S1_Trigger     -- pre-exists; fallback if no local Java

  -- Tooling setup
  AlloyJar.producedBy        = S6_SetupTooling
  ExtractedClasses.producedBy = S6_SetupTooling
  RunnerClass.producedBy     = S6_SetupTooling

  -- Clarification (produced by S2b if prompt is vague; trivially produced if clear)
  Clarification.producedBy   = S2b_Clarify

  -- Skill execution outputs
  UserModel.producedBy       = S5_WriteModel
  BoundaryReview.producedBy  = S5b_ReviewBounds
  RunOutput.producedBy       = S8_FormatOutput
  Interpretation.producedBy  = S9_Interpret
  Reconciliation.producedBy  = S9b_Reconcile
}


-- ================================================================
-- 5. DEPENDENCY RULES
-- ================================================================

fact Dependencies {
  -- S1: user prompt arrives — no artifact dependencies (prompt IS the trigger)
  S1_Trigger.requires = none

  -- S2: read the skill definition; need the user's prompt for context
  S2_ReadSkill.requires = SkillMd + UserPrompt

  -- S2b: clarify vague prompts — needs the prompt + skill (to know what to ask)
  S2b_Clarify.requires = UserPrompt + SkillMd

  -- S3: consult patterns for the user's domain — uses clarified prompt
  S3_SelectPattern.requires = PatternsMd + SkillMd + UserPrompt + Clarification

  -- S4: read relevant reference examples — selected by style + domain (see ExampleSelection)
  S4_ReadExample.requires = PatternsMd + Clarification

  -- S5: write the model — uses clarified prompt, patterns, source system
  S5_WriteModel.requires = PatternsMd + SkillMd + Clarification + SourceSystem

  -- S5b: review model boundaries — quality gate for the downstream pipeline.
  -- Requires UserModel + SourceSystem regardless of mode.
  -- In Guided mode, also uses PatternsMd + SkillMd for thorough review.
  -- In Free mode, the modeler may have skipped patterns/skill, but the model
  -- still must meet the quality bar (has module, facts, assertions, run/check).
  S5b_ReviewBounds.requires = UserModel + SourceSystem

  -- S6: download jar, extract classes, compile runner
  -- Runtime is chosen by D5 (RuntimeChoice): local Java preferred, Docker fallback.
  -- The requires set includes RunScript + whichever runtime was chosen.
  RunScript in S6_SetupTooling.requires
  RuntimeChoice.chosen = UseLocalJava implies S6_SetupTooling.requires = RunScript + LocalJava
  RuntimeChoice.chosen = UseDocker    implies S6_SetupTooling.requires = RunScript + DockerEngine

  -- S7: run the model — now also requires boundary review completed
  S7_RunModel.requires = UserModel + BoundaryReview + RunScript + AlloyJar + ExtractedClasses + RunnerClass

  -- S8: format raw output
  S8_FormatOutput.requires = Formatter

  -- S9: interpret formatted results
  S9_Interpret.requires = RunOutput + UserModel

  -- S9b: reconcile against INCLUDED source artifacts (partial reconciliation)
  -- Always needs: interpretation, user model, skill description, prompt
  -- Source artifacts: ONLY those the user selected — skipped ones are excluded
  S9b_Reconcile.requires = Interpretation + UserModel + SkillMd + UserPrompt + IncludedSources

  -- S10: iterate — fix model or text based on reconciliation
  S10_Iterate.requires = Reconciliation + Interpretation + UserModel + PatternsMd
}


-- ================================================================
-- 6. PATTERN CONSULTATION
-- ================================================================

fact PatternConsultation {
  S1_Trigger.readsPatterns       = No
  S2_ReadSkill.readsPatterns     = No
  S2b_Clarify.readsPatterns      = No    -- clarification is about the user's system, not patterns
  S3_SelectPattern.readsPatterns = Yes   -- primary pattern selection step
  S4_ReadExample.readsPatterns   = Yes   -- patterns guide which example to read
  S5_WriteModel.readsPatterns    = Yes   -- patterns consulted during writing
  S5b_ReviewBounds.readsPatterns = Yes   -- patterns guide gap analysis
  S6_SetupTooling.readsPatterns  = No
  S7_RunModel.readsPatterns      = No
  S8_FormatOutput.readsPatterns  = No
  S9_Interpret.readsPatterns     = No    -- interpretation uses the model, not patterns
  S9b_Reconcile.readsPatterns    = No    -- compares text against model, not patterns
  S10_Iterate.readsPatterns      = Yes   -- may consult patterns to fix issues
}


-- ================================================================
-- 7. CONSISTENCY CHECKS (artifact-level)
-- ================================================================

-- Pattern coverage: each example file should demonstrate patterns
-- that are documented in patterns.md
sig PatternCoverage {
  example:  one Artifact,
  patterns: set PatternCategory
}

abstract sig PatternCategory {}
one sig Basics           extends PatternCategory {}
one sig Structural       extends PatternCategory {}
one sig TemporalCat      extends PatternCategory {}
one sig UxAccess         extends PatternCategory {}
one sig DataConvert      extends PatternCategory {}
one sig Pipeline         extends PatternCategory {}
one sig Verification     extends PatternCategory {}
one sig Alloy6Essentials extends PatternCategory {}  -- patterns 39-46: ordering, temporal, disj, seq, etc.

fact ExampleCoverage {
  some pc: PatternCoverage | pc.example = StaticExample
    and pc.patterns = Basics + Structural + Verification
  some pc: PatternCoverage | pc.example = TemporalExample
    and pc.patterns = Basics + TemporalCat + Verification
  some pc: PatternCoverage | pc.example = UxExample
    and pc.patterns = Basics + UxAccess + Verification
  some pc: PatternCoverage | pc.example = DataConvExample
    and pc.patterns = Basics + DataConvert + Verification
  some pc: PatternCoverage | pc.example = PipelineExample
    and pc.patterns = Pipeline + Verification + Alloy6Essentials
}

-- SkillMd pattern summary must reference all categories that examples cover
sig SkillMdCoverage {
  mentionedCategories: set PatternCategory
}

fact SkillMdMentionsAll {
  some smc: SkillMdCoverage |
    smc.mentionedCategories = Basics + Structural + TemporalCat + UxAccess
      + DataConvert + Pipeline + Verification + Alloy6Essentials
}


-- ================================================================
-- 8. PROOF OF WORK
-- ================================================================

sig ProofOfWork {
  step: one Step,
  requiresCheckResults: one Bool,     -- must show assertion pass/fail
  requiresScenarioTrace: one Bool,    -- must show concrete instance/trace
  requiresCounterexplanation: one Bool -- must explain counterexamples
}

fact ProofOfWorkRules {
  -- Run output must contain check results
  some p: ProofOfWork | p.step = S8_FormatOutput
    and p.requiresCheckResults = Yes
    and p.requiresScenarioTrace = Yes
    and p.requiresCounterexplanation = No   -- formatter just renders, doesn't explain

  -- Interpretation must explain counterexamples
  some p: ProofOfWork | p.step = S9_Interpret
    and p.requiresCheckResults = No         -- already shown in output
    and p.requiresScenarioTrace = No
    and p.requiresCounterexplanation = Yes  -- THE key value add

  -- Boundary review must list scope and identify gaps
  some p: ProofOfWork | p.step = S5b_ReviewBounds
    and p.requiresCheckResults = No
    and p.requiresScenarioTrace = No
    and p.requiresCounterexplanation = No
    -- implicit: must list what's in/out of scope and identify shallow assertions

  -- Iteration must produce a corrected model
  some p: ProofOfWork | p.step = S10_Iterate
    and p.requiresCheckResults = No
    and p.requiresScenarioTrace = No
    and p.requiresCounterexplanation = No
}


-- ================================================================
-- 9. STALENESS MODEL
-- ================================================================

-- Three staleness vectors:
--   (a) UserModel edited during iteration → RunOutput stale
--   (b) SourceSystem changed by the team → UserModel stale (model describes old system)
--   (c) Interpretation stale when RunOutput regenerated
--
-- Vector (b) is the system-evolution case: the team ships a change,
-- the model's assertions still pass, but they verify the OLD system.
-- The model needs to be re-verified against the NEW source system.

sig ArtifactVersion {
  artifact:  one Artifact,
  writtenBy: one Step,
  version:   one Int
}

fact Versions {
  -- UserModel: v1 from WriteModel, v2 from Iterate
  some v: ArtifactVersion | v.artifact = UserModel and v.writtenBy = S5_WriteModel and v.version = 1
  some v: ArtifactVersion | v.artifact = UserModel and v.writtenBy = S10_Iterate   and v.version = 2

  -- RunOutput: v1 from FormatOutput (based on UserModel v1)
  some v: ArtifactVersion | v.artifact = RunOutput and v.writtenBy = S8_FormatOutput and v.version = 1

  -- Source artifacts: v1 at trigger time, v2 when team ships changes
  some v: ArtifactVersion | v.artifact = SourceCode and v.writtenBy = S1_Trigger and v.version = 1
}

-- Model-source drift: UserModel was written against source v1,
-- but the team shipped changes to any source artifact. The model is now stale.
pred modelSourceDrift {
  some vs: ArtifactVersion | vs.artifact in SourceArtifact and vs.version > 1
  and some vm: ArtifactVersion | vm.artifact = UserModel and vm.version = 1
  -- Model was never updated to reflect the new source system
}

-- Staleness predicate
pred isStale[consumer: Step, art: Artifact] {
  art in consumer.requires
  some v1, v2: ArtifactVersion |
    v1.artifact = art and v2.artifact = art
    and v1.version < v2.version
    and lt[v1.writtenBy, consumer]
    and lt[v2.writtenBy, consumer]
}

-- Freshness guard: after iterate, must re-run before re-interpreting
sig FreshnessCheck {
  step:     one Step,
  compares: one Artifact,
  against:  one Artifact
}

fact FreshnessGuards {
  -- S9 (Interpret) must verify RunOutput matches current UserModel
  some fc: FreshnessCheck |
    fc.step = S9_Interpret and fc.compares = RunOutput and fc.against = UserModel
}


-- ================================================================
-- 10. ASSERTIONS
-- ================================================================

-- A1: No step reads an artifact from the future
assert DependenciesSatisfied {
  all s: Step, a: s.requires | lte[a.producedBy, s]
}

-- A2: Each artifact has exactly one producer
assert SingleProducer {
  all a: Artifact | one a.producedBy
}

-- A3: Writing a model requires consulting patterns
assert ModelRequiresPatterns {
  PatternsMd in S5_WriteModel.requires
  and S5_WriteModel.readsPatterns = Yes
}

-- A4: Can't run without a model
assert RunRequiresModel {
  UserModel in S7_RunModel.requires
}

-- A5: Can't run without tooling
assert RunRequiresTooling {
  AlloyJar in S7_RunModel.requires
  and ExtractedClasses in S7_RunModel.requires
  and RunnerClass in S7_RunModel.requires
}

-- A6: Can't interpret without run output
assert InterpretRequiresOutput {
  RunOutput in S9_Interpret.requires
}

-- A7: Examples are NOT runtime dependencies (they're design-time references)
assert ExamplesNotRequiredForRun {
  StaticExample not in S7_RunModel.requires
  and TemporalExample not in S7_RunModel.requires
  and UxExample not in S7_RunModel.requires
}

-- A8: Tooling setup is independent of skill content
assert ToolingIndependentOfSkill {
  SkillMd not in S6_SetupTooling.requires
  and PatternsMd not in S6_SetupTooling.requires
}

-- A9: Every pattern category covered by an example is also in the patterns.md
assert PatternsSyncedWithExamples {
  all pc: PatternCoverage, cat: pc.patterns |
    some smc: SkillMdCoverage | cat in smc.mentionedCategories
}

-- A10: SkillMd summary covers all documented categories
assert SkillMdCoversAllCategories {
  some smc: SkillMdCoverage |
    Basics + Structural + TemporalCat + UxAccess + DataConvert + Pipeline + Verification + Alloy6Essentials
      in smc.mentionedCategories
}

-- A11: Formatted output must include check results (proof of work)
assert OutputIncludesChecks {
  some p: ProofOfWork | p.step = S8_FormatOutput and p.requiresCheckResults = Yes
}

-- A12: Iterate requires interpretation (can't fix without understanding)
assert IterateRequiresInterpret {
  Interpretation in S10_Iterate.requires
}

-- A13: Interpretation must explain counterexamples (not just show raw output)
assert InterpretExplainsCounterexamples {
  some p: ProofOfWork | p.step = S9_Interpret and p.requiresCounterexplanation = Yes
}

-- A14: Boundary review must happen before running (no running unreviewed models)
assert ReviewBeforeRun {
  BoundaryReview in S7_RunModel.requires
  and lt[S5b_ReviewBounds, S7_RunModel]
}

-- A15: Boundary review requires the written model (can't review what doesn't exist)
assert ReviewRequiresModel {
  UserModel in S5b_ReviewBounds.requires
}

-- A16: After iterate, RunOutput is stale (must re-run)
assert RunOutputStaleAfterIterate {
  UserModel.mutable = Yes
}

-- A17: Writing a model requires clarified input (prompt flows through S2b_Clarify)
--   UserPrompt → S2b_Clarify → Clarification → S5_WriteModel
assert ModelRequiresClarifiedInput {
  Clarification in S5_WriteModel.requires
  and UserPrompt in S2b_Clarify.requires
  and lt[S2b_Clarify, S5_WriteModel]
}

-- A18: Tooling uses exactly one runtime — Java OR Docker, never both, never neither.
--   The RuntimeChoice resolves the OR before S6 runs.
assert ToolingUsesExactlyOneRuntime {
  (RuntimeChoice.chosen = UseLocalJava implies
    (LocalJava in S6_SetupTooling.requires and DockerEngine not in S6_SetupTooling.requires))
  and
  (RuntimeChoice.chosen = UseDocker implies
    (DockerEngine in S6_SetupTooling.requires and LocalJava not in S6_SetupTooling.requires))
}

-- A19: Boundary review has proof of work (must list scope + gaps)
assert BoundaryReviewHasProofOfWork {
  some p: ProofOfWork | p.step = S5b_ReviewBounds
}

-- A20: Example selection IS now modeled (gap FIXED).
--   S4_ReadExample requires Clarification (style determined after clarification).
--   ExampleRelevance maps examples to styles; ExampleBudget limits count.
assert ExampleSelectionModeled {
  Clarification in S4_ReadExample.requires
}

-- A23: Reconciliation requires both the interpretation and the source text (SkillMd)
assert ReconcileRequiresInterpretAndSpec {
  Interpretation in S9b_Reconcile.requires
  and SkillMd in S9b_Reconcile.requires
}

-- A24: Reconciliation happens before iterate (fix text, then decide what to change)
assert ReconcileBeforeIterate {
  lt[S9b_Reconcile, S10_Iterate]
  and Reconciliation in S10_Iterate.requires
}

-- A25: Every FixModel discrepancy (either direction) implies the model is mutable (will need re-run)
assert FixModelImpliesRerun {
  all d: Discrepancy | d.outcome in (FixModelToCode + FixModelToIntent) implies UserModel.mutable = Yes
}

-- A26: Reconciliation always finds at least one claim to check
assert ReconciliationNonTrivial {
  some Discrepancy
}

-- A53: Conflict outcomes require user decision (direction = UserDecides)
assert ConflictRequiresUserDecision {
  all d: Discrepancy | d.outcome = Conflict implies d.direction = UserDecides
}

-- A54: Conflict doesn't trigger model rerun by itself (user must choose direction first)
assert ConflictDoesNotImplyRerun {
  all d: Discrepancy | d.outcome = Conflict implies
    d.outcome not in (FixModelToCode + FixModelToIntent)
}

-- ================================================================
-- CRITICAL DECISION ASSERTIONS
-- ================================================================

-- A33: Temporal problems require temporal style (wrong style = can't verify liveness)
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

-- A36: If a counterexample event exists, both response types are structurally valid
--   (the model doesn't force all counterexamples into FixAndRerun)
assert DesignBugIsValidResponse {
  all ce: CounterexampleEvent | ce.response = DesignBugFound or ce.response = FixAndRerun
}

-- A37: Reverify mode requires stale drift status (git diff detected changes)
assert ReverifyRequiresDriftDetected {
  PipelineConfig.entryMode = Reverify implies PipelineConfig.driftStatus = ModelStale
}

-- A50: No model exists → must be fresh run (can't reverify what doesn't exist)
assert NoModelMeansFreshRun {
  PipelineConfig.driftStatus = NoModelExists implies PipelineConfig.entryMode = FreshRun
}

-- A38: Scope increase is suggested when all checks pass at current scope
assert ScopeProgressionAvailable {
  shouldIncreaseScope implies SolverConfig.currentScope != Scope8
}

-- ================================================================
-- GAP ASSERTIONS FOR RISKY EXCLUSIONS (from boundary review)
-- ================================================================

-- A45: Every discrepancy in the report has bidirectional traceability
assert ReportHasBidirectionalRefs {
  all d: Discrepancy | d.modelRef = Yes and d.sourceRef = Yes
}

-- A46: Every discrepancy has impact analysis + recommended action
assert ReportIsActionable {
  all d: Discrepancy | d.hasImpact = Yes and d.hasAction = Yes
}

-- A51: Natural-language Aligned discrepancies must have enforcement level
assert EnforcementAuditRequired {
  EnforcementConfig.sourceNature = NaturalLanguage implies
    all d: Discrepancy | d.outcome not in (FixSource + FixModelToCode + FixModelToIntent + Conflict + Exclusion)
      implies some d.enforcement
}

-- A52: Executable code sources skip enforcement audit (enforces by construction)
assert CodeSkipsEnforcementAudit {
  EnforcementConfig.sourceNature = ExecutableCode implies
    all d: Discrepancy | no d.enforcement
}

-- A41: Both modes produce models that meet the minimum quality bar
assert BothModesMeetQuality {
  HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
}

-- A42: Guided mode produces higher quality (full documentation)
assert GuidedModeHigherQuality {
  ModeConfig.mode = Guided implies
    HasModuleDecl + HasDocComment in ModelQuality.properties
}

-- A43: Free mode is valid — downstream pipeline works with minimum quality
assert FreeModeIsValid {
  ModeConfig.mode = Free implies
    HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
}

-- A44: Quality gate is at S5b (boundary review) — the checkpoint for both modes
assert QualityGateAtBoundaryReview {
  UserModel in S5b_ReviewBounds.requires
  and SourceSystem in S5b_ReviewBounds.requires
}

-- A39: Vague prompts require clarification before writing (gap FIXED)
--   S2b_Clarify produces Clarification; S5_WriteModel requires Clarification.
--   If prompt is vague, the clarification step asks questions.
--   If prompt is clear, clarification is trivially produced (no-op step).
assert VaguePromptRequiresClarification {
  Clarification in S5_WriteModel.requires
  and lt[S2b_Clarify, S5_WriteModel]
}

-- A40: Example selection respects token budget (gap FIXED)
--   At most 2-3 examples loaded per style, selected by ExampleRelevance.
--   S4_ReadExample requires Clarification (style is known after clarification).
assert ExampleSelectionRespectsBudget {
  Clarification in S4_ReadExample.requires
  and #{er: ExampleRelevance | er.forStyle = ProblemProfile.chosenStyle} <= 3
}

-- A31: Risky exclusions must have documenting gap assertions
assert RiskyExclusionsHaveGapAssertions {
  all e: SystemElement | e.decision = ExcludeRisky implies e.hasGapAssertion = Yes
}

-- A32: Model is non-empty (at least one system element included)
assert ModelNonEmpty {
  some e: SystemElement | e.decision = Include
}

-- A28: WriteModel requires SourceSystem (model must describe the actual system)
assert ModelRequiresSourceSystem {
  SourceSystem in S5_WriteModel.requires
}

-- A29: Reconcile requires at least the included sources
assert ReconcileRequiresIncludedSources {
  IncludedSources in S9b_Reconcile.requires
}

-- A30: Boundary review requires SourceSystem (scope review must check actual system, not memory)
assert BoundaryReviewRequiresSource {
  SourceSystem in S5b_ReviewBounds.requires
}

-- A47: Reconciliation checks all INCLUDED sources (partial reconciliation allowed)
assert ReconcileChecksIncludedSources {
  -- Code is always checked (CodeAlwaysIncluded fact)
  SourceCode in S9b_Reconcile.requires
  -- Other sources are in requires only if included
  and all sa: SourceArtifact | sa.includedInReconciliation = Yes implies sa in S9b_Reconcile.requires
}

-- A49: Skipped sources are NOT in reconcile requires (no false "aligned" verdicts)
assert SkippedSourcesNotChecked {
  all sa: SourceArtifact | sa.includedInReconciliation = No implies sa not in S9b_Reconcile.requires
}

-- A48: Writing a model requires at least the code (the actual behavior)
assert ModelRequiresCode {
  SourceCode in S5_WriteModel.requires
}

-- A27: Report-only mode is valid — reconciliation can be the final deliverable
--      without proceeding to iterate. The gap report + plan IS the output.
assert ReportOnlyIsValid {
  ReconcileMode.reportOnly = Yes implies
    Reconciliation.producedBy = S9b_Reconcile
}

-- A22: OR-dependency is now modeled via RuntimeChoice (gap FIXED).
--   The choice resolves Java-or-Docker into a concrete requires set.
--   RunScript is always required; the runtime is chosen by D5.
assert RuntimeChoiceResolved {
  RunScript in S6_SetupTooling.requires
  and (LocalJava in S6_SetupTooling.requires or DockerEngine in S6_SetupTooling.requires)
}

-- A21: GAP — Iteration is not a loop.
--   The total order goes S10_Iterate → END. In reality, iterate feeds
--   back to S7_RunModel. util/ordering can't model cycles.
--   This assertion trivially holds — it documents the structural limitation.
assert IterationNotALoop {
  S10_Iterate = last
}


-- ================================================================
-- 11. CHECKS
-- ================================================================

-- Scope rationale: `one sig` atoms (25 artifacts, 13 steps) get exact counts
-- regardless of `for N`.  The bound only limits 10 unbounded sigs.
-- Facts force minimums: 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork,
-- 3 ArtifactVersion, 1+ Discrepancy/SelectedPattern/SystemElement/FreshnessCheck.
-- We use N=3 with `but` overrides for sigs that need more than 3 atoms.
-- No assertion needs >3 atoms of Discrepancy/SystemElement/SelectedPattern
-- to exhibit a counterexample; the `but` clauses cover forced minimums.

-- 12 checks moved to isolated modules for faster runs:
--   A31, A32 → skill_pipeline_boundary.als
--   A41, A42, A43 → skill_pipeline_quality.als
--   A33, A34, A35, A36, A37, A38, A50 → skill_pipeline_decisions.als
-- Remaining 38 checks require Step ordering / Artifact dependencies.

check DependenciesSatisfied      for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check SingleProducer             for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ModelRequiresPatterns      for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check RunRequiresModel           for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check RunRequiresTooling         for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check InterpretRequiresOutput    for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ExamplesNotRequiredForRun  for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ToolingIndependentOfSkill  for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check PatternsSyncedWithExamples for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check SkillMdCoversAllCategories for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check OutputIncludesChecks       for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check IterateRequiresInterpret   for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check InterpretExplainsCounterexamples for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReviewBeforeRun            for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReviewRequiresModel        for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check RunOutputStaleAfterIterate for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ModelRequiresClarifiedInput for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ToolingUsesExactlyOneRuntime for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check RuntimeChoiceResolved      for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check BoundaryReviewHasProofOfWork for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReconcileRequiresInterpretAndSpec for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReconcileBeforeIterate     for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check FixModelImpliesRerun       for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReconciliationNonTrivial   for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReportOnlyIsValid          for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ModelRequiresSourceSystem  for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReconcileRequiresIncludedSources for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check BoundaryReviewRequiresSource for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReconcileChecksIncludedSources for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check SkippedSourcesNotChecked   for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ModelRequiresCode          for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReportHasBidirectionalRefs for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ReportIsActionable         for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check QualityGateAtBoundaryReview for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check VaguePromptRequiresClarification for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ExampleSelectionRespectsBudget for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ExampleSelectionModeled    for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check IterationNotALoop          for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check EnforcementAuditRequired   for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check CodeSkipsEnforcementAudit  for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ConflictRequiresUserDecision for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion
check ConflictDoesNotImplyRerun for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion


-- ================================================================
-- 12. SCENARIO RUNS
-- ================================================================

-- S1: Happy path — all steps execute in order, all dependencies met
run HappyPath {
  #Step = 13
  all s: Step, a: s.requires | lte[a.producedBy, s]
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion, 6 Int

-- S2: Pattern selection step consults patterns.md
run PatternSelectionWorks {
  some s: Step | s.readsPatterns = Yes and PatternsMd in s.requires
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S3: All three examples cover different pattern categories
run ExamplesCoverDifferentDomains {
  some pc1, pc2, pc3: PatternCoverage |
    pc1.example = StaticExample
    and pc2.example = TemporalExample
    and pc3.example = UxExample
    and pc1.patterns != pc2.patterns
    and pc2.patterns != pc3.patterns
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S4: Iterate step has access to everything needed to fix the model
run IterateHasFullContext {
  some s: Step | s = S10_Iterate
    and Interpretation in s.requires
    and UserModel in s.requires
    and PatternsMd in s.requires
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S5: Tooling uses local Java (no Docker needed)
run ToolingWithLocalJava {
  RuntimeChoice.chosen = UseLocalJava
  and LocalJava in S6_SetupTooling.requires
  and DockerEngine not in S6_SetupTooling.requires
  and SkillMd not in S6_SetupTooling.requires
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S5b: Tooling falls back to Docker (no local Java)
run ToolingWithDockerFallback {
  RuntimeChoice.chosen = UseDocker
  and DockerEngine in S6_SetupTooling.requires
  and LocalJava not in S6_SetupTooling.requires
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S6: GAP — after iterate, can we interpret without re-running?
-- This should be SAT because the model allows it (no temporal constraint),
-- exposing that the iteration loop needs an explicit "re-run" gate.
run InterpretWithoutRerun {
  Interpretation.producedBy = S9_Interpret
  and UserModel.mutable = Yes
  and some v1, v2: ArtifactVersion |
    v1.artifact = UserModel and v2.artifact = UserModel
    and v1.version < v2.version
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion, 6 Int

-- S7: Are any pattern categories still uncovered by examples?
-- With all 5 examples, this should now be UNSAT (gap closed).
run UncoveredCategories {
  some cat: PatternCategory |
    (some smc: SkillMdCoverage | cat in smc.mentionedCategories)
    and (no pc: PatternCoverage | cat in pc.patterns)
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S8: All five reconciliation outcomes co-exist
run AllReconcileOutcomes {
  some d1, d2, d3, d4, d5: Discrepancy |
    d1.outcome = FixSource           -- model correct → fix source
    and d2.outcome = FixModelToCode  -- code changed → model tracks as-is
    and d3.outcome = FixModelToIntent -- spec updated → model tracks intent
    and d4.outcome = Conflict        -- sources contradict → user decides
    and d5.outcome = Exclusion       -- conscious exclusion
    and d1 != d2 and d1 != d3 and d1 != d4 and d1 != d5
    and d2 != d3 and d2 != d4 and d2 != d5
    and d3 != d4 and d3 != d5
    and d4 != d5
} for 3 but exactly 5 Discrepancy, 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S8b: Conflict — code and spec disagree, user must decide
run ConflictBetweenSources {
  some d: Discrepancy | d.outcome = Conflict and d.direction = UserDecides
  and some d: Discrepancy | d.outcome = FixSource
} for 3 but exactly 2 Discrepancy, 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S9: Reconciliation with only FixSource (happy path — model is fully current)
run ReconcileTextOnly {
  all d: Discrepancy | d.outcome = FixSource
} for 3 but exactly 2 Discrepancy, 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S10: Report-only mode — user stops at gap report, no iterate
run ReportOnlyMode {
  ReconcileMode.reportOnly = Yes
  and some d: Discrepancy | d.outcome = FixSource
  and some d: Discrepancy | d.outcome = Exclusion
} for 3 but exactly 2 Discrepancy, 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- S11: System evolution — team ships a change, model drifts from source
--   SourceSystem v2 exists but UserModel was only written against v1.
--   The reconciliation step should catch this: FixModelToCode outcome.
run SystemEvolutionDrift {
  modelSourceDrift
  and some d: Discrepancy | d.outcome = FixModelToCode and d.claim = UserModel
} for 5 but exactly 1 Discrepancy, 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 5 ArtifactVersion, 6 Int

-- AllBoundaryDecisions → skill_pipeline_boundary.als

-- S12: Re-entry after system change — full pipeline re-run with updated source
run ReverifyAfterChange {
  SourceSystem in S5_WriteModel.requires
  and SourceSystem in S5b_ReviewBounds.requires
  and IncludedSources in S9b_Reconcile.requires
  and (all sa: SourceArtifact | sa.mutable = Yes)
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion

-- Partial reconciliation: code + spec only, tests and docs skipped
run PartialReconciliation {
  SourceCode.includedInReconciliation = Yes
  and SourceSpec.includedInReconciliation = Yes
  and SourceTests.includedInReconciliation = No
  and SourceDocs.includedInReconciliation = No
  and SourceCode in S9b_Reconcile.requires
  and SourceSpec in S9b_Reconcile.requires
  and SourceTests not in S9b_Reconcile.requires
  and SourceDocs not in S9b_Reconcile.requires
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion, 6 Int

-- Full reconciliation: all four sources included
run FullReconciliation {
  all sa: SourceArtifact | sa.includedInReconciliation = Yes
  and SourceSystem in S9b_Reconcile.requires
} for 3 but 5 PatternCoverage, 5 ExampleRelevance, 4 ProofOfWork, 4 ArtifactVersion, 6 Int

-- ================================================================
-- CRITICAL DECISION & QUALITY SCENARIOS
-- Moved to isolated modules for faster runs:
--   Decision scenarios → skill_pipeline_decisions.als
--   Quality scenarios  → skill_pipeline_quality.als
-- ================================================================
