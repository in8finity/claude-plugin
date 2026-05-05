#!/usr/bin/env bash
# Both functions gate append_claim with check_sticky_eligibility.

claim_one() {
  check_sticky_eligibility "$task_id" "$ctx" || exit 10
  append_claim "$task_id" "$ctx"
}

claim_two() {
  if ! check_sticky_eligibility "$task_id" "$ctx"; then
    exit 10
  fi
  append_claim "$task_id" "$ctx"
}
