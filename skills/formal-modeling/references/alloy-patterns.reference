# Alloy Modeling Patterns

Production-proven patterns for writing Alloy 6 models. Read this when writing a new model.

## Table of Contents

**Basics**
1. [Bool Helper](#1-bool-helper)
2. [Enum States](#2-enum-states)
3. [Nullable Fields (lone)](#3-nullable-fields)
4. [Fun (Pure Functions)](#4-fun-pure-functions)
5. [Set Comprehension & Let](#5-set-comprehension--let)
6. [Relation Lookup Syntax](#6-relation-lookup-syntax)
7. [Int Constraints with Ranges](#7-int-constraints-with-ranges)

**Structural Patterns**
8. [Soft-Delete Lifecycle](#8-soft-delete-lifecycle)
9. [Partial Unique Index](#9-partial-unique-index)
10. [Platform Mutual Exclusion (Disjoint Subtypes)](#10-platform-mutual-exclusion)
11. [Cross-System Integration](#11-cross-system-integration)
12. [Cache Consistency](#12-cache-consistency)
13. [Report/Pair Symmetry](#13-reportpair-symmetry)
14. [Chain/Linked List](#14-chainlinked-list)
15. [Ordered Enum Chain (Named Ranges)](#15-ordered-enum-chain)
16. [Event Sigs (Operation Snapshots)](#16-event-sigs)

**Temporal Patterns**
17. [Temporal State Machine](#17-temporal-state-machine)
18. [Relation Override Operator ++](#18-relation-override-operator)
19. [Frame Condition Composition + Stutter](#19-frame-condition-composition)
20. [Nested Eventually (Temporal Ordering)](#20-nested-eventually)

**UX / Access Control Patterns**
21. [Role×State×Field Access Matrix](#21-access-matrix)
22. [CTA Validity Checking](#22-cta-validity)
23. [Notification Recipient Sets](#23-notification-recipients)
24. [Template → Trigger State Mapping](#24-template-trigger-mapping)

**Data Conversion & Time-Series Patterns**
25. [Axiomatic Data Conversion + Singleton Lookup Map](#25-axiomatic-data-conversion)
26. [Data Format Mismatch Verification](#26-data-format-mismatch)
27. [Database Column Type Semantics](#27-db-column-types)
28. [Effect Bag (Typed Contributions)](#28-effect-bag)
29. [Sliding Window Verification](#29-sliding-window)

**Pipeline & Build Patterns**
30. [Pipeline DAG Verification + util/ordering](#30-pipeline-dag)
31. [Artifact Versioning & Staleness](#31-artifact-versioning)
32. [Freshness Guards](#32-freshness-guards)
33. [Proof of Work (Verification Evidence)](#33-proof-of-work)

**Verification Patterns**
34. [Scenario Predicates (Before/After)](#34-scenario-predicates)
35. [Scoping and Cardinality](#35-scoping-and-cardinality)
36. [Concurrency / Advisory Lock Modeling](#36-concurrency-modeling)
37. [Gap Assertion (Intentional Failure)](#37-gap-assertion)
38. [Resolved Choice (OR-Dependency)](#38-resolved-choice)
48. [Compositional Verification (Interface States)](#48-compositional-verification)

**Alloy 6 Essentials**
39. [Ordering Alias for Alloy 6](#39-ordering-alias)
40. [Temporal Invariants](#40-temporal-invariants)
41. [Until and Releases Operators](#41-until-and-releases)
42. [Disj Quantifier](#42-disj-quantifier)
43. [Module Parameterization](#43-module-parameterization)
44. [Sequences (util/sequniv)](#44-sequences)
45. [Inductive Invariant Structure](#45-inductive-invariant)
46. [Expect Annotations](#46-expect-annotations)
47. [Equivalence Classes (Range Partitioning)](#47-equivalence-classes-range-partitioning)

---

## 1. Bool Helper

Alloy has no built-in boolean. Use this pattern for flags:

```alloy
abstract sig Bool {}
one sig True, False extends Bool {}

sig User { deleted: one Bool }
pred alive[u: User]       { u.deleted = False }
pred softDeleted[u: User] { u.deleted = True }
```

## 2. Enum States

Model status enums as abstract sig with `one sig` variants:

```alloy
abstract sig SubStatus {}
one sig Pending, Active, Inactive, Canceled, Disabled extends SubStatus {}
```

Each status gets exactly one atom — lightweight and solver-friendly. No integer mapping needed.

## 3. Nullable Fields

Use `lone` for nullable fields, `one` for non-nullable:

```alloy
sig User {
  email       : lone Email,       -- NULL after soft-delete
  deviceToken : lone DeviceToken,  -- may not be set yet
  state       : one UserState      -- always present
}

-- Enforce presence/absence rules with facts
fact ActiveHasEmail {
  all u: User | u.state = Active => some u.email
}
fact DeletedHasNoEmail {
  all u: User | u.state = Deleted =>
    no u.email and no u.deviceToken
}
```

## 4. Fun (Pure Functions)

Use `fun` for domain logic mappings and computed values:

```alloy
-- Case-style pattern matching
fun mapEventToName[e: EventType] : one ActionName {
  e = Created  => Subscribe else
  e = Renewed  => Subscribe else
  e = Expired  => Unsubscribe else
  Cancel   -- default
}

-- Lookup function returning a set
fun effectsFor[record: ScoreRecord]: set Effect {
  { e: Effect | e.forRecord = record }
}

-- Computed property
fun localDay[t: Timestamp, tz: Timezone]: Day {
  DayMap.of[t][tz]
}
```

Functions are pure (no side effects) and can be used in facts, assertions, and predicates.

## 5. Set Comprehension & Let

Filter and bind intermediate results:

```alloy
-- Set comprehension: { var: SigType | predicate }
-- The binder must be a sig type, not a function call or variable.

-- Inside a predicate (let is expression-level, must be inside a formula body)
pred softDelete[u: User] {
  let userPending = { e: PendingEvent | e.owner = u } |
    PendingEvent' = PendingEvent - userPending and
    SkippedEvent' = SkippedEvent + userPending
}

-- In facts
fact UniqueRecord {
  all u: User, d: Day |
    lone { r: Record | r.user = u and r.day = d }
}

-- As a function — binder is the sig type, filter with 'in' for subsets
fun positiveEffects[r: Record]: set Effect {
  { e: Effect | e in effectsFor[r] and e.polarity = Positive }
}
```

Note: `{ e: effectsFor[r] | ... }` is invalid — the binder must be a sig type (`Effect`),
not a function call. Use `e: Effect | e in effectsFor[r] and ...` instead.

## 6. Relation Lookup Syntax

Model database indices and maps with `Key -> lone Value`:

```alloy
one sig ServiceCache {
  byEmail : Email  -> lone BackendUser,
  byExtId : ExtId  -> lone ServiceUser,
  byAppId : AppId  -> lone CacheEntry
}

-- Bracket lookup: Cache.index[key]
fact CacheEmailFresh {
  all c: ServiceCache, e: Email, u: BackendUser |
    c.byEmail[e] = u => alive[u] and u.email = e
}

-- Dual-key consistency
fact DualKeyConsistency {
  all e: Email, entry: CacheEntry |
    ServiceCache.byEmail[e] = entry =>
      ServiceCache.byAppId[entry.cachedAppId] = entry
}
```

The `Key -> lone Value` relation type gives map/dictionary semantics. `Key -> one Value` for total maps (every key has a value).

## 7. Int Constraints with Ranges

Alloy supports bounded integers. Use sparingly — symbolic enums are preferred, but Int works for arithmetic:

```alloy
sig Timezone { offsetHours: Int }

fact TimezoneRange {
  all tz: Timezone | tz.offsetHours >= -12 and tz.offsetHours <= 14
}

-- Classify with functions
abstract sig Direction {}
one sig West, Utc, East extends Direction {}

fun direction[tz: Timezone]: Direction {
  tz.offsetHours = 0 => Utc else
  tz.offsetHours > 0 => East else West
}
```

Prefer named ranges (see pattern 15) over raw Int when the values represent categories rather than quantities.

## 8. Soft-Delete Lifecycle

Pattern: a "deleted" entity keeps its row but must have no live children.

```alloy
sig User { deleted: one Bool }
sig Subscription { owner: one User, obsolete: one Bool }

fact NoLiveSubForDeletedUser {
  all u: User | u.deleted = True =>
    no s: Subscription | s.owner = u and s.obsolete = False
}
```

## 9. Partial Unique Index

At most one "live" record per identifier — mirrors SQL `UNIQUE ... WHERE is_obsolete = false`:

```alloy
fact PlatformUnique {
  all id: PlatformTxId |
    lone s: PlatformASub | s.platformA_id = id and s.obsolete = False
}
```

`lone` means "zero or one" — exactly the semantics of a partial unique index.

## 10. Platform Mutual Exclusion

An entity belongs to exactly one of several categories, modeled as subtypes:

```alloy
abstract sig Subscription {
  owner: one User, status: one SubStatus, obsolete: one Bool
}
sig PlatformASub extends Subscription { platformA_id: one PlatformAId }
sig PlatformBSub extends Subscription { platformB_id: one PlatformBId }

-- One platform per user at a time (mutual exclusion via implies)
fact OneActivePlatformPerUser {
  all u: User |
    let live = { s: Subscription | s.owner = u and s.obsolete = False } |
      (some live & PlatformASub) implies no (live & PlatformBSub)
}
```

## 11. Cross-System Integration

Model two systems' data side by side, assert consistency at the boundary:

```alloy
-- System A (backend)
sig BackendUser { email: lone Email, trackingId: lone TrackingId }

-- System B (service layer)
sig ServiceUser { appId: lone AppId }

-- Integration point: service linked to backend
sig ServiceCache { emailIndex: Email -> lone BackendUser }

-- Assert cache points to the correct live user
assert CachePointsToActiveUser {
  all e: Email, u: BackendUser |
    (some c: ServiceCache | c.emailIndex[e] = u) => u.state = Active
}
```

## 12. Cache Consistency

Model cache alongside source of truth, verify no stale references:

```alloy
sig Cache {
  byEmail: Email -> lone BackendUser,
  byExtId: ExtId -> lone ServiceUser
}

fact CacheEmailFresh {
  all c: Cache, e: Email, u: BackendUser |
    c.byEmail[e] = u => alive[u] and u.email = e
}
```

## 13. Report/Pair Symmetry

Two related entities that must reach the same state together:

```alloy
sig ReportPair {
  direct:   one Report,
  reverse:  one Report,
  explorer: one User,
  explored: one User
}

-- Both reports Ready together or not at all
assert PairSymmetry {
  all rp: ReportPair |
    rp.direct.state = Ready <=> rp.reverse.state = Ready
}
```

The `<=>` biconditional is the key — it enforces both directions of the implication.

## 14. Chain/Linked List

Model ordered sequences as acyclic linked lists:

```alloy
sig Day { next: lone Day }

-- Acyclic
fact DayChainAcyclic { no d: Day | d in d.^next }
-- Single root (one element with no predecessor)
fact SingleRoot { one d: Day | no d': Day | d'.next = d }
```

Use `^next` (transitive closure) for reachability queries, `*next` (reflexive-transitive) for "same or reachable."

## 15. Ordered Enum Chain

When you need comparison (`<`, `<=`) between enum values without using Int:

```alloy
abstract sig ScoreRange { higher: lone ScoreRange }

one sig Floor extends ScoreRange {}
one sig Low   extends ScoreRange {}
one sig Mid   extends ScoreRange {}
one sig High  extends ScoreRange {}
one sig Peak  extends ScoreRange {}

fact ScoreRangeChain {
  Floor.higher = Low
  Low.higher   = Mid
  Mid.higher   = High
  High.higher  = Peak
  no Peak.higher
}

pred scoreLt[a, b: ScoreRange]  { b in a.^higher }
pred scoreLte[a, b: ScoreRange] { b in a.*higher }
```

This avoids Alloy's limited Int bitwidth while giving full ordering semantics.

## 16. Event Sigs

Model operations/events as sigs that capture state snapshots — useful for static models of complex workflows:

```alloy
-- An account creation event (snapshot of what happened)
sig CreateAccount {
  createdUser:  one User,
  syncedRecord: one ServiceRecord,
  syncEmail:    lone Email
}

fact Create_UserIsActive {
  all e: CreateAccount | e.createdUser.state = Active
}

-- A compound event linking sub-events
sig PlanMigration {
  account:   one User,
  oldSub:    one CancelEvent,
  newSub:    one CreateAccount,
  oldPlan:   one Plan,
  newPlan:   one Plan
}

fact Migration_DifferentPlans {
  all m: PlanMigration | m.oldPlan != m.newPlan
}
fact Migration_AccountActive {
  all m: PlanMigration | m.account.state = Active
}
```

Event sigs let you reason about sequences of operations in a static model (without temporal logic) by capturing the before/after state in one snapshot.

## 17. Temporal State Machine

Alloy 6 `var sig` for mutable state + explicit transition predicates:

```alloy
sig User {}
var sig ActiveUser  in User {}
var sig DeletedUser in User {}

pred register[u: User] {
  u not in ActiveUser + DeletedUser     -- guard
  ActiveUser'  = ActiveUser + u         -- next state
  DeletedUser' = DeletedUser            -- frame
}

fact Init { no ActiveUser and no DeletedUser }
fact Transitions {
  always (
    stutter
    or (some u: User | register[u])
    or (some u: User | softDelete[u])
  )
}
```

Key temporal operators:
- `formula'` — formula evaluated in the next state
- `always formula` — holds in every reachable state
- `eventually formula` — holds in some future state
- `once formula` — held in some past state
- `after formula` — holds in the immediately next state

## 18. Relation Override Operator ++

For surgical updates to relations in temporal models, use `++` instead of remove-then-add:

```alloy
pred subscribe[u: User, s: Sub] {
  -- ++ overwrites the mapping for key s, keeps all other entries
  owner'  = owner  ++ (s -> u)
  status' = status ++ (s -> Active)
}

-- Bulk update: set status to Disabled for all of a user's subs
-- Note: set comprehension binder must be a sig type, not a variable
pred softDelete[u: User] {
  let userSubs = { s: Sub | s in ExistingSub - ObsoleteSub and owner[s] = u } |
    status' = status ++ { s: Sub, st: SubStatus | s in userSubs and st = Disabled }
}
```

`++` is relation override: `R ++ (a -> b)` returns R with any existing `a -> ?` replaced by `a -> b`. Much cleaner than `(R - (a -> R[a])) + (a -> b)`.

## 19. Frame Condition Composition

Group unchanged state into reusable frame predicates, then compose them:

```alloy
pred frameUsers {
  ActiveUser'  = ActiveUser
  DeletedUser' = DeletedUser
}

pred frameSubs {
  ExistingSub' = ExistingSub
  ObsoleteSub' = ObsoleteSub
  owner'  = owner
  status' = status
}

pred frameEnv {
  Config' = Config
}

-- Stutter = all frames composed
pred stutter {
  frameUsers
  frameSubs
  frameEnv
}

-- Each transition composes only the frames it doesn't touch
pred register[u: User] {
  u not in ActiveUser + DeletedUser
  ActiveUser'  = ActiveUser + u
  DeletedUser' = DeletedUser
  frameSubs    -- subs unchanged
  frameEnv     -- env unchanged
}

pred subscribe[u: User, s: Sub] {
  ...
  frameUsers   -- users unchanged
  frameEnv     -- env unchanged
}
```

This prevents the error-prone pattern of repeating every var sig assignment in every transition. Add a new var sig → update one frame pred → all transitions that use it automatically preserve the new state.

**Stutter step**: compose all frames into a no-op transition. Every temporal model needs this — without stutter, the solver may report UNSAT on liveness properties because it can't find traces of the right length. Always include stutter in the `Transitions` fact.

## 20. Nested Eventually

Chain `eventually` to specify ordered multi-step scenarios:

```alloy
-- "First A happens, then later B, then later C"
run FullLifecycle {
  some u: User, s: Sub |
    eventually (u in ActiveUser and no ExistingSub        -- step 1: register
    and
    eventually (s in ExistingSub and owner[s] = u         -- step 2: subscribe
      and status[s] = Active
    and
    eventually (status[s] = Canceled                      -- step 3: cancel
    and
    eventually (status[s] = Active                        -- step 4: reactivate
    ))))
} for exactly 1 User, exactly 1 Sub, exactly 1 TxId, 10 steps
```

Each nested `eventually` means "and then at some later point." The solver finds the minimum trace that satisfies the ordering. Use `for N steps` to bound the search.

## 21. Role×State×Field Access Matrix

Model field-level access control as a three-way predicate: `canWrite[role, entity, field]`. This catches permission bugs that unit tests miss because they test one role at a time.

```alloy
-- Fields grouped by sensitivity
fun internalOnly : set Field { CostBreakdown + InternalNotes + BillingRef }
fun activeAllowed : set Field { BillingRef + Attachments + Approvals }

pred canWrite[r: Role, t: Task, f: Field] {
  r = Admin                                            -- admin: unrestricted
  or
  (r = Manager and (
    editable[t.state]                                   -- all fields in editable states
    or (t.state = Active and f in activeAllowed)        -- subset in active
    or (terminal[t.state] and f = BillingRef)           -- one field in terminal
  ))
  or
  (r = Owner and f not in internalOnly and f != HideFromViewer
    and (editable[t.state] or (t.state = Active and f in activeAllowed)))
  -- Viewer: no branch → always false (enforced by absence)
}
```

Key: the `canRead` predicate follows the same pattern. Assert properties across all combinations:

```alloy
-- Viewer has zero write access in any state
assert ViewerCannotWrite { all t: Task, f: Field | not canWrite[Viewer, t, f] }
-- Client roles cannot write internal fields
-- Note: quantifier binders must be sig types; use 'in' to filter by function result
assert ClientCannotWriteCosts {
  all t: Task, f: Field | f in internalOnly implies
    not canWrite[Owner, t, f] and not canWrite[Author, t, f]
}
-- Required fields are settable before submission
assert AllRequiredFieldsSettable {
  all f: Field, t: Task | f in required and editable[t.state]
    implies some r: Role - Viewer | canWrite[r, t, f]
}
```

Note: `all f: internalOnly` and `all f: required` are invalid — Alloy quantifier binders must
be sig types. Use `all f: Field | f in internalOnly implies ...` instead.

## 22. CTA Validity Checking

Verify that every call-to-action button in notification emails leads to an action the recipient can actually perform. This catches "dead button" bugs — an approve button sent to someone who can't approve, or a link to a form that's disabled.

```alloy
abstract sig Cta {}
one sig CtaView    extends Cta {}  -- link to entity (always valid)
one sig CtaApprove extends Cta {}  -- "Approve" button

-- CTA is valid = the implied action is available
pred ctaValid[c: Cta, r: Role, t: Task] {
  (c = CtaView)
  or (c = CtaApprove and t_approve[r, t])
}

-- Template → CTA mapping: which buttons appear in each email
fun templateCtasFor[tmpl: Template, r: Role, t: Task] : set Cta {
  { c: Cta |
    (c = CtaView)                                    -- always present
    or (c = CtaApprove                               -- approve button only when:
        and (r = Owner or r = Manager or r = Admin)  --   recipient can approve
        and t_approve[r, t]                          --   transition available
        and approvalPendingFor[r, t]                 --   their side hasn't approved
        and tmpl in TmplCostChanged + TmplSubmitted) --   relevant templates
  }
}

-- THE KEY ASSERTION: every CTA is valid for its recipient
assert AllCtasValidForRecipient {
  all tmpl: Template, r: Role, t: Task |
    t.state in triggerStates[tmpl]
    implies all c: templateCtasFor[tmpl, r, t] | ctaValid[c, r, t]
}
```

When this assertion FAILS, the counterexample shows the exact scenario: which template, which role, which state, which CTA is broken. This is more thorough than manual QA — it checks all combinations.

## 23. Notification Recipient Sets

Map each transition to the set of roles that receive a notification. Assert the sets are non-empty and correct.

```alloy
fun notifySubmit[t: Task] : set Role {
  Manager + Owner + Author
  + (t.hiddenFromViewer = False implies Viewer else none)
}

fun notifyStateChange : set Role {
  Manager + Owner + Author
}

-- Conditional inclusion: viewer only notified in certain states when visible
fun notifyFieldChange[t: Task] : set Role {
  Manager + Owner + Author
  + ((t.state = Review or t.state = Paused) and t.hiddenFromViewer = False
     implies Viewer else none)
}

-- Assert: hidden entities don't notify viewers
assert ViewerOnlyNotifiedWhenVisible {
  all t: Task | t.hiddenFromViewer = True implies {
    Viewer not in notifySubmit[t]
    Viewer not in notifyFieldChange[t]
  }
}
```

## 24. Template → Trigger State Mapping

Map notification templates to the project states that trigger them. This ensures templates only fire in states where their content makes sense.

```alloy
abstract sig Template {}
one sig TmplSubmitted extends Template {}
one sig TmplActivated extends Template {}
one sig TmplDone      extends Template {}

fun triggerStates[tmpl: Template] : set State {
  { s: State |
    (s = Review and tmpl = TmplSubmitted) or
    (s = Active and tmpl = TmplActivated) or
    (s = Done   and tmpl = TmplDone) or
    -- Field-change templates fire in editable states
    (editable[s] and tmpl = TmplFieldChanged)
  }
}

-- Assert: cost-change template only fires where cost fields are writable
assert CostChangedOnlyInWritableStates {
  all t: Task |
    t.state in triggerStates[TmplCostChanged]
    implies canWrite[Manager, t, CostBreakdown]
}
```

## 25. Axiomatic Data Conversion

When a conversion (timezone, unit, format) is too complex to implement in Alloy, **axiomatize** its properties instead. State what the conversion guarantees without coding the algorithm.

```alloy
sig Timestamp { utcDay: Day }
sig Timezone  { offsetHours: Int }

-- Global conversion function (axiomatized, not implemented)
one sig DayMap { of: Timestamp -> Timezone -> one Day }
fun localDay[t: Timestamp, tz: Timezone]: Day { DayMap.of[t][tz] }

-- Classification
abstract sig Direction {}
one sig West, Utc, East extends Direction {}
fun dir[tz: Timezone]: Direction {
  tz.offsetHours = 0 => Utc else tz.offsetHours > 0 => East else West
}

-- Axiom 1: UTC timezone preserves the day
fact UtcIdentity {
  all t: Timestamp, tz: Timezone |
    dir[tz] = Utc implies localDay[t, tz] = t.utcDay
}
-- Axiom 2: East TZ shifts at most +1 day
fact EastBound {
  all t: Timestamp, tz: Timezone |
    dir[tz] = East implies
      (localDay[t, tz] = t.utcDay or localDay[t, tz] = t.utcDay.next)
}
-- Axiom 3: West TZ shifts at most -1 day
fact WestBound {
  all t: Timestamp, tz: Timezone |
    dir[tz] = West implies
      (localDay[t, tz] = t.utcDay or t.utcDay = localDay[t, tz].next)
}
-- Axiom 4: Larger offset never gives earlier day (monotonicity)
fact Monotonicity {
  all t: Timestamp, tz1, tz2: Timezone |
    tz1.offsetHours < tz2.offsetHours implies
      (localDay[t, tz1] = localDay[t, tz2]
       or localDay[t, tz1].next = localDay[t, tz2])
}
```

The solver can then prove properties about timezone conversion (e.g., "East is never earlier than West") without modeling actual clock arithmetic. This technique works for any complex transformation: currency conversion, coordinate projection, encoding/decoding.

**Singleton lookup map**: The `one sig DayMap { of: Timestamp -> Timezone -> one Day }` is a global function table — the solver fills in values that satisfy all axioms. This technique generalizes to any function you can't implement: currency exchange rates, feature flag evaluations, external API responses.

## 26. Data Format Mismatch Verification

Model two competing interpretations of the same stored value, then prove which is correct. This catches encoding/decoding bugs where data passes through a pipeline that misinterprets its format.

```alloy
-- Two conversion functions that interpret the same timestamp differently
-- correctFn: extracts literal day from the stored value (right for wire-format data)
fun correctFn[t: Timestamp]: Day { t.utcDay }
-- brokenFn: applies timezone offset (WRONG for wire-format — double-shifts the day)
fun brokenFn[t: Timestamp, tz: Timezone]: Day { localDay[t, tz] }

-- Wire-format encoding: the stored UTC fields equal the local wall-clock
pred wireEncoded[t: Timestamp, intendedDay: Day] {
  t.utcDay = intendedDay
}

-- Assert: correctFn always recovers the intended day
assert CorrectFnWorks {
  all t: Timestamp, d: Day | wireEncoded[t, d] => correctFn[t] = d
}

-- Assert: brokenFn can produce a result different from the intended day
-- (This check should FIND a counterexample — proving the bug exists)
assert BrokenFnAlwaysCorrect {
  all t: Timestamp, tz: Timezone, d: Day |
    wireEncoded[t, d] => brokenFn[t, tz] = d
}
-- EXPECTED: counterexample found when dir[tz] = East and midnight crosses

-- Scenario: witness the double-offset bug
run DoubleOffsetBug {
  some t: Timestamp, tz: Timezone, d: Day |
    dir[tz] = East and wireEncoded[t, d]
    and brokenFn[t, tz] = d.next    -- wrong
    and correctFn[t] = d            -- right
} for 3 but exactly 1 Timestamp, exactly 1 Timezone, exactly 3 Day, 6 Int
```

This pattern is valuable whenever data crosses system boundaries with different format assumptions (API wire format vs DB storage, local time vs UTC, ISO strings vs Date objects).

## 27. Variant-Dependent Behavior

Model an entity that behaves differently based on its variant (subtype), with facts constraining which fields are present per variant. Useful for DB column types, API response formats, config options.

```alloy
abstract sig Variant {}
one sig TypeA extends Variant {}  -- e.g., timestamptz, JSON, encrypted
one sig TypeB extends Variant {}  -- e.g., timestamp, plain text, unencrypted

sig StoredValue {
  variant : one Variant,
  primary : one Datum,       -- always present
  extra   : lone Datum       -- only present for TypeB (lone = nullable)
}

-- Variant determines which fields exist
fact TypeAHasNoExtra   { all v: StoredValue | v.variant = TypeA implies no  v.extra }
fact TypeBHasExtra     { all v: StoredValue | v.variant = TypeB implies one v.extra }

-- Behavior depends on variant
fun interpret[v: StoredValue, ctx: Context]: Result {
  v.variant = TypeA => transform[v.primary, ctx]  -- context-dependent
  else v.extra                                     -- literal, context-independent
}

-- Assert: TypeB is context-independent (same result regardless of context)
assert TypeBIgnoresContext {
  all v: StoredValue, c1, c2: Context |
    v.variant = TypeB implies interpret[v, c1] = interpret[v, c2]
}
```

This generalizes database column types (timestamptz vs timestamp), serialization formats (JSON vs protobuf), encryption modes, etc.

## 28. Effect Bag (Typed Contributions)

Replace integer accumulation (`score += impact`) with a **set of typed contribution sigs**. Each contribution carries metadata (source, target, magnitude, polarity). Reasoning about the bag uses set operations, not arithmetic.

```alloy
-- A contribution from one event to one record
sig Contribution {
  source:    one Event,
  target:    one Record,
  magnitude: one Tier,     -- strength (e.g., TierLow/Mid/High)
  polarity:  one Sign      -- direction (Positive/Negative)
}

-- Uniqueness: one contribution per (event, record) pair
fact ContributionUnique {
  all ev: Event, r: Record |
    lone c: Contribution | c.source = ev and c.target = r
}

-- Contributions inherit properties from source event
fact ContributionMatchesSource {
  all c: Contribution | c.magnitude = c.source.tier and c.polarity = c.source.sign
}

-- Bijection: contribution exists iff event genuinely affects the record
fact ContributionBijects {
  all c: Contribution | affects[c.source, c.target]
  all ev: Event, r: Record | affects[ev, r] implies
    one c: Contribution | c.source = ev and c.target = r
}

-- Bag accessors
fun contributionsFor[r: Record]: set Contribution { { c: Contribution | c.target = r } }
fun positiveContributions[r: Record]: set Contribution {
  { c: contributionsFor[r] | c.polarity = Positive }
}

-- Qualitative net direction (no arithmetic)
pred netPositive[r: Record] { some positiveContributions[r] and no negativeContributions[r] }
pred netNegative[r: Record] { no positiveContributions[r] and some negativeContributions[r] }
```

This is more powerful than `score: Int` because you can assert properties about individual contributions, filter by source, and reason about composition without Alloy's limited integer bitwidth.

## 29. Sliding Window Verification

Verify which records fall inside or outside a multi-slot attribution window. An event contributes to records within a window (e.g., today + tomorrow); when the window boundaries shift (parameter change, timezone, rounding), records may slide in or out incorrectly.

```alloy
sig Day { next: lone Day }
sig User {}
sig Record { user: one User, day: one Day }

sig Event {
  user: one User,
  day:  one Day      -- the day this event targets
}

-- Attribution window: event on day D affects records for D and D+1
fun targetWindow[ev: Event]: set Record {
  { r: Record | r.user = ev.user and (r.day = ev.day or r.day = ev.day.next) }
}

-- Last-day events have at most one target (no D+1 exists)
assert LastDayAtMostOneTarget {
  all ev: Event | no ev.day.next implies lone targetWindow[ev]
}

-- Two events on adjacent days share exactly one record in their windows
run OverlappingWindows {
  some ev1, ev2: Event, r: Record |
    ev1.user = ev2.user and ev1 != ev2
    and ev1.day.next = ev2.day
    and r in targetWindow[ev1] and r in targetWindow[ev2]
} for 4 but exactly 2 Event, exactly 3 Day, exactly 2 Record

-- Window shift: if the event's day changes (e.g., timezone reinterpretation),
-- the entire window slides by one
run WindowShift {
  some ev: Event, r: Record, d: Day |
    ev.day = d and r.day = d
    and r in targetWindow[ev]          -- r is in the window now
    -- if ev.day were d.next instead, r would be outside the window
} for 3 but exactly 1 Event, exactly 3 Day
```

This pattern catches off-by-one and boundary-shift bugs in any system with window-based attribution: time-series aggregation, billing cycles, retention windows, SLA calculations.

## 30. Pipeline DAG Verification

Model a multi-step processing pipeline as `Step` sigs producing/consuming `Artifact` sigs. Assert that every step's inputs are produced by earlier steps — catches ordering violations and missing dependencies.

```alloy
abstract sig Artifact { producedBy: one Step }

one sig RawData    extends Artifact {}
one sig Validated  extends Artifact {}
one sig Enriched   extends Artifact {}
one sig IndexData  extends Artifact {}
one sig Report     extends Artifact {}

abstract sig Step { requires: set Artifact, produces: set Artifact }

one sig S1_Validate extends Step {}
one sig S2_Enrich   extends Step {}
one sig S3_Index    extends Step {}
one sig S4_Report   extends Step {}

open util/ordering[Step]

fact StepOrder {
  first = S1_Validate
  next[S1_Validate] = S2_Enrich
  next[S2_Enrich]   = S3_Index
  next[S3_Index]    = S4_Report
}

fact Productions {
  RawData.producedBy   = S1_Validate   -- pre-exists, validated by S1
  Validated.producedBy = S1_Validate
  Enriched.producedBy  = S2_Enrich
  IndexData.producedBy = S3_Index
  Report.producedBy    = S4_Report
}

fact Dependencies {
  S1_Validate.requires = RawData
  S2_Enrich.requires   = Validated + RawData
  S3_Index.requires    = Enriched
  S4_Report.requires   = IndexData + Enriched
}

-- THE KEY ASSERTION: no step uses artifacts from the future
assert DependenciesSatisfied {
  all s: Step, a: s.requires | lt[a.producedBy, s]
}
check DependenciesSatisfied for 10

-- Every artifact has exactly one producer
assert SingleProducer { all a: Artifact | one a.producedBy }
check SingleProducer for 10
```

Use `util/ordering[Step]` for strict total order — provides `first`, `last`, `next`, `lt`, `gt` out of the box.

**Alloy 6 warning**: `next` is also the temporal "next state" keyword. In models that use both `util/ordering` and `var` (temporal), alias the import to avoid ambiguity: `open util/ordering[Step] as ord` then use `ord/next[S1]` instead of bare `next[S1]`.

**Note**: `assert SingleProducer { all a: Artifact | one a.producedBy }` is redundant — the `one` multiplicity on `producedBy: one Step` already enforces exactly one producer at the type level. The assertion trivially passes and can be omitted. Include it only as documentation for readers unfamiliar with Alloy multiplicities.

## 31. Artifact Versioning & Staleness

When artifacts are mutable (overwritten by multiple steps), track versions to detect stale reads. A consumer sees stale data when a newer version was written between the version it reads and its own execution.

```alloy
sig ArtifactVersion {
  artifact:  one Artifact,
  writtenBy: one Step,
  version:   one Int
}

-- Mutable artifacts get multiple versions
fact MutableVersions {
  some v1: ArtifactVersion | v1.artifact = Enriched and v1.writtenBy = S2_Enrich and v1.version = 1
  some v2: ArtifactVersion | v2.artifact = Enriched and v2.writtenBy = S3_Index  and v2.version = 2
}

-- Staleness: consumer reads artifact but a newer version exists from an earlier step
pred isStale[consumer: Step, art: Artifact] {
  art in consumer.requires
  some v1, v2: ArtifactVersion |
    v1.artifact = art and v2.artifact = art
    and v1.version < v2.version
    and lt[v1.writtenBy, consumer]
    and lt[v2.writtenBy, consumer]
}

-- Scenario: detect stale read
run StaleRead {
  some s: Step, a: Artifact | isStale[s, a]
} for 10 but 4 ArtifactVersion, 6 Int
```

This pattern is essential for any pipeline where intermediate artifacts (caches, snapshots, indices) can go stale after mutation steps.

## 32. Freshness Guards

Force steps that consume cached/snapshot data to verify it matches the current on-disk version before proceeding. Model the check as a `FreshnessCheck` sig.

```alloy
sig FreshnessCheck {
  step:     one Step,
  compares: one Artifact,    -- the cached/snapshot artifact
  against:  one Artifact     -- the authoritative on-disk artifact
}

fact FreshnessGuards {
  -- Any step reading IndexData must verify it matches current Enriched
  some fc: FreshnessCheck |
    fc.step = S4_Report and fc.compares = IndexData and fc.against = Enriched
}

-- Assert: every consumer of a snapshot artifact has a freshness check
assert SnapshotConsumersCheckFreshness {
  all s: Step | IndexData in s.requires implies
    some fc: FreshnessCheck | fc.step = s and fc.compares = IndexData
}
check SnapshotConsumersCheckFreshness for 10
```

This turns implicit assumptions ("the index is up to date") into explicit, verifiable requirements.

## 33. Proof of Work (Verification Evidence)

Enforce that verification steps produce reports with specific evidence — prevents hollow "all checks passed" outputs that don't actually verify anything.

```alloy
-- Reuse Bool from Pattern 1 (True/False). Do NOT redefine Bool with Yes/No —
-- a model that combines patterns would get 4 Bool atoms and break.

sig ProofOfWork {
  step:                 one Step,
  requiresSourceQuotes: one Bool,   -- must include quotes from source data
  requiresPerItemTable: one Bool,   -- must list every item checked
  requiresPassFail:     one Bool    -- must have a pass/fail status
}

fact ProofOfWorkRules {
  -- Validation step must produce per-item table with pass/fail
  some p: ProofOfWork | p.step = S1_Validate
    and p.requiresSourceQuotes = False
    and p.requiresPerItemTable = True
    and p.requiresPassFail = True

  -- Enrichment audit must include source quotes and per-item coverage
  some p: ProofOfWork | p.step = S2_Enrich
    and p.requiresSourceQuotes = True
    and p.requiresPerItemTable = True
    and p.requiresPassFail = False

  -- Final report must have everything
  some p: ProofOfWork | p.step = S4_Report
    and p.requiresSourceQuotes = True
    and p.requiresPerItemTable = True
    and p.requiresPassFail = True
}
```

This pattern is valuable for AI/LLM pipelines where intermediate verification steps can be gamed by producing plausible-looking but ungrounded reports.

## 34. Scenario Predicates

Split pre/post conditions into separate predicates for clarity:

```alloy
pred BeforeUpgrade[u: User, sub: Sub, p1: Plan] {
  alive[u]
  sub.owner = u
  sub.plan = p1
  sub.status = Active
  sub.obsolete = False
}

pred AfterUpgrade[u: User, sub: Sub, p1: Plan, p2: Plan] {
  p1 != p2
  alive[u]
  sub.owner = u
  sub.plan = p2
  sub.status = Active
  sub.obsolete = False
}

run ShowUpgrade {
  some u: User, sub: Sub, p1, p2: Plan |
    BeforeUpgrade[u, sub, p1] and AfterUpgrade[u, sub, p1, p2]
} for 4 but 1 User, 1 Sub, 2 Plan
```

## 35. Scoping and Cardinality

- `for N` — global atom budget (default for all sigs)
- `for N but 2 User, 1 Plan` — override per sig
- `0 PlatformBSub` — exclude a subtype entirely from a scenario
- `for exactly 2 User` — force precise count (useful in temporal scenarios)
- Start small (`for 4`), increase for confidence (`for 6`, `for 8`)
- Assertions that pass at scope 6 typically hold in practice (small-scope hypothesis)

```alloy
-- Precise control in temporal scenarios
run Scenario {
  ...
} for exactly 1 User, exactly 1 Sub, exactly 1 TxId, 10 steps

-- Flexible scope in static checks
check MyAssertion for 6
```

## 36. Concurrency Modeling

Model concurrent access and duplicate prevention:

```alloy
-- Two concurrent send attempts to the same recipient
sig SendAttempt {
  target:   one Recipient,
  outcome:  one Outcome,
  usesLock: one Bool
}

-- Advisory lock serializes immediate sends
fact AdvisoryLockSerializes {
  all a1, a2: SendAttempt |
    (a1 != a2 and a1.usesLock = True and a2.usesLock = True)
    => a1.target != a2.target
}

-- First delivery closes the gate for subsequent attempts
fact DeliveryClosesGate {
  all a1, a2: SendAttempt |
    (a1 != a2 and a1.outcome = Delivered and a2.target = a1.target)
    => a2.outcome != Delivered
}
```

This pattern models race conditions and mutual exclusion without temporal logic — each `SendAttempt` sig is a concurrent operation snapshot.

## 37. Gap Assertion

Write assertions that are **expected to fail** to demonstrate architectural flaws and prove a fix is needed:

```alloy
-- This assertion INTENTIONALLY fails — proving a race condition exists
-- between immediate and scheduled sends.
assert NoDuplicateDelivery {
  all a1, a2: SendAttempt |
    (a1 != a2 and a1.target = a2.target)
    => not (a1.outcome = Delivered and a2.outcome = Delivered)
}
-- EXPECTED: counterexample found — shows the race condition
check NoDuplicateDelivery for 5

-- Demonstrate the specific gap scenario
run ShowRaceCondition {
  some a1, a2: SendAttempt |
    a1 != a2
    and a1.target = a2.target
    and a1.outcome = Delivered
    and a2.outcome = Delivered
} for 5 but 2 SendAttempt, 1 Recipient
```

Gap assertions are valuable for:
- **Proving to stakeholders** that a bug is real (the counterexample is concrete evidence)
- **Validating a fix** — after fixing, the assertion should pass
- **Documenting known limitations** — "we know this can happen; here's why"

Comment the assertion clearly as intentionally failing so future readers don't treat it as a broken model.

## 38. Resolved Choice (OR-Dependency)

Alloy's `requires` relation is conjunctive — all elements in the set are required. You can't directly express "step needs A **or** B." The workaround: model the OR as a **resolved choice** that picks one option before the step runs, then constrain the requires set conditionally.

```alloy
-- The disjunction: step needs LocalJava OR DockerEngine
-- Model it as a choice that resolves before the step executes

abstract sig RuntimeOption {}
one sig UseLocalJava extends RuntimeOption {}
one sig UseDocker   extends RuntimeOption {}

one sig RuntimeChoice { chosen: one RuntimeOption }

-- S6 requires RunScript always + whichever runtime was chosen
fact S6Dependencies {
  RunScript in S6_Setup.requires
  RuntimeChoice.chosen = UseLocalJava implies S6_Setup.requires = RunScript + LocalJava
  RuntimeChoice.chosen = UseDocker    implies S6_Setup.requires = RunScript + DockerEngine
}

-- Assert: exactly one runtime, never both, never neither
assert ExactlyOneRuntime {
  (RuntimeChoice.chosen = UseLocalJava implies
    (LocalJava in S6_Setup.requires and DockerEngine not in S6_Setup.requires))
  and
  (RuntimeChoice.chosen = UseDocker implies
    (DockerEngine in S6_Setup.requires and LocalJava not in S6_Setup.requires))
}

-- Scenarios: both options are satisfiable
run WithLocalJava { RuntimeChoice.chosen = UseLocalJava } for 5
run WithDocker    { RuntimeChoice.chosen = UseDocker }    for 5
```

This pattern works for any disjunctive dependency:
- **Build tool**: needs Maven OR Gradle
- **Cloud provider**: deploy to AWS OR GCP
- **Auth method**: OAuth OR API key
- **Database**: PostgreSQL OR MySQL
- **Runtime**: local install OR container

The key insight: the OR isn't really "either works at the same time" — it's a **decision that was already made**. The choice sig captures the decision; the conditional facts capture the consequences. The solver then verifies properties for each possible choice independently.

## 39. Ordering Alias for Alloy 6

In Alloy 6, `next` is a temporal keyword (next state). The `util/ordering` module also exports `next` (successor). When a model uses both temporal `var` and `util/ordering`, name clashes can cause subtle bugs. Always alias the import:

```alloy
open util/ordering[Step] as ord

fact StepOrder {
  ord/first = S1_Validate
  ord/next[S1_Validate] = S2_Enrich
  ord/next[S2_Enrich]   = S3_Index
}

-- Use ord/lt instead of bare lt if ambiguity is possible
assert ValidateFirst { ord/first = S1_Validate }
assert EnrichBeforeIndex { ord/lt[S2_Enrich, S3_Index] }
```

This is mandatory in models that combine pipeline ordering with temporal state machines.

## 40. Temporal Invariants

Write standing invariants that must hold in every reachable state, separate from the transition system. This is distinct from facts (which constrain all states including unreachable ones) — temporal invariants are checked against the traces the transition system can actually produce.

```alloy
-- Standing invariants (checked against reachable states only)
assert NoZombieSubs {
  always (all u: DeletedUser | no s: ExistingSub - ObsoleteSub | owner[s] = u)
}

assert MonotonicDeletion {
  always (DeletedUser in DeletedUser')   -- once deleted, always deleted
}

-- Check that the transition system preserves these
check NoZombieSubs for 5 but 8 steps
check MonotonicDeletion for 5 but 8 steps
```

The `always` wrapping makes these temporal assertions. The solver generates all possible traces from `Init` through `Transitions` and checks the property holds at every state in every trace.

## 41. Until and Releases Operators

Alloy 6 provides `until` and `releases` for bounded liveness and conditional safety:

```alloy
-- "A holds until B becomes true" (strong until: B must eventually happen)
assert EventuallyProcessed {
  always (all e: PendingEvent |
    (e in PendingEvent) until (e in ProcessedEvent))
}

-- "B holds unless/until A happens" (weak: A may never happen, B holds forever)
assert SafeUnlessRevoked {
  always (all u: ActiveUser |
    (u in ActiveUser) releases (u not in BannedUser))
}
```

`until` is for liveness: "X is true and stays true until Y becomes true; Y must eventually become true." `releases` is the dual: "Y holds at least until X becomes true; if X never happens, Y holds forever." These are essential for expressing timeout behavior, retry guarantees, and conditional permissions.

## 42. Disj Quantifier

Use `all disj a, b: T | ...` to quantify over all *distinct* pairs. Essential for uniqueness, non-aliasing, and mutual exclusion constraints.

```alloy
-- No two active users share the same email
assert UniqueEmails {
  all disj u1, u2: ActiveUser | u1.email != u2.email
}

-- No two steps produce the same artifact
assert NoSharedProduction {
  all disj s1, s2: Step | no (s1.produces & s2.produces)
}

-- Every pair of concurrent requests accesses different resources
assert NoConflict {
  all disj r1, r2: Request | r1.resource != r2.resource
}
```

`disj` is syntactic sugar for `u1 != u2` but is clearer and avoids the common mistake of forgetting the distinctness guard. Works with any number of variables: `all disj a, b, c: T | ...`.

## 43. Module Parameterization

Build reusable model libraries by parameterizing modules with types:

```alloy
-- In file: cache.als
module cache[Key, Value]

sig CacheEntry {
  key: one Key,
  value: one Value,
  stale: one Bool
}

fact NoDuplicateKeys {
  all disj e1, e2: CacheEntry | e1.key != e2.key
}

pred lookup[k: Key]: one Value {
  some e: CacheEntry | e.key = k and e.stale = False
}
```

```alloy
-- In file: main.als
open cache[Email, User] as userCache
open cache[Token, Session] as sessionCache

-- userCache/CacheEntry and sessionCache/CacheEntry are separate sigs
-- Each has its own NoDuplicateKeys constraint
```

This is how standard library modules (`util/ordering`, `util/relation`) work. Use for any reusable component: caches, queues, state machines, access control matrices.

## 44. Sequences (util/sequniv)

For ordered collections with indexed access, use `seq`:

```alloy
open util/sequniv

sig Pipeline {
  steps: seq Step    -- ordered sequence of steps with indices
}

-- Access by index
fun firstStep[p: Pipeline]: Step { p.steps.first }
fun lastStep[p: Pipeline]: Step { p.steps.last }

-- Sequence length
pred hasAtLeastThreeSteps[p: Pipeline] { #p.steps >= 3 }

-- Order within sequence
assert StepsOrdered {
  all p: Pipeline, i, j: p.steps.inds |
    i < j implies lt[p.steps[i], p.steps[j]]
}
```

`seq T` gives you indexed access (`.first`, `.last`, `.rest`, `[i]`), length (`#`), and ordering. Use instead of linked-list chains (Pattern 14) when you need random access or when the order is the primary structure.

## 45. Inductive Invariant Structure

The canonical method for proving safety properties in temporal models: establish the invariant at init, show each transition preserves it, then assert `always { inv }`.

```alloy
pred safetyInvariant {
  -- The property that must hold in every reachable state
  all u: DeletedUser | no s: ExistingSub - ObsoleteSub | owner[s] = u
}

-- 1. Init establishes the invariant (trivially: no users, no subs)
assert InitEstablishesInvariant {
  safetyInvariant    -- holds in the initial state (no ActiveUser, no ExistingSub)
}

-- 2. Each transition preserves the invariant
-- (this is what the solver actually checks — all traces from Init through Transitions)
assert InvariantPreserved {
  always safetyInvariant
}
check InvariantPreserved for 5 but 10 steps
```

The two-step structure (init + preservation) is the foundation of inductive verification. If you can't prove `always inv` directly, break it into: (a) `inv` holds at init, (b) `inv and transition implies inv'`. This decomposition helps identify which specific transition breaks the invariant.

## 46. Expect Annotations

Document expected results directly in `run` and `check` commands:

```alloy
-- This scenario SHOULD be satisfiable (expect an instance)
run HappyPath { ... } for 5 expect 1

-- This scenario SHOULD be unsatisfiable (no valid configuration exists)
run ImpossibleState { ... } for 5 expect 0

-- This assertion SHOULD hold (no counterexample expected)
check SafetyProperty for 6 expect 0

-- This assertion SHOULD fail (counterexample expected — gap assertion)
check KnownBug for 6 expect 1
```

`expect 0` = no instance/counterexample expected. `expect 1` = at least one expected. The Alloy Analyzer reports whether the expectation was met, making it easy to detect when a model change breaks something that previously worked (or "fixes" a gap assertion that should still fail).

## 47. Equivalence Classes (Range Partitioning)

When a system's behavior depends on where a value falls within ranges (price tiers, rate limits,
SLA levels, age brackets), replace the continuous domain with discrete equivalence classes.
Each class represents a range that triggers the same business rules — the exact value inside
the range doesn't matter for verification, only which class it belongs to.

This avoids Alloy's Int limitations (4-bit default = -8..7) while still verifying all
boundary-crossing behavior. The solver explores every combination of classes exhaustively.

```alloy
-- Instead of: amount: one Int (limited, overflow-prone)
-- Use equivalence classes that partition the domain:

abstract sig AmountClass {}
one sig UnderThreshold extends AmountClass {}   -- e.g. < $1,000
one sig MidRange       extends AmountClass {}   -- $1,000 – $10,000
one sig OverThreshold  extends AmountClass {}   -- > $10,000

sig Invoice {
  amount: one AmountClass,
  status: one InvoiceStatus,
  approvedBy: set Role
}

-- Different rules per class:
fact ApprovalThresholds {
  all i: Invoice | i.status = Approved implies {
    -- Under threshold: any reviewer suffices
    i.amount = UnderThreshold implies some i.approvedBy & Reviewer
    -- Mid range: reviewer or admin
    i.amount = MidRange implies some i.approvedBy & (Reviewer + Admin)
    -- Over threshold: dual approval required
    i.amount = OverThreshold implies
      (some i.approvedBy & Reviewer and some i.approvedBy & Finance)
  }
}

-- The key assertion: over-threshold invoices can't slip through with single approval
assert DualApprovalForLargeInvoices {
  all i: Invoice | i.amount = OverThreshold and i.status = Approved implies
    #i.approvedBy >= 2
}
check DualApprovalForLargeInvoices for 5
```

**When to use equivalence classes instead of Int:**
- The rules differ by range, not by exact value (tier-based pricing, SLA levels)
- You need exhaustive verification of all class combinations (the solver checks every pairing)
- The domain has well-defined boundaries that map to different behavior

**When Int is still better:**
- You need arithmetic (accumulation, counters, differences)
- The exact value matters (retry count = 3, not "retry count is in the high range")
- The domain is small enough to fit Alloy's Int bitwidth (see pattern 7)

**Combining with ordered enum (pattern 15):** If you also need comparison between classes
(e.g., "this class is higher than that one"), add a `higher` chain. But often the classes
are simply different behaviors, not a linear ordering — in that case, plain abstract sig
with one sig extends is cleaner.

**Boundary testing:** The solver automatically explores all class assignments. If you have
3 classes and 2 invoices, it checks 3² = 9 combinations — including the interesting ones
like "one invoice under threshold, one over" that manual testing might miss.

## 48. Compositional Verification (Interface States)

Split a sequential model into independently verifiable segments joined by **interface predicates** — predicates that characterize equivalence classes of states at cut points. Each segment proves it delivers states satisfying the next interface; each downstream segment proves its properties from any state satisfying its input interface. The full model remains available for end-to-end verification when needed.

This is assume-guarantee reasoning applied to Alloy: the interface predicate is simultaneously the postcondition of one segment and the precondition of the next.

```alloy
-- ================================================================
-- A pipeline has phases: Prepare → Execute → Deliver.
-- End-to-end scope explodes. Split at two interfaces.
-- ================================================================

open util/ordering[Step]

abstract sig Step {}
one sig S1, S2, S3, S4, S5, S6 extends Step {}

abstract sig Artifact { produced: one Step }
one sig Prompt, Model, Review extends Artifact {}      -- Prepare phase
one sig Tooling, Output, Formatted extends Artifact {} -- Execute phase
one sig Interp, Report extends Artifact {}             -- Deliver phase

-- Full model facts (step order, productions, dependencies) omitted for brevity.
-- The key addition is the interface predicates:

-- ================================================================
-- INTERFACE PREDICATES
--
-- Define observable properties at cut points.
-- "Observable" = defined over artifacts and their state,
-- NOT over which path was taken to get here.
-- ================================================================

pred PrepareComplete {
  -- Model exists and meets quality gate
  some Model
  Model.produced in S1 + S2 + S3
  some Review
}

pred ExecuteComplete {
  -- Run output exists and was produced after the model
  PrepareComplete
  some Output
  some Formatted
  lt[Model.produced, Output.produced]
}

-- ================================================================
-- SEGMENT CHECKS (fast, independent)
--
-- Each segment proves: given input interface, output interface holds.
-- These run in seconds because scope is limited to one phase.
-- ================================================================

-- Segment 1: init → PrepareComplete
assert Seg1_PrepareDelivers {
  -- If steps S1-S3 ran with valid inputs, PrepareComplete holds
  (some Prompt and Prompt.produced = S1 and Model.produced = S3)
    implies PrepareComplete
}
check Seg1_PrepareDelivers for 4

-- Segment 2: PrepareComplete → ExecuteComplete
assert Seg2_ExecuteDelivers {
  -- If PrepareComplete and execution steps ran, ExecuteComplete holds
  (PrepareComplete and Output.produced = S4 and Formatted.produced = S5)
    implies ExecuteComplete
}
check Seg2_ExecuteDelivers for 4

-- Segment 3: ExecuteComplete → final properties
assert Seg3_DeliverComplete {
  -- If ExecuteComplete and deliver steps ran, report is traceable
  (ExecuteComplete and some Report and Report.produced = S6)
    implies (some Interp and lt[Formatted.produced, Report.produced])
}
check Seg3_DeliverComplete for 4

-- ================================================================
-- END-TO-END CHECK (slow, full confidence)
--
-- Ignores interfaces — lets solver explore entire state space.
-- If this passes, the interfaces are consistent.
-- If segments pass but this fails, an interface is too weak.
-- ================================================================

assert EndToEnd {
  (some Prompt and Prompt.produced = S1 and some Report)
    implies lt[Model.produced, Report.produced]
}
check EndToEnd for 6   -- needs higher scope than segments

-- ================================================================
-- INTERFACE CONSISTENCY (diagnostic)
--
-- Verify interfaces are satisfiable — not vacuously true.
-- A run that finds no instance means the interface is too strong.
-- ================================================================

run PrepareReachable { PrepareComplete } for 4
run ExecuteReachable { ExecuteComplete } for 4

-- ================================================================
-- COMPOSABILITY CHECK
--
-- Verify that the output of segment N is sufficient input for segment N+1.
-- If this fails, the interface predicate admits states that break downstream.
-- ================================================================

assert InterfaceComposes {
  -- Any state satisfying PrepareComplete can reach ExecuteComplete
  -- (i.e., the interface doesn't accidentally admit unreachable states)
  PrepareComplete implies (some Output.produced)
}
check InterfaceComposes for 5
```

**When to use compositional verification:**
- Model has >3 sequential phases and end-to-end scope causes solver timeout
- Different teams own different phases and need to verify independently
- System has natural handoff points (queues, APIs, approval gates, phase transitions)
- You want fast feedback during development (segment checks in seconds) with full confidence on demand (end-to-end check in minutes)

**How to pick cut points:**
- Look for **natural phase boundaries** where observable state is well-defined (e.g., "model exists and passed review" between writing and running)
- Interface predicates should capture **what is true**, not **how it became true** — no path history, no step references beyond production ordering
- Start with 2 interfaces (3 segments). Add more only if a segment still blows up

**Tradeoffs:**
- **Too-weak interface:** admits states the real system can't reach → downstream segments find spurious counterexamples. Fix: strengthen the predicate with additional invariants.
- **Too-strong interface:** encodes path history → you haven't actually decomposed anything, and the interface `run` may be UNSAT. Fix: remove conditions that reference specific steps or intermediate state.
- **Sweet spot:** interface predicates that capture invariants holding at that point, like function signatures — caller guarantees preconditions, callee guarantees postconditions, neither cares about internals.

**Relationship to other patterns:**
- Combines with [Scenario Predicates (#34)](#34-scenario-predicates) — interface predicates are a special case of before/after predicates applied at phase boundaries
- Combines with [Pipeline DAG (#30)](#30-pipeline-dag) — the DAG defines step ordering; interfaces define observable state at cut points within the DAG
- Combines with [Proof of Work (#33)](#33-proof-of-work) — interface predicates can require proof artifacts (e.g., "review exists" as evidence that quality gate passed)
