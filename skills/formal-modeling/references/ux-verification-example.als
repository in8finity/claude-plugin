-- ================================================================
-- Task Lifecycle — UX & Notification Verification (generic example)
--
-- Demonstrates formal verification of the full UX layer:
--   • State machine (draft/review/active/paused/done/cancelled)
--   • Role-based action guards (who can trigger which transition)
--   • Field write access (role × state × field → writable?)
--   • Field read access (role × state × field → visible?)
--   • Approval mechanics (both-sides approval gate)
--   • Notification recipient sets per transition
--   • CTA validity (button in email → is the action available?)
--   • Gap assertions (intentionally failing checks for known bugs)
--
-- Checks (12 assertions):
--   A1  NoDeadEndsExceptTerminal       — every non-terminal state has an exit
--   A2  AllRequiredFieldsSettable      — required fields writable before submission
--   A3  ViewerCannotWrite              — read-only role has zero write access
--   A4  ViewerCannotReadCosts          — viewer never sees internal cost fields
--   A5  ActivateWhenBothApproved       — activate available once both sides approve
--   A6  TerminalStatesHaveNoExit       — Done/Cancelled are terminal
--   A7  OnlyOwnerCanCancel             — cancel restricted to owner/admin
--   C1  AllCtasValidForRecipient       — EXPECTED FAIL: gap assertion
--   C2  ApproveCtaOnlyForApprovers     — approve button only for approving roles
--   C3  ApproveCtaOnlyWhenPending      — no approve button after already approved
--   C4  TerminalNotificationsNoAction  — no action CTAs in terminal emails
--   C5  ViewerOnlyNotifiedWhenVisible  — hidden tasks don't notify viewers
-- ================================================================

module task_lifecycle


-- ================================================================
-- 1. ROLES
-- ================================================================

abstract sig Role {}

one sig Admin      extends Role {}  -- internal superuser
one sig Manager    extends Role {}  -- operations manager (internal side)
one sig Owner      extends Role {}  -- task owner (client side)
one sig Viewer     extends Role {}  -- read-only observer (no costs, no writes)
one sig Author     extends Role {}  -- task creator (client side)
one sig Contact    extends Role {}  -- secondary contact


-- ================================================================
-- 2. STATES
-- ================================================================

abstract sig State {}

one sig Draft     extends State {}  -- initial; filling fields
one sig Review    extends State {}  -- submitted; awaiting approval
one sig Active    extends State {}  -- work in progress; most fields frozen
one sig Paused    extends State {}  -- paused; full edit re-opens
one sig Done      extends State {}  -- terminal: completed
one sig Cancelled extends State {}  -- terminal: abandoned

pred terminal[s: State]      { s = Done or s = Cancelled }
pred editable[s: State]      { s = Draft or s = Review or s = Paused }


-- ================================================================
-- 3. FIELDS
-- ================================================================

abstract sig Field {}

-- General fields — required to leave Draft
one sig Title         extends Field {}
one sig Description   extends Field {}
one sig Priority      extends Field {}
one sig Deadline      extends Field {}
one sig Assignee      extends Field {}
one sig Category      extends Field {}
one sig Attachments   extends Field {}
one sig CustomFields  extends Field {}

-- Internal-only fields — hidden from client roles
one sig CostBreakdown extends Field {}  -- internal pricing
one sig InternalNotes extends Field {}  -- internal-only notes
one sig BillingRef    extends Field {}  -- billing reference number

-- Visibility toggle
one sig HideFromViewer extends Field {}  -- only manager/admin can toggle

-- Approval tracking (editable in Active)
one sig Approvals     extends Field {}

-- Derived field sets
fun required : set Field {
  Title + Description + Priority + Deadline +
  Assignee + Category + CustomFields
}

fun internalOnly : set Field {
  CostBreakdown + InternalNotes + BillingRef
}

fun activeAllowed : set Field {
  BillingRef + Attachments + Approvals
}


-- ================================================================
-- 4. APPROVAL STATE
-- ================================================================

abstract sig Bool {}
one sig True  extends Bool {}
one sig False extends Bool {}

sig ApprovalState {
  clientApproved  : one Bool,
  managerApproved : one Bool
}

pred bothApproved[a: ApprovalState] {
  a.clientApproved = True and a.managerApproved = True
}


-- ================================================================
-- 5. TASK
-- ================================================================

sig Task {
  state           : one State,
  approvalState   : one ApprovalState,
  autoApproved    : one Bool,     -- pre-approved workflow (skip approval gate)
  filled          : set Field,    -- fields that have been provided
  hiddenFromViewer: one Bool,
  estimatable     : one Bool      -- cost estimation feature enabled
}

pred hasRequired[t: Task] { required in t.filled }

pred canProgress[t: Task] {
  bothApproved[t.approvalState] or t.autoApproved = True
}


-- ================================================================
-- 6. FIELD WRITE ACCESS
--    Role × State × Field → writable?
-- ================================================================

pred canWrite[r: Role, t: Task, f: Field] {

  -- Admin: unrestricted
  r = Admin

  or

  -- Manager: all fields in editable states; only activeAllowed in Active;
  --          only BillingRef in terminal states
  (r = Manager and (
    editable[t.state]
    or (t.state = Active and f in activeAllowed)
    or (terminal[t.state] and f = BillingRef)
  ))

  or

  -- Owner: non-internal, non-HideFromViewer in editable states;
  --        activeAllowed minus internal in Active
  (r = Owner
    and f not in internalOnly
    and f != HideFromViewer
    and (
      editable[t.state]
      or (t.state = Active and f in activeAllowed)
    )
  )

  or

  -- Author / Contact: non-internal in editable states only
  ((r = Author or r = Contact)
    and f not in internalOnly
    and f != HideFromViewer
    and editable[t.state]
  )

  -- Viewer: no write access (no branch → always false)
}


-- ================================================================
-- 7. FIELD READ ACCESS
--    Role × State × Field → visible?
-- ================================================================

pred canRead[r: Role, t: Task, f: Field] {

  -- Admin, Manager, Owner: full visibility
  (r = Admin or r = Manager or r = Owner)

  or

  -- Viewer: all except internal + HideFromViewer, blocked if hidden
  (r = Viewer
    and f not in internalOnly
    and f != HideFromViewer
    and t.hiddenFromViewer = False
  )

  or

  -- Author / Contact: all except internal
  ((r = Author or r = Contact)
    and f not in internalOnly
  )
}


-- ================================================================
-- 8. TRANSITIONS (action guards)
-- ================================================================

pred t_submit[r: Role, t: Task] {
  t.state = Draft
  and hasRequired[t]
  and r != Viewer
}

pred t_backToDraft[r: Role, t: Task] {
  t.state = Review
  and (r = Admin or r = Owner or r = Manager or r = Author)
}

pred t_approve[r: Role, t: Task] {
  (t.state = Review or t.state = Active or t.state = Paused)
  and (r = Admin or r = Owner or r = Manager)
}

pred t_activate[r: Role, t: Task] {
  (t.state = Review or t.state = Paused)
  and canProgress[t]
  and (r = Admin or r = Owner or r = Author)
}

pred t_pause[r: Role, t: Task] {
  t.state = Active
  and (r = Admin or r = Owner or r = Manager)
}

pred t_finish[r: Role, t: Task] {
  (t.state = Active or t.state = Paused)
  and bothApproved[t.approvalState]
  and (r = Admin or r = Owner)
}

pred t_cancel[r: Role, t: Task] {
  (t.state = Active or t.state = Paused)
  and (r = Admin or r = Owner)
}

pred anyTransition[t: Task] {
  some r: Role |
    t_submit[r, t] or t_backToDraft[r, t] or t_approve[r, t]
    or t_activate[r, t] or t_pause[r, t] or t_finish[r, t]
    or t_cancel[r, t]
}


-- ================================================================
-- 9. NOTIFICATION RECIPIENTS
-- ================================================================

fun notifySubmit[t: Task] : set Role {
  Manager + Owner + Author
  + (t.hiddenFromViewer = False implies Viewer else none)
}

fun notifyStateChange : set Role {
  Manager + Owner + Author
}

fun notifyFieldChange[t: Task] : set Role {
  Manager + Owner + Author
  + ((t.state = Review or t.state = Paused) and t.hiddenFromViewer = False
     implies Viewer else none)
}


-- ================================================================
-- 10. STRUCTURAL ASSERTIONS
-- ================================================================

-- A1: No non-terminal state is a dead end
assert NoDeadEndsExceptTerminal {
  all t: Task |
    not terminal[t.state] implies (
      (t.state = Draft implies
        (hasRequired[t] implies some r: Role | t_submit[r, t]))
      and (t.state = Review implies some r: Role | t_backToDraft[r, t])
      and (t.state = Active implies
        (some r: Role | t_pause[r, t]) and (some r: Role | t_cancel[r, t]))
      and (t.state = Paused implies some r: Role | t_cancel[r, t])
    )
}

-- A2: Required fields writable by at least one non-viewer role in draft/review
assert AllRequiredFieldsSettable {
  all f: required, t: Task |
    (t.state = Draft or t.state = Review)
    implies some r: Role - Viewer | canWrite[r, t, f]
}

-- A3: Viewer has zero write access
assert ViewerCannotWrite {
  all t: Task, f: Field | not canWrite[Viewer, t, f]
}

-- A4: Viewer cannot read internal cost fields
assert ViewerCannotReadCosts {
  all t: Task, f: internalOnly | not canRead[Viewer, t, f]
}

-- A5: Activate available when both sides approve in Review/Paused
assert ActivateWhenBothApproved {
  all t: Task |
    ((t.state = Review or t.state = Paused) and bothApproved[t.approvalState])
    implies t_activate[Owner, t]
}

-- A6: Terminal states have no outgoing transitions
assert TerminalStatesHaveNoExit {
  all t: Task | terminal[t.state] implies {
    no r: Role | t_submit[r, t]
    no r: Role | t_backToDraft[r, t]
    no r: Role | t_activate[r, t]
    no r: Role | t_pause[r, t]
    no r: Role | t_finish[r, t]
    no r: Role | t_cancel[r, t]
  }
}

-- A7: Only owner/admin can cancel
assert OnlyOwnerCanCancel {
  all t: Task, r: Role |
    t_cancel[r, t] implies (r = Owner or r = Admin)
}


-- ================================================================
-- 11. CTA TYPES & VALIDITY
-- ================================================================

abstract sig Cta {}
one sig CtaView     extends Cta {}  -- link to task (always present)
one sig CtaApprove  extends Cta {}  -- "Approve" button
one sig CtaEstimate extends Cta {}  -- "Fill estimate" (viewer only)

-- Notification templates
abstract sig Template {}
one sig TmplSubmitted      extends Template {}  -- draft→review
one sig TmplActivated      extends Template {}  -- →active
one sig TmplPaused         extends Template {}  -- →paused
one sig TmplDone           extends Template {}  -- →done
one sig TmplCancelled      extends Template {}  -- →cancelled
one sig TmplBackToDraft    extends Template {}  -- review→draft
one sig TmplFieldChanged   extends Template {}  -- field change
one sig TmplCostChanged    extends Template {}  -- cost field change
one sig TmplViewerNotify   extends Template {}  -- viewer-specific notification

-- Template trigger states
fun triggerStates[tmpl: Template] : set State {
  { s: State |
    (s = Review    and tmpl in TmplSubmitted + TmplViewerNotify) or
    (s = Active    and tmpl = TmplActivated) or
    (s = Paused    and tmpl = TmplPaused) or
    (s = Done      and tmpl = TmplDone) or
    (s = Cancelled and tmpl = TmplCancelled) or
    (s = Draft     and tmpl = TmplBackToDraft) or
    (s in Review + Active + Paused
     and tmpl in TmplFieldChanged + TmplCostChanged)
  }
}

-- Approval pending
pred clientApprovalPending[t: Task]  { t.approvalState.clientApproved  = False }
pred managerApprovalPending[t: Task] { t.approvalState.managerApproved = False }

pred approvalPendingFor[r: Role, t: Task] {
  (r = Owner   and clientApprovalPending[t])  or
  (r = Manager and managerApprovalPending[t]) or
  (r = Admin)
}

-- Template → CTA mapping
fun templateCtasFor[tmpl: Template, r: Role, t: Task] : set Cta {
  { c: Cta |
    -- CtaView: always present
    (c = CtaView)
    or
    -- CtaApprove: only in approval-relevant templates, only for approving roles
    (c = CtaApprove
     and (r = Owner or r = Manager or r = Admin)
     and t_approve[r, t]
     and approvalPendingFor[r, t]
     and tmpl in TmplCostChanged + TmplSubmitted + TmplPaused)
    or
    -- CtaEstimate: viewer gets estimate CTA in viewer notification
    -- GAP: included unconditionally, but only valid when estimatable=True
    (c = CtaEstimate
     and tmpl = TmplViewerNotify
     and r = Viewer)
  }
}

-- CTA validity
pred ctaValid[c: Cta, r: Role, t: Task] {
  (c = CtaView)
  or
  (c = CtaApprove and t_approve[r, t])
  or
  -- CtaEstimate only valid when estimation feature is enabled
  (c = CtaEstimate and r = Viewer and t.estimatable = True)
}


-- ================================================================
-- 12. NOTIFICATION / CTA ASSERTIONS
-- ================================================================

-- C1: Every CTA in a notification is valid for its recipient.
--     EXPECTED FAIL: viewer gets CtaEstimate when estimatable=False
--     This counterexample documents the known gap.
assert AllCtasValidForRecipient {
  all tmpl: Template, r: Role, t: Task |
    t.state in triggerStates[tmpl]
    implies all c: templateCtasFor[tmpl, r, t] | ctaValid[c, r, t]
}

-- C2: CtaApprove only sent to approving roles
assert ApproveCtaOnlyForApprovers {
  all tmpl: Template, r: Role, t: Task |
    CtaApprove in templateCtasFor[tmpl, r, t]
    implies (r = Owner or r = Manager or r = Admin)
}

-- C3: CtaApprove only when recipient hasn't already approved
assert ApproveCtaOnlyWhenPending {
  all tmpl: Template, r: Role, t: Task |
    CtaApprove in templateCtasFor[tmpl, r, t]
    implies approvalPendingFor[r, t]
}

-- C4: Terminal notifications have no action CTAs
assert TerminalNotificationsNoAction {
  all r: Role, t: Task |
    terminal[t.state] implies {
      CtaApprove  not in templateCtasFor[TmplDone,      r, t]
      CtaApprove  not in templateCtasFor[TmplCancelled, r, t]
      CtaEstimate not in templateCtasFor[TmplDone,      r, t]
      CtaEstimate not in templateCtasFor[TmplCancelled, r, t]
    }
}

-- C5: Viewer only notified when task is visible
assert ViewerOnlyNotifiedWhenVisible {
  all t: Task |
    t.hiddenFromViewer = True implies {
      Viewer not in notifySubmit[t]
      Viewer not in notifyFieldChange[t]
    }
}


-- ================================================================
-- 13. CHECKS
-- ================================================================

check NoDeadEndsExceptTerminal      for 6
check AllRequiredFieldsSettable     for 6
check ViewerCannotWrite             for 6
check ViewerCannotReadCosts         for 6
check ActivateWhenBothApproved      for 6
check TerminalStatesHaveNoExit      for 6
check OnlyOwnerCanCancel            for 6
check AllCtasValidForRecipient      for 6  -- expected FAIL: estimatable gap
check ApproveCtaOnlyForApprovers    for 6
check ApproveCtaOnlyWhenPending     for 6
check TerminalNotificationsNoAction for 6
check ViewerOnlyNotifiedWhenVisible for 6


-- ================================================================
-- 14. SCENARIO RUNS
-- ================================================================

-- S1: Happy path — author fills fields and submits
run DraftReadyToSubmit {
  some t: Task |
    t.state = Draft and hasRequired[t] and t_submit[Author, t]
} for 4

-- S2: Both sides can approve
run BothSidesCanApprove {
  some t: Task |
    t.state = Review and t_approve[Owner, t] and t_approve[Manager, t]
} for 4

-- S3: Approval enables activation
run ApprovalEnablesActivation {
  some t: Task |
    t.state = Review and bothApproved[t.approvalState]
    and t_activate[Owner, t]
} for 4

-- S4: Active has exit (pause + cancel)
run ActiveHasExit {
  some t: Task |
    t.state = Active and t_pause[Owner, t] and t_cancel[Owner, t]
} for 4

-- S5: Approve CTA in cost-change email for pending approver
run ApproveCtaInCostChange {
  some t: Task |
    t.state = Review and clientApprovalPending[t]
    and CtaApprove in templateCtasFor[TmplCostChanged, Owner, t]
} for 4

-- S6: No approve CTA for non-approving roles
run NoApproveCtaForAuthor {
  some t: Task |
    t.state = Review
    and CtaApprove not in templateCtasFor[TmplCostChanged, Author, t]
} for 4

-- S7: GAP WITNESS — CtaEstimate present but invalid
run EstimateCtaInvalidGap {
  some t: Task |
    t.state = Review and t.hiddenFromViewer = False
    and t.estimatable = False
    and CtaEstimate in templateCtasFor[TmplViewerNotify, Viewer, t]
    and not ctaValid[CtaEstimate, Viewer, t]
} for 4

-- S8: Viewer excluded when hidden
run ViewerExcludedWhenHidden {
  some t: Task |
    t.hiddenFromViewer = True
    and Viewer not in notifySubmit[t]
    and Viewer not in notifyFieldChange[t]
} for 4
