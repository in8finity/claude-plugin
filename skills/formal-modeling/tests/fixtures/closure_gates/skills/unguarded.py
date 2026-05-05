"""Simulates the bug from the hashharness-pm 0.6.4 report — a NEW file
introduces a call site of the protected primitive but skips the gate.
The file-list `code_gates` check would pass (this file isn't listed);
the `closure_gates` check must catch it."""

from store import append_claim


def pull(task_id, ctx):
    return append_claim(task_id, ctx)


def pull_after_check(task_id, ctx):
    from store import check_sticky_eligibility
    result = append_claim(task_id, ctx)
    check_sticky_eligibility(task_id, ctx)
    return result
