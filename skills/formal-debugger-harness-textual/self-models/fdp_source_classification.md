# F3 — Source Classification

Static mapping from a fact's source to its reliability tier. Replaces
`fdp_source_classification.als`. Encoded as a **decision/lookup table** (#5)
plus an **invariant table** (#6) for the standalone safety properties.

## Reliability tiers (ordered, strongest to weakest)

1. `Direct` — produced from a live, authoritative source at investigation time
2. `Inferred` — produced from a source that was authoritative at the time it was captured but may have decayed
3. `Interpreted` — derived by a human or by reading non-runtime artefacts; not production truth
4. `UnreliableSource` — known-divergent surface (e.g. distributed mobile clients)

Reliability ordering: `Direct > Inferred > Interpreted > UnreliableSource`.

## Source → Reliability lookup table

| Source                    | Reliability        | Notes                                                          |
|---------------------------|--------------------|----------------------------------------------------------------|
| `ProductionDB`            | `Direct`           | Live query against the production data store                   |
| `RecentProductionLogs`    | `Direct`           | <7 days old; older entries downgrade (see `OldProductionLogs`) |
| `LiveAPIResponse`         | `Direct`           | Synchronous response from the production API                   |
| `DeployedConfig`          | `Direct`           | Config / env var read from the running deployment              |
| `OldProductionLogs`       | `Inferred`         | ≥7 days old — production but decayed                           |
| `TextualModelWalkthrough` | `Inferred`         | Result of walking a textual model by hand against evidence     |
| `UserReport`              | `Inferred`         | Aggregate user complaints; production-shaped but not captured  |
| `RepoCode`                | `Interpreted`      | Source code is design-time, never runtime truth                |
| `LocalGitHistory`         | `Interpreted`      | Local working-copy history; may diverge from deployed          |
| `PriorReport`             | `Interpreted`      | Prior investigations / postmortems                             |
| `SpecDesignDoc`           | `Interpreted`      | Specification or design doc                                    |
| `UserVerbalDescription`   | `Interpreted`      | Human paraphrase of behaviour                                  |
| `ThirdPartyDocs`          | `Interpreted`      | External vendor / library docs                                 |
| `MobileAppCode`           | `UnreliableSource` | Distributed clients with version/locale skew                   |

The lookup is total: every source type has exactly one reliability. No row maps
to multiple tiers.

## Invariants

| id      | rule                                                                                      | why                                                                                                  | trigger                                              | how to verify by hand                                                                                     |
|---------|-------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| F3-S1   | Every `SourceType` value maps to exactly one `Reliability`                                | A partial or multi-valued mapping would let the same source justify different acceptance decisions  | New source type added                                | Walk the lookup table — confirm every `SourceType` enum value appears once and only once                  |
| F3-S2   | `RepoCode → Interpreted`; never `Direct`                                                  | Repo code is design-time, not runtime; tagging it `Direct` is the central F3 failure                | Any evidence row whose source is repo code           | Confirm the row in the lookup table; reject any evidence record that pairs `source=RepoCode` with `Direct`|
| F3-S3   | The four `Direct` sources are exactly: `ProductionDB`, `RecentProductionLogs`, `LiveAPIResponse`, `DeployedConfig` | Closes the `Direct` set so future additions are explicit                                             | New source proposed as `Direct`                      | Confirm there are exactly 4 rows mapping to `Direct`; new `Direct` source requires this rule's update     |
| F3-S4   | `MobileAppCode → UnreliableSource`                                                        | Distributed clients are not production truth at investigation time                                   | Evidence cites mobile-client behaviour               | Confirm row in lookup table                                                                               |
| F3-S5   | `RecentProductionLogs → Direct` AND `OldProductionLogs → Inferred`                        | Production logs decay; the >7 day boundary is the decay point                                        | Evidence cites a production log                      | Check the log's age field — `<7d` ⇒ `Direct`, `≥7d` ⇒ `Inferred`                                          |
| F3-S6   | `TextualModelWalkthrough → Inferred`; never `Direct`                                      | A walkthrough is a derivation over collected facts, not a fresh production observation               | Hypothesis cites a model walkthrough as evidence     | Confirm row in lookup table; the walkthrough record is `Inferred` even when every fact in it is `Direct`  |
| F3-S7   | If a fact has `reliability=Interpreted`, its source is NOT in the four `Direct` sources   | Symmetric to F3-S2: prevents tagging a production source as `Interpreted`                            | Cross-tag audit                                      | Walk evidence rows; reject any row whose `reliability=Interpreted` but `source` is in the `Direct` set    |
| F3-S8   | A fact set whose every source is `RepoCode` contains no `Direct` evidence                 | Consequence used by PV1 (no acceptance without `≥1 Direct` fact) — repo-only investigations cannot accept | Pre-acceptance check                                 | Walk the evidence log; if every row has `source=RepoCode`, PV1 blocks acceptance                          |
| F3-S9   | `reliability` always consistent with `source` for every fact                              | The F3 invariant restated explicitly so the audit script can flag manual overrides                   | Continuous (every evidence write)                    | For every `E<N>` row, recompute `lookup[source]` and compare to the stored `reliability`                  |

## Worked example (counterexample-style)

```
Setup:  E1 { source: RepoCode, reliability: Direct, text: "checked controller.ts line 42" }
Walk:   F3-S2 row applies. Lookup[RepoCode] = Interpreted, not Direct.
        ⇒ E1 violates F3-S2. Reject the evidence record. Re-tag as Interpreted
        and re-evaluate any hypothesis that cited E1 as Direct support.
```
