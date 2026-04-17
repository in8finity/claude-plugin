-- ================================================================
-- Boundary Decisions — isolated module (no pipeline dependency)
--
-- Verifies that boundary review decisions are well-formed:
-- risky exclusions have gap assertions, and at least one element
-- is included in the model.
--
-- Extracted from skill_pipeline.als for faster solver runs.
-- ================================================================

module skill_pipeline_boundary

abstract sig Bool {}
one sig Yes, No extends Bool {}

abstract sig BoundaryDecision {}
one sig Include extends BoundaryDecision {}
one sig ExcludeSafe extends BoundaryDecision {}
one sig ExcludeRisky extends BoundaryDecision {}
one sig Stub extends BoundaryDecision {}

sig SystemElement {
  decision: one BoundaryDecision,
  hasGapAssertion: one Bool
}

fact RiskyExclusionsDocumented {
  all e: SystemElement | e.decision = ExcludeRisky implies e.hasGapAssertion = Yes
}

fact SomeElementsIncluded {
  some e: SystemElement | e.decision = Include
}

-- A31: Risky exclusions must have documenting gap assertions
assert RiskyExclusionsHaveGapAssertions {
  all e: SystemElement | e.decision = ExcludeRisky implies e.hasGapAssertion = Yes
}

-- A32: Model is non-empty (at least one system element included)
assert ModelNonEmpty {
  some e: SystemElement | e.decision = Include
}

check RiskyExclusionsHaveGapAssertions for 6
check ModelNonEmpty                    for 6

-- All four boundary decisions co-exist
run AllBoundaryDecisions {
  some e1, e2, e3, e4: SystemElement |
    e1.decision = Include
    and e2.decision = ExcludeSafe
    and e3.decision = ExcludeRisky and e3.hasGapAssertion = Yes
    and e4.decision = Stub
    and e1 != e2 and e2 != e3 and e3 != e4 and e1 != e3 and e1 != e4 and e2 != e4
} for exactly 4 SystemElement
