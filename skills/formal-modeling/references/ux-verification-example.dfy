/**
 * UX/Access Control Verification — Dafny port
 *
 * Ported from references/ux-verification-example.als.
 *
 * Roles: Admin, Manager, Owner, Viewer, Author, Contact
 * States: Draft, Review, Active, Paused, Done, Cancelled
 * Fields: Title, Description, Priority, Deadline, etc.
 *
 * Verifies role×state×field access matrix and CTA validity.
 */

// ============================================================
// Enums
// ============================================================

datatype Role = Admin | Manager | Owner | Viewer | Author | Contact

datatype TaskState = Draft | Review | Active | Paused | Done | Cancelled

datatype Field =
  | Title | Description | Priority | Deadline | Assignee
  | Category | Attachments | CustomFields
  | CostBreakdown | InternalNotes | BillingRef
  | HideFromViewer | Approvals

datatype Cta = CtaApprove | CtaReject | CtaEstimate | CtaView

datatype NotificationTemplate = CostChange | StatusUpdate | TaskCreated | ApprovalRequest

// ============================================================
// State classification
// ============================================================

predicate terminal(s: TaskState) { s == Done || s == Cancelled }
predicate editable(s: TaskState) { s == Draft || s == Review || s == Paused }

predicate isRequired(f: Field) {
  f == Title || f == Description || f == Priority || f == Deadline
}

predicate isInternalOnly(f: Field) {
  f == CostBreakdown || f == InternalNotes || f == BillingRef
}

predicate isActiveAllowed(f: Field) {
  f == Priority || f == Deadline || f == Attachments
}

// ============================================================
// Access control: canWrite predicate
// ============================================================

predicate canWrite(r: Role, s: TaskState, f: Field)
{
  // Admin: full access in editable states + internal always
  (r == Admin) ||
  // Manager: editable states, or active-allowed in Active
  (r == Manager && (editable(s) || (s == Active && isActiveAllowed(f)))) ||
  // Owner: editable states except internal-only
  (r == Owner && !isInternalOnly(f) && editable(s)) ||
  // Author: Draft only, non-internal
  (r == Author && !isInternalOnly(f) && s == Draft) ||
  // Viewer: no write access ever
  // Contact: no write access
  false
}

predicate canRead(r: Role, f: Field)
{
  // Viewer cannot see cost fields
  (r == Viewer && !isInternalOnly(f)) ||
  // Everyone else can see everything
  (r != Viewer)
}

// ============================================================
// Transitions
// ============================================================

predicate validTransition(from: TaskState, to: TaskState)
{
  match (from, to) {
    case (Draft, Review)     => true
    case (Review, Active)    => true
    case (Review, Draft)     => true   // rejection
    case (Active, Paused)    => true
    case (Active, Done)      => true
    case (Paused, Active)    => true
    case (Paused, Draft)     => true   // full re-edit
    case (Draft, Cancelled)  => true
    case (Review, Cancelled) => true
    case _ => false
  }
}

predicate canTransition(r: Role, from: TaskState, to: TaskState)
{
  validTransition(from, to) &&
  match (from, to) {
    // Only Owner can cancel
    case (_, Cancelled) => r == Owner || r == Admin
    // Only Manager/Admin can approve (Review → Active)
    case (Review, Active) => r == Manager || r == Admin
    // Reject: Manager/Admin
    case (Review, Draft) => r == Manager || r == Admin
    // Submit: Owner/Author/Admin
    case (Draft, Review) => r == Owner || r == Author || r == Admin
    // Pause/resume/complete: Manager/Admin/Owner
    case _ => r == Manager || r == Admin || r == Owner
  }
}

// ============================================================
// CTA validity
// ============================================================

predicate ctaAvailable(cta: Cta, r: Role, s: TaskState)
{
  match cta {
    case CtaView => true  // everyone can view
    case CtaApprove => canTransition(r, s, Active) && s == Review
    case CtaReject  => canTransition(r, s, Draft) && s == Review
    case CtaEstimate => canWrite(r, s, CostBreakdown)
  }
}

// Which CTAs appear in which notification
predicate templateHasCta(tmpl: NotificationTemplate, cta: Cta, r: Role)
{
  match tmpl {
    case ApprovalRequest => cta == CtaApprove || cta == CtaReject || cta == CtaView
    case CostChange      => (cta == CtaEstimate && (r == Manager || r == Admin)) || cta == CtaView
    case StatusUpdate    => cta == CtaView
    case TaskCreated     => cta == CtaView
  }
}

// Notification trigger states
predicate templateTriggeredInState(tmpl: NotificationTemplate, s: TaskState)
{
  match tmpl {
    case ApprovalRequest => s == Review
    case CostChange      => s == Active || s == Review
    case StatusUpdate    => true
    case TaskCreated     => s == Draft
  }
}

// ============================================================
// Assertions as lemmas
// ============================================================

// Viewer cannot write anything in any state
lemma ViewerCannotWrite(s: TaskState, f: Field)
  ensures !canWrite(Viewer, s, f)
{}

// Viewer cannot read cost fields
lemma ViewerCannotReadCosts(f: Field)
  requires isInternalOnly(f)
  ensures !canRead(Viewer, f)
{}

// Terminal states have no exit transitions
lemma TerminalStatesHaveNoExit(from: TaskState, to: TaskState)
  requires terminal(from)
  ensures !validTransition(from, to)
{}

// Only Owner (or Admin) can cancel
lemma OnlyOwnerCanCancel(r: Role, from: TaskState)
  requires canTransition(r, from, Cancelled)
  ensures r == Owner || r == Admin
{}

// Approve CTA only available for Manager/Admin
lemma ApproveCtaOnlyForApprovers(r: Role, s: TaskState)
  requires ctaAvailable(CtaApprove, r, s)
  ensures r == Manager || r == Admin
{}

// Approve CTA only when in Review
lemma ApproveCtaOnlyWhenPending(r: Role, s: TaskState)
  requires ctaAvailable(CtaApprove, r, s)
  ensures s == Review
{}

// All required fields are writable by Owner in Draft
lemma AllRequiredFieldsSettable(f: Field)
  requires isRequired(f)
  ensures canWrite(Owner, Draft, f)
{}

// CTA validity for Admin — Admin can do everything, so all CTAs work
lemma AdminCtasAlwaysValid(tmpl: NotificationTemplate, cta: Cta, s: TaskState)
  requires templateTriggeredInState(tmpl, s)
  requires templateHasCta(tmpl, cta, Admin)
  requires cta != CtaView
  ensures ctaAvailable(cta, Admin, s)
{}

// CTA validity for approval actions by Manager in Review state
lemma ManagerApprovalCtasValid(cta: Cta, s: TaskState)
  requires s == Review
  requires cta == CtaApprove || cta == CtaReject
  ensures ctaAvailable(cta, Manager, s)
{}

// GAP: AllCtasValid for ALL roles FAILS — same as Alloy's expected-fail check.
// The ApprovalRequest template sends CtaApprove to all roles, but only
// Manager/Admin can approve. This is a known design gap:
// the notification template should filter CTAs by role.
//
// In Alloy: check AllCtasValidForRecipient for 6  -- expected FAIL
// In Dafny: this lemma would fail if uncommented:
//
// lemma AllCtasValid_EXPECTED_FAIL(tmpl: NotificationTemplate, cta: Cta, r: Role, s: TaskState)
//   requires templateTriggeredInState(tmpl, s)
//   requires templateHasCta(tmpl, cta, r)
//   requires cta != CtaView
//   ensures ctaAvailable(cta, r, s)  // FAILS for Owner+CtaApprove
// {}

// ============================================================
// Witness: valid state exists
// ============================================================

lemma DraftStateExists()
  ensures canWrite(Owner, Draft, Title)
  ensures canWrite(Owner, Draft, Description)
  ensures canWrite(Manager, Draft, CostBreakdown)
  ensures !canWrite(Viewer, Draft, Title)
{}
