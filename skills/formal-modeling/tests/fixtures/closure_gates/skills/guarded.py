from store import append_claim, check_sticky_eligibility


def claim_one(task_id, ctx):
    check_sticky_eligibility(task_id, ctx)
    return append_claim(task_id, ctx)


def claim_two(task_id, ctx):
    if not check_sticky_eligibility(task_id, ctx):
        raise SystemExit(10)
    return append_claim(task_id, ctx)
