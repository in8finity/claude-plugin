# Shared Core — Enums and Source Classification Function

Shared atom definitions used by `fdp_temporal_core.md`, `fdp_skip_protocol.md`,
and the per-rule self-models. Replaces `system-models/shared/fdp_core.als`.
Encoded as a **type taxonomy** (#7) plus the F3 lookup table (which mirrors
the canonical `fdp_source_classification.md`).

## Investigation steps (outer loop)

- `S0_Symptom`        — document the symptom
  - `S0a_Tooling`     — inventory tooling
  - `S0b_Verify`      — verify the symptom against production
- `S1_Model`          — build the minimal **textual** model (replaces "build the formal model")
- `S2_Hypotheses`     — generate hypotheses
- `S3_Checks`         — design distinguishing checks
- `S4_Facts`          — collect facts
- `S5_Update`         — update model with facts (re-walk affected invariant rows)
- `S6_Equivalence`    — check diagnostic equivalence
- `S7_Deepen`         — deepen the model
- `S8_Terminate`      — terminate or iterate

> **Variant note.** `S1_Model` and `S5_Update` deliberately do NOT mean "run a
> solver". In the textual variant they mean "build / extend a textual model
> from the representation menu and record a hand walkthrough". This is the
> only semantic shift relative to the canonical core.

## Hypothesis status

- `Active`             — created but not yet judged against evidence
- `Compatible`         — evidence consistent; not yet uniquely supported
- `Weakened`           — partially refuted; some sub-claims fail
- `Undistinguished`    — diagnostically equivalent to another live hypothesis
- `Rejected`           — terminal; explicit rejection reason recorded (per TC35)
- `Accepted`           — terminal; sole `Compatible` after termination gate

Status transitions are constrained by the lifecycle (see
`fdp_temporal_core.md`). Both `Rejected` and `Accepted` are terminal —
no transitions out of them.

## Fact reliability (ordered)

1. `Direct`             — strongest; runtime / authoritative
2. `Inferred`           — production-shaped but decayed
3. `Interpreted`        — derived from non-runtime sources
4. `UnreliableSource`   — known-divergent surface

(Defined in detail in `fdp_source_classification.md`.)

## Diagnostic strength of a check

- `Strong`             — confirms one hypothesis AND excludes another
- `Weak`               — compatible with multiple hypotheses
- `Irrelevant`         — compatible with every live hypothesis (zero info gain)

## Task type (F4 axis)

- `Investigate`        — first fact may be `Direct` or `Inferred`
- `Fix`                — first fact MUST be `Direct`

## Cause classes (M1's 14 blind-spot categories)

The blind-spot checklist that "alternative considered" (M2) must walk
to be honoured. One row per class; M2 records which were considered.

- `CC_Concurrency`         [concurrent execution, race conditions]
- `CC_SharedMutableState`  [globals, singletons, in-process caches]
- `CC_ObjectLifecycle`     [creation/teardown ordering, dangling refs]
- `CC_Caching`             [staleness, key collisions, TTL drift]
- `CC_AsyncBoundaries`     [retries, queues, eventual consistency]
- `CC_ExternalSystem`      [vendor APIs, partial outages, schema drift]
- `CC_PartialObservability`[missing logs, sampling, missing dimensions]
- `CC_ConfigFeatureFlags`  [flag drift, env-var divergence]
- `CC_DataMigration`       [partial backfills, schema migrations]
- `CC_TenantIsolation`     [cross-tenant leakage, scope coercion]
- `CC_AuthState`           [session, token, role, claims]
- `CC_DeploymentDrift`     [version skew, partial rollouts, canary]
- `CC_MultiArtifact`       [client/server contract drift]
- `CC_BuildPipeline`       [CI cache, untracked files, baseline mismatch]

## Source types (F3 axis)

- **`Direct` sources**
  - `ProductionDB`             — live production data store query
  - `RecentProductionLogs`     — `<7d` old production logs
  - `LiveAPIResponse`          — synchronous response from production API
  - `DeployedConfig`           — config / env var read from running deployment
- **`Inferred` sources**
  - `OldProductionLogs`        — `≥7d` old production logs
  - `TextualModelWalkthrough`  — result of walking a textual model by hand
                                  (variant rename of `AlloyModelResult`)
  - `UserReport`               — aggregate user complaints
- **`Interpreted` sources**
  - `RepoCode`                 — source code in repository
  - `LocalGitHistory`          — local git working-copy history
  - `PriorReport`              — previous investigation / postmortem
  - `SpecDesignDoc`            — specification / design doc
  - `UserVerbalDescription`    — human paraphrase of behaviour
  - `ThirdPartyDocs`           — vendor / library docs
- **`UnreliableSource`**
  - `MobileAppCode`            — distributed clients with skew

For the full lookup table and safety properties, see
`fdp_source_classification.md`.
