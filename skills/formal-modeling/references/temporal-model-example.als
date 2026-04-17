/**
 * Alloy 6 temporal model for SaaS subscription lifecycle (generic example).
 *
 * Follows the Alloy 6 / Electrum pattern:
 *   fact Init        — initial state
 *   fact Transitions — valid moves at every step
 *   run / check      — temporal goals
 *
 * Two payment platforms with different semantics:
 *   PlatformA — identifier is durable (reused across renewals).
 *               Expired subs: Active → Inactive (one-way).
 *   PlatformB — identifier is per-purchase (new ID each cycle).
 *               Canceled subs can be reactivated: Active → Canceled → Active.
 *
 * Modelled transitions:
 *   T1 register[u]                  — new app account
 *   T2 platformASubscribe[u,s,id]   — PlatformA purchase → Active
 *   T3 platformAExpired[s]          — PlatformA expired → Inactive
 *   T4 platformBSubscribe[u,s,id]   — PlatformB purchase → Active
 *   T5 platformBCanceled[s]         — PlatformB canceled → Canceled
 *   T6 platformBReactivated[s]      — PlatformB reactivated → Active
 *   T7 softDelete[u]               — account deletion → Disabled + obsolete
 *
 * Scenarios:
 *   FullLifecycle          — register → subscribe → expire
 *   CancelReactivateCycle  — subscribe → cancel → reactivate
 *   AccountDeletion        — register → subscribe → delete
 */

-- ============================================================
-- Eternal atoms (fixed universe)
-- ============================================================

sig PlatformAId {}   -- durable identifier (reused across renewals)
sig PlatformBId {}   -- per-purchase identifier

abstract sig SubStatus {}
one sig Active, Inactive, Canceled, Disabled extends SubStatus {}

-- ============================================================
-- User accounts
--   Non-var sig  → fixed universe; quantifiers always work.
--   var sets     → track lifecycle state at each step.
-- ============================================================

sig User {}

var sig ActiveUser  in User {}   -- registered and alive
var sig DeletedUser in User {}   -- soft-deleted

-- ============================================================
-- Subscriptions
-- ============================================================

abstract sig Sub {
  var owner  : lone User,       -- mutable: who owns this row
  var status : lone SubStatus   -- mutable: current status
}
sig PlatformASub extends Sub {
  platformA_id: one PlatformAId   -- immutable: platform identifier
}
sig PlatformBSub extends Sub {
  platformB_id: one PlatformBId   -- immutable: platform identifier
}

var sig ExistingSub in Sub {}    -- rows that exist in DB
var sig ObsoleteSub in Sub {}    -- rows marked obsolete

-- ============================================================
-- Structural invariants (hold in every state)
-- ============================================================

fact Structure {
  -- Users: active and deleted are disjoint
  always no ActiveUser & DeletedUser
  -- Once deleted, always deleted (soft-delete is permanent)
  always DeletedUser in DeletedUser'
  -- Rows never vanish once created
  always ExistingSub in ExistingSub'
  -- Obsolete is monotonic (once set, never cleared)
  always ObsoleteSub in ObsoleteSub'
  -- Each existing sub has exactly one owner and one status
  always all s: ExistingSub | one s.owner and one s.status
  -- Non-existing subs have no owner/status
  always all s: Sub - ExistingSub | no s.owner and no s.status
}

-- ============================================================
-- Initial state
-- ============================================================

fact Init {
  no ActiveUser
  no DeletedUser
  no ExistingSub
  no ObsoleteSub
  all s: Sub | no s.owner and no s.status
}

-- ============================================================
-- Frame condition helpers (compose into stutter)
-- ============================================================

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

pred stutter {
  frameUsers
  frameSubs
}

-- ============================================================
-- Transitions
-- ============================================================

pred register[u: User] {
  -- guard: not yet in system
  u not in ActiveUser + DeletedUser
  -- effect
  ActiveUser'  = ActiveUser + u
  DeletedUser' = DeletedUser
  frameSubs
}

pred platformASubscribe[u: User, s: PlatformASub, id: PlatformAId] {
  -- guard
  u in ActiveUser
  s not in ExistingSub
  s.platformA_id = id
  -- guard: no live row for this ID
  no s2: (ExistingSub & PlatformASub) - ObsoleteSub | s2.platformA_id = id
  -- effect
  ExistingSub' = ExistingSub + s
  ObsoleteSub' = ObsoleteSub
  owner'  = owner  ++ (s -> u)
  status' = status ++ (s -> Active)
  frameUsers
}

pred platformAExpired[s: PlatformASub] {
  -- guard: live and active
  s in ExistingSub - ObsoleteSub
  status[s] = Active
  -- effect: mark inactive
  status' = status ++ (s -> Inactive)
  owner'  = owner
  ExistingSub' = ExistingSub
  ObsoleteSub' = ObsoleteSub
  frameUsers
}

pred platformBSubscribe[u: User, s: PlatformBSub, id: PlatformBId] {
  u in ActiveUser
  s not in ExistingSub
  s.platformB_id = id
  no s2: (ExistingSub & PlatformBSub) - ObsoleteSub | s2.platformB_id = id

  ExistingSub' = ExistingSub + s
  ObsoleteSub' = ObsoleteSub
  owner'  = owner  ++ (s -> u)
  status' = status ++ (s -> Active)
  frameUsers
}

pred platformBCanceled[s: PlatformBSub] {
  s in ExistingSub - ObsoleteSub
  status[s] = Active
  status' = status ++ (s -> Canceled)
  owner'  = owner
  ExistingSub' = ExistingSub
  ObsoleteSub' = ObsoleteSub
  frameUsers
}

pred platformBReactivated[s: PlatformBSub] {
  s in ExistingSub - ObsoleteSub
  status[s] = Canceled
  status' = status ++ (s -> Active)
  owner'  = owner
  ExistingSub' = ExistingSub
  ObsoleteSub' = ObsoleteSub
  frameUsers
}

pred softDelete[u: User] {
  u in ActiveUser
  ActiveUser'  = ActiveUser - u
  DeletedUser' = DeletedUser + u
  -- mark all user's live subs as obsolete + disabled
  let userSubs = { s: ExistingSub - ObsoleteSub | owner[s] = u } |
    ObsoleteSub' = ObsoleteSub + userSubs and
    status' = status ++ { s: userSubs, st: SubStatus | st = Disabled } and
    owner'  = owner and
    ExistingSub' = ExistingSub
}

-- ============================================================
-- Transition system
-- ============================================================

fact Transitions {
  always (
    stutter
    or (some u: User | register[u])
    or (some u: User, s: PlatformASub, id: PlatformAId | platformASubscribe[u, s, id])
    or (some s: PlatformASub | platformAExpired[s])
    or (some u: User, s: PlatformBSub, id: PlatformBId | platformBSubscribe[u, s, id])
    or (some s: PlatformBSub | platformBCanceled[s])
    or (some s: PlatformBSub | platformBReactivated[s])
    or (some u: User | softDelete[u])
  )
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- At most one live PlatformA sub per identifier
assert PlatformADedupAlwaysHolds {
  always all id: PlatformAId |
    lone s: (ExistingSub & PlatformASub) - ObsoleteSub | s.platformA_id = id
}
check PlatformADedupAlwaysHolds for 4

-- A deleted user never owns a live subscription
assert DeletedUserHasNoLiveSub {
  always all u: DeletedUser |
    no s: ExistingSub - ObsoleteSub | owner[s] = u
}
check DeletedUserHasNoLiveSub for 4

-- ============================================================
-- Scenarios
-- ============================================================

-- Full lifecycle: register → subscribe → expire
run FullLifecycle {
  some u: User, s: PlatformASub, id: PlatformAId |
    s.platformA_id = id
    and
    eventually (u in ActiveUser and no ExistingSub
    and
    eventually (s in ExistingSub and status[s] = Active and owner[s] = u
    and
    eventually (status[s] = Inactive)))
} for exactly 1 User, exactly 1 PlatformASub, exactly 1 PlatformAId,
      0 PlatformBSub, 0 PlatformBId, 8 steps

-- Cancel/reactivate cycle: subscribe → cancel → reactivate
run CancelReactivateCycle {
  some u: User, s: PlatformBSub |
    eventually (status[s] = Active
    and eventually (status[s] = Canceled
    and eventually (status[s] = Active)))
} for exactly 1 User, exactly 1 PlatformBSub, exactly 1 PlatformBId,
      0 PlatformASub, 0 PlatformAId, 8 steps

-- Account deletion: register → subscribe → delete (sub becomes obsolete)
run AccountDeletion {
  some u: User, s: PlatformASub |
    eventually (u in ActiveUser and s in ExistingSub and status[s] = Active
    and
    eventually (u in DeletedUser and s in ObsoleteSub and status[s] = Disabled))
} for exactly 1 User, exactly 1 PlatformASub, exactly 1 PlatformAId,
      0 PlatformBSub, 0 PlatformBId, 8 steps
