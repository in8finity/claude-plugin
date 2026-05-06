# F10 — Baseline Comparability

A differential against a "last known good" baseline only informs the
investigation if the baseline matches on repository, trigger type, and
config. Replaces `fdp_baseline_comparability.als`. Encoded as a
**decision/lookup table** (#5) for the match function plus an **invariant
table** (#6) for the safety properties.

## Match definition

A baseline `B` is **comparable** to the failing build `F` iff all three
axes match:

| Axis      | Field                                | Match means                                                  |
|-----------|--------------------------------------|--------------------------------------------------------------|
| repo      | source repository / service          | identical repo (not a renamed predecessor, not a sibling)    |
| trigger   | trigger kind (PR / push / cron / manual) | identical trigger type                                       |
| config    | environment / compose file / feature flags | identical config snapshot, or a recorded `config-diff=Z`     |

`baselineMatches(B, F)  ≡  B.repo = F.repo  ∧  B.trigger = F.trigger  ∧  B.config = F.config`

The relation is **reflexive** (every baseline matches itself) and
**symmetric** (`matches(A, B) ⇔ matches(B, A)`). Any disagreement on a
single axis breaks the match.

## Evidence shape

Every differential evidence record carries a `Baseline:` line:

```
Baseline: <id> | repo=<X> trigger=<Y> config-diff=<Z>
```

If any of `repo`, `trigger`, or `config-diff` is missing or marked `?`, the
record is treated as failing F10 and degraded to `Interpreted`.

## Invariants

| id     | rule                                                               | why                                                                                                                                  | trigger                                                              | how to verify by hand                                                                                                       |
|--------|--------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------|
| F10-S1 | Mismatched repo ⇒ baseline fails the match                         | Builds from different repos may share a name but cannot share build behaviour; cross-repo diffs are not signal                       | Differential cites a baseline whose repo differs from the failing build | Read the `Baseline:` line; confirm `repo=` matches the failing-build repo                                                   |
| F10-S2 | Same repo but different trigger ⇒ fails                            | PR builds, cron builds, and manual builds run different pipelines; differences may reflect the trigger, not the change under test    | Trigger axis differs                                                 | Confirm `trigger=` matches; if missing, the baseline is not comparable                                                      |
| F10-S3 | Same repo and trigger but different config ⇒ fails                 | Compose files / env vars / feature flags can change behaviour entirely; an undeclared config diff produces a polluted differential   | Config axis differs                                                  | Confirm `config-diff=` is empty or explicitly enumerated; any unrecorded config drift breaks the match                      |
| F10-S4 | A baseline matches iff all three axes align (necessary AND sufficient) | Closes the rule both directions — preventing both false negatives ("matches but I'll reject anyway") and false positives             | Pre-acceptance check                                                 | Walk the three axes; either all three pass or the baseline is incomparable. There is no partial credit                      |
| F10-S5 | Matching is reflexive: every baseline matches itself                | Sanity property; lets the rule type-check                                                                                            | Self-comparison check                                                | Confirm that for any baseline `B`, `B` is comparable to itself                                                              |
| F10-S6 | A differential built on a non-matching baseline cannot be `Direct` | Caps the reliability of a polluted differential at `Interpreted`; downstream checks see the degradation                              | Evidence write whose source cites a differential                     | If F10-S1/S2/S3 fails, downgrade the evidence's reliability to `Interpreted` and record `Baseline-mismatch: <axis>` on the row |

## Worked example

```
Setup: F = build 91e90439, repo=bot, trigger=PR, config=docker-compose.yml
       B = build 3299ae05, repo=back (deprecated), trigger=manual, config=docker-compose.back.yml

Walk:  F10-S1 — repo bot vs back ⇒ FAIL
       F10-S2 — trigger PR vs manual ⇒ FAIL
       F10-S3 — config different files ⇒ FAIL
       Three axes mismatched ⇒ baseline incomparable.

Outcome: Reject the differential. Any time spent comparing test logs between
         these two builds is not load-bearing — record this and ask for a
         green build on (repo=bot, trigger=PR, config=docker-compose.yml).
```
