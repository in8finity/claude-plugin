module fdp_skip_protocol

/*
 * Segment 3: TC24 Skip Protocol (Micro-temporal)
 *
 * Proves the propose → acknowledge → writeSkipEntry ordering invariant for
 * formal model skipping. Three DISTINCT temporal steps:
 *   1. propose       — Claude asks for acknowledgement
 *   2. acknowledge   — User replies affirmatively (later turn)
 *   3. writeSkipEntry — Claude logs M1 with verbatim Acknowledgement field
 *                       (yet another turn)
 *
 * Silent skip (acknowledge without proposal) and in-turn entry (log entry
 * in the same step as acknowledgement) are both structurally impossible.
 *
 * Interface contract: tc24_satisfied iff
 *   modelBuilt = True OR (proposed AND acknowledged AND entryLogged)
 * The temporal core collapses the skip path to a single var Bool
 * (modelOrSkipReady), justified by the safety assertions below.
 */

-- ============================================================
-- Domain (self-contained)
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

-- Model build status (immutable choice — you either build or skip)
abstract sig ModelChoice {}
one sig Build, Skip extends ModelChoice {}

one sig Protocol {
  var proposed: one Bool,       -- Claude proposed to skip
  var acknowledged: one Bool,   -- User accepted the skip
  var entryLogged: one Bool,    -- Skip entry written with verbatim Acknowledgement field
  var modelBuilt: one Bool,     -- Model was actually built
  var atModelStep: one Bool     -- Currently at S1_Model
}

-- ============================================================
-- Initial state
-- ============================================================

fact Init {
  Protocol.proposed = False
  Protocol.acknowledged = False
  Protocol.entryLogged = False
  Protocol.modelBuilt = False
  Protocol.atModelStep = True  -- start at model step
}

-- ============================================================
-- Frame conditions
-- ============================================================

pred frameAll {
  Protocol.proposed' = Protocol.proposed
  Protocol.acknowledged' = Protocol.acknowledged
  Protocol.entryLogged' = Protocol.entryLogged
  Protocol.modelBuilt' = Protocol.modelBuilt
  Protocol.atModelStep' = Protocol.atModelStep
}

pred stutter { frameAll }

-- ============================================================
-- Transitions
-- ============================================================

-- Claude proposes to skip (only at model step, only once)
-- The propose step does NOT advance past model step; acknowledgement + entry
-- must happen in subsequent turns. This models the "different turn" rule.
pred propose {
  Protocol.atModelStep = True
  Protocol.proposed = False
  Protocol.proposed' = True
  Protocol.acknowledged' = Protocol.acknowledged
  Protocol.entryLogged' = Protocol.entryLogged
  Protocol.modelBuilt' = Protocol.modelBuilt
  Protocol.atModelStep' = Protocol.atModelStep
}

-- User acknowledges skip in a later turn (only after proposal).
-- Acknowledgement does NOT yet satisfy TC24; the skip entry with the
-- verbatim Acknowledgement field must still be written.
pred acknowledge {
  Protocol.atModelStep = True
  Protocol.proposed = True
  Protocol.acknowledged = False
  Protocol.acknowledged' = True
  Protocol.entryLogged' = Protocol.entryLogged
  Protocol.modelBuilt' = Protocol.modelBuilt
  Protocol.proposed' = Protocol.proposed
  Protocol.atModelStep' = Protocol.atModelStep
}

-- Claude writes M1: Skipped entry with verbatim Acknowledgement field.
-- This MUST be a distinct step from acknowledge (different turn than the
-- user's reply). Only after entryLogged is TC24 satisfied via skip path.
pred writeSkipEntry {
  Protocol.atModelStep = True
  Protocol.proposed = True
  Protocol.acknowledged = True
  Protocol.entryLogged = False
  Protocol.entryLogged' = True
  Protocol.atModelStep' = False  -- advance past model step
  Protocol.proposed' = Protocol.proposed
  Protocol.acknowledged' = Protocol.acknowledged
  Protocol.modelBuilt' = False   -- model NOT built
}

-- Build the model (alternative to skipping).
-- Guard: cannot build once skip has been acknowledged — protocol commits
-- to the skip path at that point.
pred buildModel {
  Protocol.atModelStep = True
  Protocol.modelBuilt = False
  Protocol.acknowledged = False
  Protocol.modelBuilt' = True
  Protocol.atModelStep' = False  -- advance past model step
  Protocol.proposed' = Protocol.proposed
  Protocol.acknowledged' = Protocol.acknowledged
  Protocol.entryLogged' = Protocol.entryLogged
}

-- User rejects skip proposal (Claude must build)
pred rejectSkip {
  Protocol.atModelStep = True
  Protocol.proposed = True
  Protocol.acknowledged = False
  -- Rejection clears the proposal; Claude must build
  Protocol.proposed' = False
  Protocol.acknowledged' = False
  Protocol.entryLogged' = Protocol.entryLogged
  Protocol.modelBuilt' = Protocol.modelBuilt
  Protocol.atModelStep' = Protocol.atModelStep
}

fact Transitions {
  always (
    stutter
    or propose
    or acknowledge
    or writeSkipEntry
    or buildModel
    or rejectSkip
  )
}

-- ============================================================
-- The TC24 contract predicate
-- ============================================================

-- Skip path requires three distinct temporal steps:
--   propose → acknowledge → writeSkipEntry
-- "entryLogged" represents the M1 entry with verbatim Acknowledgement field,
-- which per SKILL.md must live in a turn AFTER the acknowledgement reply.
pred tc24_satisfied {
  Protocol.modelBuilt = True
  or (Protocol.proposed = True
      and Protocol.acknowledged = True
      and Protocol.entryLogged = True)
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- TC24-S1: Skip acknowledgement always requires prior proposal
assert NoSilentSkip {
  always (Protocol.acknowledged = True => Protocol.proposed = True)
}
check NoSilentSkip for 4 but 6 steps

-- TC24-S2: Acknowledged skip implies model was NOT built
assert SkipMeansNoModel {
  always (Protocol.acknowledged = True => Protocol.modelBuilt = False)
}
check SkipMeansNoModel for 4 but 6 steps

-- TC24-S3: If past model step, either model was built or skip was acknowledged
assert PastModelStepSatisfied {
  always (Protocol.atModelStep = False => tc24_satisfied)
}
check PastModelStepSatisfied for 4 but 6 steps

-- TC24-S4: Building the model satisfies TC24
assert BuildSatisfiesTC24 {
  always (Protocol.modelBuilt = True => tc24_satisfied)
}
check BuildSatisfiesTC24 for 4 but 6 steps

-- TC24-S5: Cannot acknowledge without proposing first
-- (structurally enforced by the acknowledge guard)
assert AcknowledgeRequiresProposal {
  always (Protocol.acknowledged' = True and Protocol.acknowledged = False
    => Protocol.proposed = True)
}
check AcknowledgeRequiresProposal for 4 but 6 steps

-- TC24-S6: Skip entry requires prior acknowledgement (enforces verbatim-quote
-- rule: the entry's Acknowledgement field can only be written after the user
-- has actually acknowledged).
assert EntryRequiresAcknowledgement {
  always (Protocol.entryLogged = True => Protocol.acknowledged = True)
}
check EntryRequiresAcknowledgement for 4 but 8 steps

-- TC24-S7: Skip entry must be in a DIFFERENT step from acknowledgement.
-- The entry-write transition only fires when acknowledged was already True,
-- which means entryLogged cannot flip True in the same step as acknowledged.
assert EntryNotSameStepAsAcknowledgement {
  always (
    (Protocol.acknowledged = False and Protocol.acknowledged' = True)
      => Protocol.entryLogged' = False
  )
}
check EntryNotSameStepAsAcknowledgement for 4 but 8 steps

-- TC24-S8: Skip path satisfies TC24 only after all three steps have fired.
assert SkipPathRequiresAllThreeSteps {
  always (
    (Protocol.modelBuilt = False and tc24_satisfied)
      => (Protocol.proposed = True
          and Protocol.acknowledged = True
          and Protocol.entryLogged = True)
  )
}
check SkipPathRequiresAllThreeSteps for 4 but 8 steps

-- ============================================================
-- Scenarios
-- ============================================================

-- Happy path: build model directly
run BuildPath {
  eventually (Protocol.modelBuilt = True and Protocol.atModelStep = False)
} for 4 but 4 steps

-- Skip path: propose → acknowledge → writeSkipEntry (three distinct steps)
run SkipPath {
  eventually (Protocol.entryLogged = True and Protocol.atModelStep = False)
} for 4 but 6 steps

-- Reject path: propose → reject → build
run RejectThenBuild {
  eventually (Protocol.proposed = True
    and eventually (Protocol.proposed = False
      and eventually (Protocol.modelBuilt = True)))
} for 4 but 6 steps
