# S0-V.1 — Symptom Proximity (Transport-Shaped Symptoms)

Transport-shaped symptoms (DNS failure, `gaierror`, connection refused,
socket timeout, 5xx, health-check fail) may be downstream effects of the
target process never starting. Before any transport-layer hypothesis can
be accepted, the investigation must have `Direct` evidence of upstream
liveness. Replaces `fdp_symptom_proximity.als`. Encoded as a
**decision/lookup table** (#5) for the gate plus an **invariant table** (#6)
for the safety properties.

## Symptom shape lookup

| Shape (matches symptom text…)                                                                  | Required liveness evidence before transport hypothesis |
|------------------------------------------------------------------------------------------------|--------------------------------------------------------|
| `TransportLayer`: `gaierror`, `Name or service not known`, `Connection refused`, `socket timeout`, `5xx`, `EHOSTUNREACH`, `health-check fail`, `DNS resolution failed`, `connection reset` | `Direct` AND `observedLive=yes`                        |
| `NonTransport`: business-logic errors, data corruption, wrong field values, stale cache, anything that doesn't reach the network layer | None — S0-V.1 does not gate non-transport hypotheses   |

Classification rule: if the symptom text contains any of the transport
markers above, treat it as `TransportLayer`. The rule is conservative —
ambiguous cases default to `TransportLayer` (gate engaged).

## Liveness evidence shape

A liveness witness has two fields:

```
LivenessEvidence E<N>
  Reliability:     <Direct | Inferred | Interpreted | UnreliableSource>
  Observed live:   <yes | no>
```

The witness **passes** S0-V.1 iff `Reliability=Direct` AND `Observed live=yes`.

## Invariants

| id      | rule                                                                                  | why                                                                                                                                  | trigger                                                            | how to verify by hand                                                                                                                            |
|---------|---------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| S0V1-S1 | Non-transport symptoms ignore liveness witness — S0-V.1 is satisfied automatically    | The gate's purpose is to catch the "transport error means upstream is dead" mode; for business-logic bugs the gate is irrelevant     | Symptom classified `NonTransport`                                  | Confirm the classification; if `NonTransport`, no liveness witness is required by this rule                                                      |
| S0V1-S2 | Transport-shaped symptom + non-`Direct` liveness ⇒ S0-V.1 fails                       | Inferred / Interpreted liveness can be read from stale logs or code; only a `Direct` observation rules out "process never started"  | Transport hypothesis cites liveness evidence whose reliability is not `Direct` | Read the witness's `Reliability` field; anything other than `Direct` ⇒ block                                                                     |
| S0V1-S3 | Transport-shaped symptom + `Observed live=no` ⇒ S0-V.1 fails                          | Even a `Direct` witness saying "the process is not live" supports rather than refutes the upstream-dead hypothesis                   | Liveness evidence captured but `Observed live=no`                  | Read the `Observed live` field; if `no`, the transport hypothesis is unsupported and the upstream-dead hypothesis becomes the leading branch    |
| S0V1-S4 | Interpreted liveness (e.g., reading repo code or a deployment doc) blocks the gate    | Transport bugs are runtime; only runtime evidence can prove liveness                                                                 | Witness whose source is `RepoCode`, `SpecDesignDoc`, or similar    | Cross-check with F3: any source classified `Interpreted` cannot satisfy S0-V.1                                                                  |
| S0V1-S5 | A valid transport investigation exists (positive sanity property)                     | Closes the rule both directions — there must be a witness shape that passes the gate so the rule is not vacuously blocking          | Any successful transport investigation                             | Confirm at least one witness exists with `Reliability=Direct` AND `Observed live=yes` BEFORE accepting any transport hypothesis                  |
| S0V1-S6 | Topology / config changes proposed for a transport-shaped symptom before liveness is proven count as OB1 violations | S0-V.1 and OB1 reinforce each other; blind transport interventions break both                                                        | User has already changed network / DNS / service config            | Before any further intervention, walk OB1's table for each change; pair the OB1 violation with the missing S0-V.1 witness in the report          |

## Worked example

```
Setup: CI failing with socket.gaierror: [Errno -2] Name or service not known: 'app'
       Symptom shape: TransportLayer (matches gaierror + 'name not known').
       Available liveness evidence:
         E1: source=docker-compose.yml,    reliability=Interpreted, observed=?
         E2: source=service rename log,    reliability=Interpreted, observed=?
       No `Direct` evidence of the 'app' container's startup state.

Walk:  S0V1-S2 — E1 reliability=Interpreted, not Direct ⇒ FAIL
       S0V1-S2 — E2 reliability=Interpreted, not Direct ⇒ FAIL
       S0V1-S5 — no witness yet ⇒ no transport hypothesis can be accepted

Outcome: First hypothesis must be 'the target process (app) never started or
         crashed during startup,' BEFORE digging into DNS/network topology.
         Request `Direct` evidence: container status, startup logs, process
         list. Only after S0-V.1 passes does the transport branch reopen.
```
