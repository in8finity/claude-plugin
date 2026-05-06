# F6 / F7 / F8 / F9 — Evidence Quality Rules

Four orthogonal evidence-quality gates. Replaces `fdp_evidence_quality.als`.
Encoded primarily as **invariant tables** (#6) with light **schema** (#4) and
**decision-table** (#5) accents where the rule pivots on a small enum.

---

## F6 — Cross-source absence verification

A zero-result query is one data point, not a conclusion. To claim a
behaviour does NOT occur, the investigator must enumerate every source
that could carry a trace and query each independently.

### Schema

```yaml
AbsenceClaim:
  sources_total:    int   # ≥0; the count of distinct sources that COULD carry a trace
  sources_checked:  int   # ≥0; the count actually queried
  all_agree_absent: bool  # true iff every queried source returned no trace
```

The claim is **verified** iff `sources_checked == sources_total > 0` AND
`all_agree_absent == true`.

### Invariants

| id    | rule                                                                 | why                                                                                                       | trigger                                                          | how to verify by hand                                                                                          |
|-------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| F6-S1 | Single source with multiple available ⇒ claim NOT verified            | One zero-result query is the canonical F6 failure                                                          | Evidence cites a single zero-result query as proof of absence    | Read `sources_checked` vs `sources_total`; if checked < total, the claim cannot be marked verified              |
| F6-S2 | All sources checked AND all agree ⇒ verified (positive form)          | Closes the rule positively so well-verified absence claims pass                                            | Pre-acceptance check                                              | Confirm `sources_checked == sources_total > 0` AND `all_agree_absent == true`                                  |
| F6-S3 | Zero sources checked ⇒ NOT verified                                   | Without any query, there is no evidence at all                                                             | Evidence claims absence without citing a query                   | If `sources_checked == 0`, reject                                                                              |
| F6-S4 | Partial check (`checked < total`) ⇒ NOT verified                      | Two-out-of-three is still missing the place where the trace might be                                       | Pre-acceptance check                                              | Reject any AbsenceClaim where checked < total                                                                  |
| F6-S5 | Sources disagree (`all_agree_absent == false`) ⇒ NOT verified          | Disagreement is signal, not absence — at least one source HAS a trace                                      | Cross-source query results conflict                              | Reject; investigate the disagreeing source as a positive lead                                                  |
| F6-S6 | Every absence-based evidence record carries an `Absence sources: N/M` field | Makes the rule mechanically auditable                                                                      | Evidence write whose claim is absence-based                      | Confirm the `Absence sources:` line exists; its values must satisfy F6-S2                                       |

---

## F7 — Trace the writer, not the reader

When a stored value is wrong, the bug is at the **write site**, not the
read site. Re-analysing the consumer of the value wastes time.

### Schema

```yaml
WrongValueEvidence:
  write_paths_enumerated: bool  # every code path that writes the field has been listed
  producer_identified:    bool  # one of those paths has been matched to the wrong value
  consumer_only_analysis: bool  # true if the only analysis so far is of the read site
```

Tracing is **complete** iff `write_paths_enumerated && producer_identified`.

### Invariants

| id    | rule                                                                                       | why                                                                                                | trigger                                                          | how to verify by hand                                                                                          |
|-------|--------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| F7-S1 | Consumer-only analysis without enumerated writes ⇒ tracing incomplete                      | The most common F7 failure: re-reading `renderInvoice()` instead of finding the writer            | Wrong-value evidence cites only consumer code                    | Reject; enumerate every UPDATE/INSERT/default-value/migration that writes the field                            |
| F7-S2 | Both `write_paths_enumerated` AND `producer_identified` ⇒ complete (positive form)         | Closes the rule positively                                                                         | Pre-acceptance check                                              | Confirm both flags `true`                                                                                       |
| F7-S3 | Enumerated but no match (`producer_identified == false`) ⇒ incomplete                      | A list of writers is not enough; one of them must be matched to the wrong value                   | All write paths listed but none tied to the bug                  | Reject; pick the most plausible writer and walk a concrete trace through it                                    |
| F7-S4 | `write_paths_enumerated == false` ⇒ incomplete (regardless of other flags)                 | Cannot match a producer if the producers haven't been enumerated                                   | Producer claimed without enumeration                             | Reject; demand the enumeration                                                                                 |
| F7-S5 | Wrong-value evidence carries `Analysis type: write-path` field                              | Mechanical auditability                                                                            | Evidence write                                                   | Confirm the field exists; its value should be `write-path`, not `read-path`                                    |

---

## F8 — Compute locally before estimating

When a numeric quantity is replicable locally (i.e., the inputs are
available and the computation is deterministic), compute the **exact**
value before reasoning about a "discrepancy" against an estimate.

### Decision table — reliability of a numeric evidence

| `computed_exact` | `estimated_from_proxy` | Reliability  |
|------------------|------------------------|--------------|
| `true`           | (any)                  | `Direct`     |
| `false`          | `true`                 | `Inferred`   |
| `false`          | `false`                | `Interpreted`|

### Invariants

| id    | rule                                                                                            | why                                                                                                                                                | trigger                                                              | how to verify by hand                                                                                                              |
|-------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| F8-S1 | `computed_exact == true` ⇒ reliability = `Direct`                                               | Exact computation against the actual inputs is the strongest available evidence                                                                    | Numeric evidence write                                                | Confirm the computation method ("local exact via tiktoken/numpy/etc."); reliability tag must be `Direct`                            |
| F8-S2 | `computed_exact == false` AND `estimated_from_proxy == true` ⇒ reliability = `Inferred`         | Estimates are derivations from a proxy; weaker than exact                                                                                          | Numeric evidence write                                                | Reliability tag must be `Inferred`, not `Direct`                                                                                    |
| F8-S3 | Neither computed nor estimated ⇒ reliability = `Interpreted`                                    | If neither available, the value is being asserted from prose                                                                                       | Pre-acceptance check                                                  | Reliability tag must be `Interpreted`                                                                                               |
| F8-S4 | `replicable_locally && !computed_exact && residual_percent > 5%` ⇒ residual is an error signal  | A "discrepancy" between estimate and stored value is not a finding; it's an estimation artefact until proven otherwise                             | Investigation cites a residual without exact computation              | Compute the exact value locally; if the residual disappears, the residual was the estimation error, not a bug                       |
| F8-S5 | `computed_exact == true` ⇒ no residual signal (the case is closed)                              | Once you have the exact value, there is no estimate to compare against                                                                             | Pre-acceptance check                                                  | If exact computed, drop the residual narrative entirely                                                                              |
| F8-S6 | `replicable_locally == false` ⇒ no residual signal (the residual cannot be evaluated locally)   | Cannot judge an estimation error if the inputs are unavailable                                                                                     | Investigation cites a residual on a non-replicable computation        | Treat the residual as `Inferred` at best; do not block on it                                                                         |
| F8-S7 | Numeric evidence carries `Computation method: <exact-local | proxy-estimate | prose>` field      | Mechanical auditability                                                                                                                            | Evidence write                                                        | Confirm the field exists                                                                                                            |

---

## F9 — DB fields are snapshots with write timestamps

A stored value is a **snapshot** taken at write time. Whether it
represents the **current** state depends on whether the write path keeps
the field live.

### Decision table — reliability of a stored field reading

| Field temporality | State question     | Reliability  |
|-------------------|--------------------|--------------|
| `LiveField`       | (any)              | `Direct`     |
| `SnapshotField`   | `HistoricalState`  | `Direct`     |
| `SnapshotField`   | `CurrentState`     | `Inferred`   |
| `ScheduledField`  | `HistoricalState`  | `Direct`     |
| `ScheduledField`  | `CurrentState`     | `Inferred`   |

Where:
- `LiveField` = updated on every relevant event (e.g., a status flag with a trigger / explicit recompute);
- `SnapshotField` = written once on creation, never updated (e.g., `total_tokens` written on every message create but never decremented on compaction);
- `ScheduledField` = updated on a cron / batch (lags reality between runs).

### Invariants

| id    | rule                                                                              | why                                                                                                                          | trigger                                                          | how to verify by hand                                                                                                          |
|-------|-----------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| F9-S1 | `LiveField` ⇒ `Direct` for any state question                                     | Live fields update on every relevant event; reading them gives the current truth                                              | Hypothesis cites a live field's value                            | Confirm via the write path (F7) that the field is updated on every relevant event                                              |
| F9-S2 | `SnapshotField` ⇒ `Direct` for `HistoricalState`                                  | A snapshot IS the historical state at write time                                                                              | Hypothesis asks "what was the value at time T"                   | Confirm the snapshot's write timestamp matches the time of interest                                                            |
| F9-S3 | `SnapshotField` ⇒ `Inferred` (not `Direct`) for `CurrentState`                    | The canonical F9 failure: assuming `total_tokens` represents current usage when it is cumulative                              | Hypothesis cites a stored field's value as current truth         | Trace the write path; if writes are insert-only (no UPDATE / no decrement), downgrade reading-as-current to `Inferred`         |
| F9-S4 | `ScheduledField` ⇒ `Inferred` for `CurrentState`, `Direct` for `HistoricalState`  | Cron-updated fields lag real time; current reading is at most as fresh as the last cron tick                                  | Hypothesis cites a cron-updated field's value as current truth   | Check the cron's last-run timestamp; degrade currentness accordingly                                                            |
| F9-S5 | Only `LiveField` is `Direct` for `CurrentState`                                   | Inverted statement of S1-S4: anything that isn't live cannot be `Direct` for current state                                    | Pre-acceptance check                                              | If the leading hypothesis depends on a current-state reading, confirm the field is `LiveField`; otherwise, downgrade           |
| F9-S6 | Evidence carries `Field temporality: <live | snapshot | scheduled>` field         | Mechanical auditability                                                                                                       | Evidence write whose value comes from a stored field             | Confirm the field exists                                                                                                        |

## Worked example (F9 case)

```
Setup: Hypothesis claims conversation conv-8832 currently uses 45,230 tokens
       Source: SELECT total_tokens FROM conversations WHERE id = 'conv-8832'
       The conversation has had compaction events.

Walk:  Trace the write path for `total_tokens` (F7):
         INSERT on message create:        ✓ writes
         UPDATE on compaction:             ✗ NOT updated
         UPDATE on message delete:         ✗ NOT updated
       Field temporality classification: SnapshotField (insert-only)
       State question: CurrentState
       F9-S3 ⇒ reliability = Inferred, NOT Direct
       F9-S5 ⇒ this hypothesis cannot be accepted on a stored-value reading

Outcome: Recompute current usage from live messages (e.g., SUM of token
         counts of currently-resident messages) before treating the value
         as current state.
```
