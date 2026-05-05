/**
 * Primitive-strength worked example: TOCTOU on a CAS-protected head.
 *
 * Demonstrates the gap between an abstract model precondition and the
 * implementation primitive that's supposed to enforce it.
 *
 *   Abstract model: `commitClaim` requires `isNew[x]`
 *                   (the record being claimed must currently have status=new).
 *
 *   Implementation: an append-only log where the only "atomic" primitive
 *                   the storage layer offers is CAS — accept the new record
 *                   iff `submittedPrev = currentHead`. The CAS check is on
 *                   pointer/identity, not on status.
 *
 *   The buggy caller pattern (real bug from hashharness-pm 0.6.4):
 *
 *     1. Read head, observe head.status = new.            ← read 1
 *     2. (Concurrent claim by another worker moves head    ← adversary
 *         to a `working` record, also append-only.)
 *     3. Read head again to obtain `prev` for CAS.         ← read 2
 *     4. Submit CAS with prev = (the working record from   ← CAS succeeds
 *         read 2). CAS check passes — submitted prev still
 *         equals current head — so the storage accepts the
 *         claim. Two workers now hold a `working` claim.
 *
 *   The fix: thread the FIRST read through to CAS, so the prev sent to
 *   the storage is the same record whose status was checked. CAS then
 *   detects the concurrent move (head no longer equals submittedPrev)
 *   and the second worker fails cleanly.
 *
 * Two assertions:
 *   - BuggyCallerEnforcesPrecondition  → counterexample expected.
 *     Proves the primitive is too weak for this caller pattern.
 *   - FixedCallerEnforcesPrecondition  → must hold.
 *     Proves threading the first read closes the gap.
 *
 * If either verdict flips, the example is silently lying — the smoke test
 * in tests/test_primitive_strength.py asserts both verdicts.
 */
module primitive_strength_example

open util/ordering[Step] as SO

sig Step {}

abstract sig Status {}
one sig StatusNew, StatusWorking extends Status {}

// Records are immutable: a record's status is fixed at creation.
// "Changing status" in the protocol means appending a new record.
sig Record {
    status: Status
}

// The boundary state: a head pointer that the storage layer tracks.
// Free across steps — no transition fact constrains how it evolves,
// which models the worst-case adversary (any other writer can move it).
one sig Head {
    current: Record one -> Step
}

// The caller — observed reads + the prev it submits to CAS.
one sig Caller {
    read1:      Record,   // observed by read 1 (status checked here)
    read2:      Record,   // observed by read 2 (re-read for CAS prev)
    casPrev:    Record,   // value actually submitted as `prev` to CAS
    readStep1:  Step,
    readStep2:  Step,
    casStep:    Step
}

// The caller's three boundary interactions are strictly ordered.
fact CallerOrder {
    SO/lt[Caller.readStep1, Caller.readStep2]
    SO/lt[Caller.readStep2, Caller.casStep]
}

// Each "read" observes head's value at that step.
fact CallerObservations {
    Caller.read1 = Head.current.(Caller.readStep1)
    Caller.read2 = Head.current.(Caller.readStep2)
}

// The caller proceeds only because read 1 saw status=new.
fact CallerSawNew {
    Caller.read1.status = StatusNew
}

// CAS primitive — what the storage actually guarantees:
// "Accept iff your submitted prev equals the current head right now."
// We model "the CAS succeeds" by constraining the trace to those where
// head still equals casPrev at casStep. (If we wanted to model both
// success and failure, we'd add an outcome field; for the strength
// question, success is the interesting case.)
fact CasSucceeds {
    Head.current.(Caller.casStep) = Caller.casPrev
}

// ── caller patterns ────────────────────────────────────────────────────

// BUGGY: CAS uses the SECOND read. Between read1 and read2 the adversary
// can move head; the second read sees the moved record; CAS submits that.
pred buggyCaller {
    Caller.casPrev = Caller.read2
}

// FIXED: CAS uses the FIRST read. The verified value is threaded through
// to the storage; CAS now actually checks "head still equals the record
// whose status I verified."
pred fixedCaller {
    Caller.casPrev = Caller.read1
}

// ── strength assertion ────────────────────────────────────────────────
// At the moment CAS is accepted, the record CAS is committing-on-top-of
// (which equals current head, by the CAS check) must have status=new —
// the abstract precondition the model demands.

pred preconditionHoldsAtCas {
    Head.current.(Caller.casStep).status = StatusNew
}

// Buggy: counterexample expected. The adversary inserts a Working record
// between read1 and read2; head equals it at casStep; the precondition
// is violated.
assert BuggyCallerEnforcesPrecondition {
    buggyCaller => preconditionHoldsAtCas
}

// Fixed: must hold. CAS succeeds only if head still equals read1, and
// read1.status = StatusNew (by CallerSawNew).
assert FixedCallerEnforcesPrecondition {
    fixedCaller => preconditionHoldsAtCas
}

check BuggyCallerEnforcesPrecondition for 4 Step, 5 Record
check FixedCallerEnforcesPrecondition for 4 Step, 5 Record

// Sanity: the buggy counterexample shows up because the adversary
// genuinely has room to move head between the two reads. Run the buggy
// pattern explicitly to inspect the trace.
run BuggyTraceExists {
    buggyCaller
    not preconditionHoldsAtCas    // the actual bug: precondition violated
} for 4 Step, 5 Record
