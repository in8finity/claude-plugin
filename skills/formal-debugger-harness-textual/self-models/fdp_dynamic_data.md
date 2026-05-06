# F3 / TC23 — Dynamic Data Verification

Hypotheses that depend on dynamic data (DB-stored templates, runtime
config, feature-flag values, role assignments, A/B variants) cannot pass
the acceptance gate without three independent verification checks.
Replaces `fdp_dynamic_data.als`. Encoded as a **schema** (#4) for the
hypothesis's data state plus an **invariant table** (#6) for the gate.

## Schema

```yaml
HypDataState:
  dependent:                         # required, bool
    type: bool
    description:
      true  if the hypothesis's truth depends on a dynamic data value
            (e.g., "the cache TTL was 300s when the symptom occurred")
      false if it depends only on static code paths

  current_value_verified:            # required when dependent=true
    type: bool
    description:
      true iff the live value has been queried from production AT
      INVESTIGATION TIME (not from logs, not from the spec, not from
      the repo). Must be a `Direct` evidence record per F3.

  change_history_verified:           # required when dependent=true
    type: bool
    description:
      true iff the audit trail / revision table / migration log has
      been examined for this value. The aim is to detect that the
      value was different earlier and rule that in or out as the cause.

  timeline_coverage_verified:        # required when dependent=true
    type: bool
    description:
      true iff the change history's timestamps cover the symptom
      window — i.e., the data state at the time of the symptom is
      known, not extrapolated.
```

When `dependent=false`, all three verification fields are ignored
(vacuous pass per TC23-S5).

When `dependent=true`, **all three** verification fields must be `true`
for the gate to pass. Partial verification is insufficient (TC23-S7).

## Invariants

| id      | rule                                                                                          | why                                                                                                                                                  | trigger                                                              | how to verify by hand                                                                                                                            |
|---------|-----------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| TC23-S1 | `dependent=true` AND `current_value_verified=false` ⇒ gate fails                              | Without the live value, the hypothesis is grounded in code reading (`Interpreted`), not the running system                                           | Pre-acceptance check                                                 | Confirm a `Direct` evidence record exists capturing the live value at investigation time                                                          |
| TC23-S2 | `dependent=true` AND `change_history_verified=false` ⇒ gate fails                             | A current-value query alone misses "the value used to be different and that's exactly the cause"                                                     | Pre-acceptance check                                                 | Confirm an evidence record cites the audit trail / revision history / migration log for the value                                                |
| TC23-S3 | `dependent=true` AND `timeline_coverage_verified=false` ⇒ gate fails                          | Even with current value AND history, if the history has gaps that cover the symptom window, the value at symptom time is unknown                     | Pre-acceptance check                                                 | Confirm the history's timestamps span the symptom window with no gaps                                                                            |
| TC23-S4 | `dependent=true` AND all three checks `true` ⇒ gate passes                                    | Closes the rule positively so well-verified dynamic-data hypotheses can accept                                                                       | Pre-acceptance check                                                 | All three evidence records present and `Direct`                                                                                                  |
| TC23-S5 | `dependent=false` ⇒ gate passes (vacuous)                                                     | Static-code-only hypotheses do not depend on dynamic state and should not be blocked by this gate                                                    | Pre-acceptance check on a hypothesis that doesn't reference dynamic data | Confirm the `dependent` classification — read the hypothesis text, look for references to runtime values; if none, mark `dependent=false`        |
| TC23-S6 | `dependent=true` AND none of the three checks verified ⇒ gate fails                           | The fully-unverified case: the hypothesis is unsupported on every dynamic axis                                                                       | Pre-acceptance check                                                 | All three checks `false`; gate cannot pass — collect evidence first                                                                              |
| TC23-S7 | `dependent=true` AND any of the three checks `false` ⇒ gate fails (no partial credit)         | Two-out-of-three is still a missing axis; the missing axis is exactly where the bug could hide                                                       | Pre-acceptance check                                                 | If any single check is `false`, gate fails. Identify which axis is missing and what evidence would close it; treat as a Step 4 task              |
| TC23-S8 | The classification of `dependent` cannot be flipped after evidence is gathered                | Otherwise an investigator could weaken the gate post-hoc by re-classifying. The classification belongs in the hypothesis statement (H1), not the gate | Anytime the `dependent` flag is changed                              | The flag is set at hypothesis creation and lives in the hypothesis record's attributes; changing it requires a new hypothesis revision (H1-N+1) |

## Worked example

```
Setup: H1 = "the role-based notification filter sees the user as Manager
            because the cache served a stale role"
       Dynamic data dependency: the cached role at notify time
       Evidence collected so far:
         E1: live Redis GET user:7521 at 03:30 returns role=manager   (current_value)
         E2: role audit log shows role changed Engineer→Manager at 02:45 (change_history)
         E3: cron log shows notification sent at 03:15
            (gap: between 02:45 and 03:15, no record of cache state — timeline_coverage gap)

Walk:  HypDataState:
         dependent=true
         current_value_verified=true     (E1)
         change_history_verified=true    (E2)
         timeline_coverage_verified=false (E3 leaves the symptom window unobserved)
       TC23-S3 ⇒ FAIL
       TC23-S7 ⇒ FAIL

Outcome: Gate blocks H1 until the timeline gap is closed. Concrete next
         step: query Redis cache TTL at 03:15 (or the closest observable
         point), or capture a fresh trace covering 02:45-03:15. After
         that evidence lands, mark `timeline_coverage_verified=true` and
         re-walk the gate.
```
