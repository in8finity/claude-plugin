/**
 * Alloy model for SaaS subscription payment states (generic example).
 *
 * Entities:
 *   User         — application account (soft-deletable)
 *   Plan         — subscription plan (monthly, annual, etc.)
 *   Subscription — user-plan join record; one per platform subscription ID
 *
 * Two payment platforms are supported (columns are mutually exclusive per row):
 *   PlatformA — identifier is durable (reused across renewals)
 *   PlatformB — identifier is per-purchase (new ID each cycle)
 *
 * Key DB invariant: partial unique index
 *   UNIQUE (platform_id) WHERE is_obsolete = false
 * ensures at most ONE live subscription record per store-side identifier.
 *
 * Scenarios modelled:
 *   - A user with an active subscription upgrades to a different plan
 *   - A user cancels and the subscription becomes inactive
 *   - One platform per user at a time
 */

module SubscriptionStates

-- ============================================================
-- Bool helper
-- ============================================================

abstract sig Bool {}
one sig True, False extends Bool {}

-- ============================================================
-- Plan (subscription plan)
-- ============================================================

sig Plan {
  published: one Bool
}

-- ============================================================
-- User (soft-deletable application account)
-- ============================================================

sig User {
  deleted: one Bool
}

pred alive[u: User]       { u.deleted = False }
pred softDeleted[u: User] { u.deleted = True  }

-- ============================================================
-- Platform subscription identifiers
-- ============================================================

sig PlatformAId {}   -- durable identifier (reused across renewals)
sig PlatformBId {}   -- per-purchase identifier

-- ============================================================
-- Subscription status
-- ============================================================

abstract sig SubStatus {}

one sig SubPending  extends SubStatus {}  -- created, awaiting payment confirmation
one sig SubActive   extends SubStatus {}  -- active and within billing period
one sig SubInactive extends SubStatus {}  -- expired
one sig SubCanceled extends SubStatus {}  -- auto-renew off / revoked
one sig SubDisabled extends SubStatus {}  -- row superseded by soft-delete

-- ============================================================
-- Subscription record
--
-- Exactly one of the two platform FKs is non-null per row,
-- modelled as two disjoint subtypes.
-- ============================================================

abstract sig Subscription {
  owner   : one User,
  plan    : one Plan,
  status  : one SubStatus,
  obsolete: one Bool
}

sig PlatformASub extends Subscription {
  platformA_id: one PlatformAId
}

sig PlatformBSub extends Subscription {
  platformB_id: one PlatformBId
}

-- ============================================================
-- System invariants
-- ============================================================

-- I1. At most one non-obsolete record per PlatformA identifier.
--     Mirrors: UNIQUE INDEX WHERE is_obsolete = false.
fact PlatformAUnique {
  all id: PlatformAId |
    lone s: PlatformASub | s.platformA_id = id and s.obsolete = False
}

-- I2. At most one non-obsolete record per PlatformB identifier.
fact PlatformBUnique {
  all id: PlatformBId |
    lone s: PlatformBSub | s.platformB_id = id and s.obsolete = False
}

-- I3. A soft-deleted user has no live (non-obsolete) subscriptions.
fact NoLiveSubForDeletedUser {
  all u: User | softDeleted[u] =>
    no s: Subscription | s.owner = u and s.obsolete = False
}

-- I4. Active, inactive, or canceled subscriptions must be non-obsolete.
fact LiveStatusImpliesLive {
  all s: Subscription |
    (s.status = SubActive or s.status = SubInactive or s.status = SubCanceled)
      => s.obsolete = False
}

-- I5. Only published plans may have active subscriptions.
fact ActiveSubRequiresPublishedPlan {
  all s: Subscription |
    s.status = SubActive => s.plan.published = True
}

-- I6. A user has at most one live subscription platform.
fact OneActivePlatformPerUser {
  all u: User |
    let liveSubs = { s: Subscription | s.owner = u and s.obsolete = False } |
      no liveSubs & PlatformASub or no liveSubs & PlatformBSub
}

-- ============================================================
-- Scenario predicates: plan upgrade
-- ============================================================

-- BEFORE: user has an active subscription on plan p1
pred BeforeUpgrade[u: User, sub: Subscription, p1: Plan] {
  alive[u]
  sub.owner    = u
  sub.plan     = p1
  sub.status   = SubActive
  sub.obsolete = False
  p1.published = True
}

-- AFTER: same subscription row now points to plan p2
pred AfterUpgrade[u: User, sub: Subscription, p1: Plan, p2: Plan] {
  p1 != p2
  alive[u]
  sub.owner    = u
  sub.plan     = p2
  sub.status   = SubActive
  sub.obsolete = False
  p2.published = True
}

-- ============================================================
-- Assertions
-- ============================================================

-- A1. A soft-deleted user is never the owner of a live subscription.
assert SoftDeletedUserHasNoLiveSub {
  no u: User, s: Subscription |
    softDeleted[u] and s.owner = u and s.obsolete = False
}
check SoftDeletedUserHasNoLiveSub for 6

-- A2. An obsolete record cannot have an active status.
assert ObsoleteIsNeverLive {
  no s: Subscription | s.obsolete = True and
    (s.status = SubActive or s.status = SubInactive or s.status = SubCanceled)
}
check ObsoleteIsNeverLive for 6

-- A3. After upgrade, the user still has exactly one live subscription.
assert UpgradePreservesUniqueness {
  all u: User, sub: Subscription, p1, p2: Plan |
    (BeforeUpgrade[u, sub, p1] and AfterUpgrade[u, sub, p1, p2])
    =>
    one s: Subscription | s.owner = u and s.obsolete = False
}
check UpgradePreservesUniqueness for 6

-- ============================================================
-- Run commands
-- ============================================================

-- Show a user upgrading from one plan to another.
run ShowPlanUpgrade {
  some u: User, sub: PlatformASub, p1, p2: Plan |
    AfterUpgrade[u, sub, p1, p2]
} for 4 but
    1 User, 2 Plan,
    1 PlatformASub, 0 PlatformBSub,
    1 PlatformAId, 0 PlatformBId

-- Show a canceled subscription (inactive status).
run ShowCancellation {
  some u: User, sub: PlatformASub |
    alive[u]
    and sub.owner = u and sub.obsolete = False and sub.status = SubInactive
} for 4 but
    1 User, 1 Plan,
    1 PlatformASub, 0 PlatformBSub,
    1 PlatformAId, 0 PlatformBId

-- Show single-platform user (I6 forbids multi-platform).
run ShowSinglePlatformUser {
  some u: User, sub: PlatformASub |
    alive[u]
    and sub.owner = u and sub.obsolete = False and sub.status = SubActive
} for 4 but
    1 User, 1 Plan,
    1 PlatformASub, 0 PlatformBSub,
    1 PlatformAId, 0 PlatformBId
