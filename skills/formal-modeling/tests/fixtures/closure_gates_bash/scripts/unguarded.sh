#!/usr/bin/env bash
# Simulates the bug from the proposal — a NEW script gates append_claim
# without check_sticky_eligibility. The file-list `code_gates` check
# would pass (this file isn't listed); the closure check must catch it.

pull() {
  append_claim "$task_id" "$ctx"
}

pull_after_check() {
  result=$(append_claim "$task_id" "$ctx")
  check_sticky_eligibility "$task_id" "$ctx"
  echo "$result"
}
