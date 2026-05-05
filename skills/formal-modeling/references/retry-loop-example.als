/**
 * Retry-loop fairness — medium-tier worked example.
 *
 * Demonstrates the bug class behind the starvation in hashharness-pm 0.6.4:
 *   With distinct contexts and N runnable tasks, two workers re-list the
 *   queue, sort by `(context_priority, created_at)`, and re-pick the same
 *   first-by-sort candidate every iteration. The CAS race has a winner
 *   and a loser; the loser's retry — without a skip-set — re-runs the
 *   identical sort and re-selects the SAME task (now stale or contested),
 *   collides again, and after `--max-retries+1` exits silently with $TASK
 *   empty. The worker treats "no claim" as "queue empty" and quits, even
 *   though other tasks were sitting unworked.
 *
 * Why single-step Alloy assertions can't catch this:
 *   `assert SingleOwner` and similar safety properties hold trivially —
 *   they're true at every state, including the starvation state. The bug
 *   is that *the candidate-selection function*, viewed as a primitive of
 *   its own, isn't fair: two workers compute IDENTICAL results from
 *   identical inputs. The starvation pattern is just that fact compressed.
 *
 * The model:
 *   1. Tasks carry a `(context.priority, createdAt)` sort key — the
 *      actual production sort. Lexicographic on those two fields.
 *   2. Workers compute selectNext = argmin sortLE over (pool - skipSet).
 *   3. Two named workers (W1, W2) share the same runnable view — typical
 *      for two pollers reading the same store at the same wall clock.
 *   4. BUGGY caller: no skip-set tracking — W1.skipSet = W2.skipSet = ∅.
 *      Both workers' selectNext returns the same first-by-sort task, even
 *      when ≥2 runnable tasks exist.
 *   5. FIXED caller: the loser of CAS adds the contested task to its
 *      skip-set. Modeled as W2.skipSet = {W1.selected}, encoding the
 *      post-resolution state where W2 lost on whatever W1 won.
 *
 * Two assertions:
 *   - BuggyPreventsCollision  → counterexample expected.
 *     Concrete instance: pool = {T0, T1}, T0 first-by-sort, BOTH workers
 *     pick T0, T1 sits unworked. Starvation pattern in compressed form.
 *   - FixedPreventsCollision  → must hold.
 *     With skip-set, W2 picks the second-by-sort, so W1 and W2 select
 *     distinct tasks; both make progress.
 */
module retry_loop_example

sig Context {
    priority: Int
}

sig Task {
    ctx: Context,
    createdAt: Int
}

// Lexicographic order on (ctx.priority, createdAt). Reflexive — `a sortLE a`.
pred sortLE[a, b: Task] {
    a.ctx.priority < b.ctx.priority
    or (a.ctx.priority = b.ctx.priority and a.createdAt < b.createdAt)
    or a = b
}

pred isFirstBySort[t: Task, pool: set Task] {
    t in pool
    all other: pool - t | sortLE[t, other]
}

// Workers compute selectNext = first-by-sort over (pool - skipSet).
abstract sig Worker {
    skipSet:  set Task,
    pool:     set Task,    // worker's view of currently-runnable tasks
    selected: lone Task
}

fact SelectionSemantics {
    all w: Worker |
        let avail = w.pool - w.skipSet |
            ((some w.selected) iff (some avail))
            and ((some w.selected) implies isFirstBySort[w.selected, avail])
}

// Two named workers, sharing the runnable view (same store, same instant).
// `one sig`s are automatically disjoint, so no need for a distinctness fact.
one sig W1, W2 extends Worker {}
fact SharedView { W1.pool = W2.pool }

// ── BUGGY: no skip-set tracking. ──────────────────────────────────────────
pred buggyNoSkipSet {
    no W1.skipSet
    no W2.skipSet
}

// ── FIXED: loser-of-CAS adds the contested task to its skip-set. ──────────
// Encoded as the post-resolution state: W1 won (skipSet empty), W2 lost on
// W1's pick, so W2.skipSet = {W1.selected}.
pred fixedWithSkipSet {
    no W1.skipSet
    W2.skipSet = W1.selected
}

// ── Properties ────────────────────────────────────────────────────────────
//
// When ≥2 runnable tasks exist, two distinct workers should pick distinct
// tasks. Buggy fails (both pick first-by-sort); fixed holds (W2's skip-set
// pushes it to second-by-sort).

assert BuggyPreventsCollision {
    buggyNoSkipSet
        and #(W1.pool) >= 2
        and some W1.selected
        and some W2.selected
            implies W1.selected != W2.selected
}

assert FixedPreventsCollision {
    fixedWithSkipSet
        and #(W1.pool) >= 2
        and some W1.selected
        and some W2.selected
            implies W1.selected != W2.selected
}

check BuggyPreventsCollision for 4 Task, 3 Context, exactly 2 Worker, 4 int
check FixedPreventsCollision for 4 Task, 3 Context, exactly 2 Worker, 4 int

// Sanity run — show the buggy collision concretely. The instance Alloy
// returns has W1.selected = W2.selected on the first-by-sort task, while
// the pool contains a second runnable task that no worker is choosing.
run BuggyCollisionExists {
    buggyNoSkipSet
    #(W1.pool) >= 2
    some W1.selected
    some W2.selected
    W1.selected = W2.selected            // the collision
} for 4 Task, 3 Context, exactly 2 Worker, 4 int
