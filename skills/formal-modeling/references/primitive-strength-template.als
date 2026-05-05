/**
 * Primitive-strength TEMPLATE — copy and fill in for your domain.
 *
 *   USE WHEN: a precondition in your abstract model is enforced at runtime
 *   by a primitive that lives BELOW the model — at a database, kernel,
 *   network, or external-service boundary. The model trusts the boundary
 *   to enforce the precondition. This template asks: does the primitive
 *   the boundary actually exposes do that?
 *
 *   COMMON PATTERNS THIS CATCHES:
 *     - "commit requires status=new"   enforced by CAS on a head pointer
 *                                      (CAS guards identity, not status)
 *     - "delete requires no children"  enforced by foreign-key cascade
 *                                      (cascade deletes children — different!)
 *     - "send requires authenticated"  enforced by middleware that checks
 *                                      a header (replay attacks bypass)
 *     - "read requires committed"      enforced by snapshot isolation
 *                                      (read-skew across two queries)
 *
 *   THE FIVE INGREDIENTS:
 *     1. BOUNDARY STATE   — what the boundary tracks (head, row, lock).
 *     2. PRIMITIVE        — what the boundary actually guarantees, stated
 *                            literally. Not what you wished for. Not what
 *                            the docs imply. What the wire/syscall returns.
 *     3. CALLER PATTERN   — how your code uses the primitive. If it does
 *                            N>1 reads, model all N reads explicitly.
 *     4. ADVERSARY        — between any two caller steps, what can other
 *                            actors do? Default = anything (free atoms).
 *     5. STRENGTH ASSERT  — caller-pattern-with-primitive ⟹ abstract-precondition.
 *                            Counterexample = primitive too weak for caller.
 *                            Holds       = wiring is sound under the modeled adversary.
 */
module primitive_strength_TEMPLATE

open util/ordering[Step] as SO

sig Step {}

// ── 1. BOUNDARY STATE ────────────────────────────────────────────────────
// The shared state the primitive operates on.
// EXAMPLE: a head pointer, a row, a lock, an auth-token version.

abstract sig Status {}
one sig StatusReady, StatusBusy extends Status {}    // ← rename to your states

sig Resource {                                        // ← rename
    status: Status
}

one sig Boundary {
    state: Resource one -> Step                       // ← shared state, free over time
}

// ── 2. PRIMITIVE ─────────────────────────────────────────────────────────
// State the EXACT guarantee the primitive makes. Literally what the
// successful return path of the syscall/SQL/CAS tells you.
//
// EXAMPLE — CAS on pointer:
//   "I will accept iff your submittedPrev equals current state."
//   That's it. CAS does not look at .status.
//
// We model a successful primitive call by constraining the trace.

fact PrimitiveSucceeds {
    // ← Replace with the actual guarantee. Below is a CAS-on-pointer.
    Boundary.state.(Caller.opStep) = Caller.opPrev
}

// ── 3. CALLER PATTERN ────────────────────────────────────────────────────
// Show every read your code performs, in order. Don't collapse two reads
// into one — that collapsing is exactly the bug class.

one sig Caller {
    read1:    Resource,        // ← record everything the caller observes
    read2:    Resource,        // ←   (extend to readN if needed)
    opPrev:   Resource,        // ← what gets sent to the primitive
    readStep1: Step,
    readStep2: Step,
    opStep:    Step
}

fact CallerOrder {
    SO/lt[Caller.readStep1, Caller.readStep2]
    SO/lt[Caller.readStep2, Caller.opStep]
}

fact CallerObservations {
    Caller.read1 = Boundary.state.(Caller.readStep1)
    Caller.read2 = Boundary.state.(Caller.readStep2)
}

fact CallerObservedReady {
    Caller.read1.status = StatusReady               // ← the check the caller did
}

// ── 4. ADVERSARY ─────────────────────────────────────────────────────────
// Between caller steps, what can other actors do? The default — leaving
// Boundary.state free across steps with no transition fact — models the
// worst-case adversary: state can become any value.
//
// If your real adversary is more constrained (e.g. "only the same task
// owner can write"), add facts here that restrict transitions. Be honest:
// understating the adversary makes the assertion artificially pass.

// (no adversary facts by default — Boundary.state is free over Step)

// ── 5. STRENGTH ASSERTION ────────────────────────────────────────────────
// At the moment the primitive succeeds, did the abstract precondition
// actually hold on the resource it acted on?

pred preconditionHoldsAtOp {
    Boundary.state.(Caller.opStep).status = StatusReady   // ← abstract precondition
}

// Naïve caller — sends read2 as the primitive's prev (the BUG class).
pred buggyCaller { Caller.opPrev = Caller.read2 }

// Threaded caller — sends read1 as the primitive's prev (the FIX class).
pred fixedCaller { Caller.opPrev = Caller.read1 }

assert BuggyCallerEnforces  { buggyCaller => preconditionHoldsAtOp }
assert FixedCallerEnforces  { fixedCaller => preconditionHoldsAtOp }

check BuggyCallerEnforces for 4 Step, 5 Resource
check FixedCallerEnforces for 4 Step, 5 Resource

// ── INTERPRETATION ───────────────────────────────────────────────────────
//   Buggy → counterexample  ⇒ primitive too weak for the buggy caller.
//                              Fix the caller (thread first read through),
//                              OR strengthen the primitive at the boundary
//                              (e.g. CAS-with-status-check, transactional
//                              read-modify-write).
//   Fixed → holds            ⇒ the proposed fix actually closes the gap
//                              under your adversary model.
//   Both fail                ⇒ the primitive is too weak even when used
//                              correctly. Push the fix to the boundary.
//   Both hold                ⇒ either your primitive is already strong
//                              enough (good!), or your adversary is too
//                              tame (re-examine ingredient #4).
