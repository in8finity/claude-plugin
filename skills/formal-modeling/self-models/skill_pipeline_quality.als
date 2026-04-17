-- ================================================================
-- Quality Gate — isolated module (no pipeline dependency)
--
-- Verifies that both Guided and Free modeling modes produce models
-- meeting minimum quality requirements (facts, assertions, runs).
-- Guided mode additionally requires module declaration + doc comments.
--
-- Extracted from skill_pipeline.als for faster solver runs.
-- ================================================================

module skill_pipeline_quality

abstract sig ModelProperty {}
one sig HasModuleDecl    extends ModelProperty {}
one sig HasFacts         extends ModelProperty {}
one sig HasAssertions    extends ModelProperty {}
one sig HasRunScenarios  extends ModelProperty {}
one sig HasDocComment    extends ModelProperty {}

one sig ModelQuality {
  properties: set ModelProperty
}

abstract sig ModelingMode {}
one sig Guided extends ModelingMode {}
one sig Free   extends ModelingMode {}

one sig ModeConfig {
  mode: one ModelingMode
}

fact MinimumQuality {
  HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
}

fact FreeModeMeetsMinimum {
  ModeConfig.mode = Free implies
    HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
}

fact GuidedModeFullQuality {
  ModeConfig.mode = Guided implies
    ModelQuality.properties = HasModuleDecl + HasFacts + HasAssertions + HasRunScenarios + HasDocComment
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

check BothModesMeetQuality    for 6
check GuidedModeHigherQuality for 6
check FreeModeIsValid         for 6

-- Free mode: model produced directly, meets minimum quality
run FreeModeSatisfiable {
  ModeConfig.mode = Free
  and HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
} for 6

-- Guided mode: full quality including docs
run GuidedModeFullQualityScenario {
  ModeConfig.mode = Guided
  and ModelQuality.properties = HasModuleDecl + HasFacts + HasAssertions + HasRunScenarios + HasDocComment
} for 6

-- Free mode with minimal quality (no doc comment, no module decl) — still valid
run FreeMinimalButValid {
  ModeConfig.mode = Free
  and HasDocComment not in ModelQuality.properties
  and HasModuleDecl not in ModelQuality.properties
  and HasFacts + HasAssertions + HasRunScenarios in ModelQuality.properties
} for 6
