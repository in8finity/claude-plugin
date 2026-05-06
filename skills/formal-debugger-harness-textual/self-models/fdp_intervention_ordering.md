# OB1 — Observability Before Intervention

Every system change (topology, config, code, dependency version) must be
preceded by a `Direct` evidence record capturing the state being changed.
Blind intervention moves the target and breaks the causal chain. Replaces
`fdp_intervention_ordering.als`. Encoded as an **invariant table** (#6).

## Intervention record shape

Every intervention captured during an investigation has these fields:

```
Intervention I<N>
  Description:           <what was changed>
  Observation time:      <ISO 8601 of the change>
  Prior direct evidence: <E<M> | <Direct evidence record observing the pre-change state>
  Target observable:     <yes | no>     (was the target state observable at all?)
```

An intervention is **valid** iff:

1. `Target observable = yes`, AND
2. The prior `Direct` evidence record was written **strictly before** the
   intervention's observation time.

## Invariants

| id     | rule                                                                                           | why                                                                                                                                       | trigger                                                              | how to verify by hand                                                                                                              |
|--------|------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| OB1-S1 | An intervention whose target state is not observable is invalid, regardless of evidence timing | If you cannot see the target, you cannot tell whether the change made things better, worse, or unchanged                                  | Any intervention proposed without a way to observe the target        | Read the `Target observable` field; if `no`, reject the intervention until observability is added                                  |
| OB1-S2 | Evidence captured at the same instant as the intervention is invalid (must be strictly before) | Simultaneous evidence may already reflect the change in flight; only strictly-earlier evidence captures the pre-change baseline           | Intervention timestamp equals the cited evidence's timestamp         | Compare the two ISO timestamps; equal ⇒ reject                                                                                     |
| OB1-S3 | Evidence captured AFTER the intervention is invalid (the target was changed blind)             | Post-change evidence describes the post-change system, not what was being intervened on                                                   | Intervention cites evidence whose timestamp is later than the change | Compare timestamps; evidence-after-change ⇒ reject. If this case is found, also re-baseline (F10) — the comparison frame has moved |
| OB1-S4 | A well-formed intervention (observable + prior evidence strictly earlier) is valid             | Closes the rule both directions, so the audit can pass interventions, not just reject them                                                | Pre-acceptance check                                                 | Verify the two conditions: `Target observable=yes` AND `evidence timestamp < intervention timestamp`. Both pass ⇒ valid             |
| OB1-S5 | One invalid intervention poisons the whole sequence                                            | An investigation that mixes valid and blind interventions cannot be partly trusted; the blind ones may have moved the target the others depend on | Audit run                                                            | Walk every intervention in chronological order; if any single one is invalid, mark the entire intervention sequence invalid        |
| OB1-S6 | Topology changes proposed without prior `Direct` evidence are flagged before they are applied  | The OB1 check is a planning gate, not just a post-hoc audit; catching the violation before the change is what preserves the baseline      | Anytime the agent proposes a system change                           | Before applying the change, list `Direct` evidence covering the current state of the affected component; if none exists, halt    |

## Worked example

```
Setup: CI failing with socket.gaierror: 'app' name not known.
       The user has already (in this order):
         I1 = changed compose network driver bridge → default
         I2 = renamed service 'app' → 'api'
         I3 = moved pytest into the app container
       No prior `Direct` evidence of the app container's startup state.

Walk:  OB1-S1 — for I1, I2, I3, was the target state observable before the
                change? No `Direct` evidence captured app-container liveness
                before any of the three. ⇒ All three fail OB1-S1.
       OB1-S5 — One bad intervention poisons the sequence. Three bad ones
                certainly do. ⇒ The current investigation state cannot be
                used to draw conclusions.

Outcome: Recommend reverting I1, I2, I3 to restore baseline. Then collect
         `Direct` evidence: container status, startup logs, process list.
         Only after that, propose the next intervention.
```
