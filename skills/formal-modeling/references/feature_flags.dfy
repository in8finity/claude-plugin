/**
 * Feature Flag Lifecycle — Dafny port of temporal model
 *
 * Ported from feature_flags.als (Alloy 6 temporal model).
 *
 * In Alloy: `var sig`, `always`, `eventually`, `stutter`, frame conditions
 * In Dafny: sequences of states, inductive proofs over traces
 *
 * The temporal operators translate to quantifiers over sequence indices:
 *   always P    → forall i :: 0 <= i < |trace| ==> P(trace[i])
 *   eventually P → exists i :: 0 <= i < |trace| && P(trace[i])
 */

datatype FlagStatus = Draft | Staged | Active | Deprecated | Archived

// ============================================================
// Valid transitions (same as Alloy's transition predicates)
// ============================================================

predicate ValidTransition(from: FlagStatus, to: FlagStatus)
{
  match (from, to) {
    case (Draft, Staged)         => true   // stage
    case (Staged, Active)        => true   // activate
    case (Staged, Draft)         => true   // rollback
    case (Active, Deprecated)    => true   // deprecate
    case (Deprecated, Archived)  => true   // archive
    case (s1, s2)                => s1 == s2  // stutter (no change)
  }
}

// A trace is a non-empty sequence of states with valid transitions
predicate ValidTrace(trace: seq<FlagStatus>)
{
  |trace| >= 1 &&
  trace[0] == Draft &&  // Init: all flags start in Draft
  forall i :: 0 <= i < |trace| - 1 ==> ValidTransition(trace[i], trace[i+1])
}

// ============================================================
// Safety properties — proved for ALL valid traces (unbounded)
// ============================================================

// Alloy: assert ArchivedIsForever { always (f.status = Archived implies always f.status = Archived) }
lemma ArchivedIsForever(trace: seq<FlagStatus>, i: int)
  requires ValidTrace(trace)
  requires 0 <= i < |trace|
  requires trace[i] == Archived
  ensures forall j :: i <= j < |trace| ==> trace[j] == Archived
  decreases |trace| - i
{
  if i == |trace| - 1 {
    // Base: last element, nothing to prove
  } else {
    // Inductive: Archived can only transition to Archived (stutter)
    assert ValidTransition(trace[i], trace[i+1]);
    // So trace[i+1] == Archived
    ArchivedIsForever(trace, i + 1);
  }
}

// Alloy: assert OnlyActiveDeprecated (fixed version)
lemma OnlyActiveCanBeDeprecated(trace: seq<FlagStatus>, i: int)
  requires ValidTrace(trace)
  requires 0 < i < |trace|
  requires trace[i] == Deprecated
  requires trace[i-1] != Deprecated  // not a stutter
  ensures trace[i-1] == Active
{
  // Direct from ValidTransition: only Active → Deprecated (non-stutter)
  assert ValidTransition(trace[i-1], trace[i]);
}

// Alloy: assert NoDirectDraftToActive
lemma NoDirectDraftToActive(trace: seq<FlagStatus>, i: int)
  requires ValidTrace(trace)
  requires 0 < i < |trace|
  requires trace[i] == Active
  requires trace[i-1] != Active  // not a stutter
  ensures trace[i-1] == Staged
{
  assert ValidTransition(trace[i-1], trace[i]);
}

// Alloy: assert StagedTransitions
lemma StagedOnlyGoesToActiveOrDraft(trace: seq<FlagStatus>, i: int)
  requires ValidTrace(trace)
  requires 0 <= i < |trace| - 1
  requires trace[i] == Staged
  ensures trace[i+1] == Staged || trace[i+1] == Active || trace[i+1] == Draft
{
  assert ValidTransition(trace[i], trace[i+1]);
}

// ============================================================
// Stronger property: Archived is a sink (no outgoing transitions)
// This is STRONGER than Alloy's bounded check — proved for ALL traces
// ============================================================

lemma ArchivedIsSink(from: FlagStatus, to: FlagStatus)
  requires from == Archived
  requires ValidTransition(from, to)
  ensures to == Archived
{
  // Follows directly from ValidTransition definition
}

// ============================================================
// Trace existence (closest to Alloy's `run` commands)
// Unlike Alloy, Dafny can't generate instances — but we can
// construct witnesses explicitly and prove they're valid.
// ============================================================

// Alloy: run FullLifecycle { eventually Staged and eventually Active and eventually Archived }
lemma FullLifecycleExists()
  ensures exists trace ::
    (ValidTrace(trace) &&
    |trace| == 6 &&
    trace[0] == Draft &&
    trace[1] == Staged &&
    trace[2] == Active &&
    trace[3] == Deprecated &&
    trace[4] == Archived &&
    trace[5] == Archived)  // stutter (trace must be well-formed)
{
  var trace := [Draft, Staged, Active, Deprecated, Archived, Archived];
  assert ValidTrace(trace);
}

// Alloy: run RollbackThenActivate
lemma RollbackThenActivateExists()
  ensures exists trace ::
    (ValidTrace(trace) &&
    |trace| >= 5 &&
    trace[1] == Staged &&
    trace[2] == Draft &&
    trace[3] == Staged &&
    trace[4] == Active)
{
  var trace := [Draft, Staged, Draft, Staged, Active];
  assert ValidTrace(trace);
}

// ============================================================
// Executable verified state machine
// ============================================================

method Stage(current: FlagStatus) returns (next: FlagStatus)
  requires current == Draft
  ensures next == Staged
  ensures ValidTransition(current, next)
{
  next := Staged;
}

method Activate(current: FlagStatus) returns (next: FlagStatus)
  requires current == Staged
  ensures next == Active
  ensures ValidTransition(current, next)
{
  next := Active;
}

method Rollback(current: FlagStatus) returns (next: FlagStatus)
  requires current == Staged
  ensures next == Draft
  ensures ValidTransition(current, next)
{
  next := Draft;
}

method Deprecate(current: FlagStatus) returns (next: FlagStatus)
  requires current == Active
  ensures next == Deprecated
  ensures ValidTransition(current, next)
{
  next := Deprecated;
}

method Archive(current: FlagStatus) returns (next: FlagStatus)
  requires current == Deprecated
  ensures next == Archived
  ensures ValidTransition(current, next)
{
  next := Archived;
}

// Full lifecycle — verified executable
method RunFullLifecycle() returns (finalStatus: FlagStatus)
  ensures finalStatus == Archived
{
  var s := Draft;
  s := Stage(s);
  s := Activate(s);
  s := Deprecate(s);
  s := Archive(s);
  finalStatus := s;
}

// Rollback flow — verified executable
method RunRollbackFlow() returns (finalStatus: FlagStatus)
  ensures finalStatus == Active
{
  var s := Draft;
  s := Stage(s);
  s := Rollback(s);
  s := Stage(s);
  s := Activate(s);
  finalStatus := s;
}
