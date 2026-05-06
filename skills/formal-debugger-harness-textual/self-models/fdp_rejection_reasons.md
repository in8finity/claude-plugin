# U2-doc / TC35 — Rejection Reasons

Every rejected hypothesis must document **why** it was rejected. Replaces
`fdp_rejection_reasons.als`. Encoded as a **schema** (#4) for the rejection
reason structure plus an **invariant table** (#6) for the safety properties.

## Schema

A rejection reason is one of two shapes:

```yaml
# Evidence-based rejection
EvidenceBased:
  cited_evidence:    # required, exactly one
    type:    text_sha256          # the hashharness record_sha256 of the cited Evidence item
    target_types: [Evidence]      # link target type
```

```yaml
# Preference-based rejection
PreferenceBased:
  priority:          # required, exactly one
    type: enum
    values:          # closed set; no other priority name is valid
      - Occam               # simpler explanation preferred
      - BlastRadius         # smaller-impact explanation preferred
      - Severity            # more-severe explanation preferred (for prioritisation)
      - RecencyOfDeploy     # explanation tied to a recent change preferred
      - Reproducibility     # more-reproducible explanation preferred
      - FixCost             # cheaper-to-verify explanation preferred
  rationale:         # required, non-empty string
    type: string
    constraints:
      min_length: 1
      not_blank: true       # whitespace-only fails
```

A rejected hypothesis carries **exactly one** rejection reason of one of
the two shapes. The reason cannot be empty, partial, or of mixed shape.

The harness enforces the schema mechanically at write time via
`scripts/check_rejection_reasons.py`; the agent is responsible for
producing the right shape. The rejection reason lives in the
`HypothesisEvent` item's `attributes` field when its `event` is
`status-changed` with `new_status=rejected`.

## Invariants

| id      | rule                                                                                                  | why                                                                                                                            | trigger                                                  | how to verify by hand                                                                                                                    |
|---------|-------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| TC35-S1 | Every `EvidenceBased` reason is structurally valid (the citation is required and points to one Evidence item) | The citation IS the proof; if it links to a real Evidence item with the matching hash, the reason stands                       | Pre-acceptance check                                     | Confirm `cited_evidence` is non-empty and the linked record_sha256 resolves to an Evidence item                                          |
| TC35-S2 | A `PreferenceBased` reason with empty / blank rationale is invalid                                    | Without a rationale, the preference is just a vote — anyone could claim it. Rationale is what makes the preference auditable    | Rejection write whose `rationale` is missing or blank    | Read the `rationale` field; if missing, blank, or whitespace-only ⇒ reject the rejection                                                |
| TC35-S3 | A `PreferenceBased` reason with a non-empty rationale AND a priority from the allowed set is valid    | Closes the rule positively so well-formed preference rejections pass; the priority enum is a closed set, no invented names      | Pre-acceptance check                                     | Confirm `priority` is one of the six listed values AND `rationale` is non-empty                                                          |
| TC35-S4 | One undocumented rejection poisons the entire investigation's rejection set                           | An audit cannot be partly trusted; if even one rejection is unbacked, the set is unbacked                                       | Audit run                                                | Walk every rejection record; if any single one fails TC35-S1/S2/S3, the whole investigation's TC35 fails                                |
| TC35-S5 | If every rejection carries a valid reason, the rejection set is fully documented (positive form)      | Closes the rule both directions so the audit can pass investigations, not just reject them                                      | Pre-acceptance check                                     | Confirm every rejection record has either a valid `EvidenceBased` reason or a valid `PreferenceBased` reason                            |
| TC35-S6 | The priority field cannot be a name outside the closed set of six                                     | Prevents "I just prefer this one" via invented priorities like `UserChoice`, `MyPick`, `Hunch`                                   | Rejection write whose `priority` is unrecognised         | Compare against the six-value enum; anything else ⇒ reject                                                                              |
| TC35-S7 | A rejection cannot be both `EvidenceBased` AND `PreferenceBased` simultaneously                        | One rejection, one reason — keeps the audit trail unambiguous and the schema simple                                             | Rejection write that mentions both an evidence cite and a priority | Confirm the rejection's reason is exactly one of the two shapes, not both                                                                |

## Worked example

```
Setup: Four hypotheses live; new evidence arrives; investigator rejects two.
       H2: rejected because Redis MONITOR (E1) shows cache invalidations DO fire
       H3: deprioritised because tokenizer re-migration has larger blast radius
            than the index-rebuild explanation (H1)

Walk:  H2 rejection record:
         { reason: EvidenceBased, cited_evidence: <hash of E1> }
         TC35-S1 ⇒ pass (cited evidence resolves)
       H3 deprioritisation record (treated as rejection only if user prefers H1
       over H4 outright; otherwise keep H3 active with lower priority):
         { reason: PreferenceBased, priority: BlastRadius,
           rationale: "tokenizer re-migration touches every doc + every replica" }
         TC35-S3 ⇒ pass (priority in set, rationale non-empty)

Anti-pattern:
       H4 rejection record:
         { reason: PreferenceBased, priority: UserChoice, rationale: "" }
         TC35-S2 ⇒ fail (rationale empty)
         TC35-S6 ⇒ fail (UserChoice not in allowed set)
       Reject the rejection: ask the investigator to either cite evidence or
       restate the preference with an allowed priority and a rationale.
```
