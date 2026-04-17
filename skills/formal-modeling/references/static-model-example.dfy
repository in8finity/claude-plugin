/**
 * SaaS Subscription Payment States — Dafny port
 *
 * Ported from references/static-model-example.als.
 *
 * Entities: User, Plan, Subscription (PlatformA / PlatformB variants)
 * Invariants: partial unique index, soft-delete cascade, platform exclusion
 */

// ============================================================
// Enums and basic types
// ============================================================

datatype SubStatus = SubPending | SubActive | SubInactive | SubCanceled | SubDisabled

type UserId = nat
type PlanId = nat
type PlatformAId = nat
type PlatformBId = nat

datatype Platform = PlatformA(aId: PlatformAId) | PlatformB(bId: PlatformBId)

datatype User = User(id: UserId, deleted: bool)
datatype Plan = Plan(id: PlanId, published: bool)

datatype Subscription = Subscription(
  owner: UserId,
  plan: PlanId,
  status: SubStatus,
  obsolete: bool,
  platform: Platform
)

predicate alive(u: User) { !u.deleted }
predicate softDeleted(u: User) { u.deleted }

// ============================================================
// System state: a collection of users, plans, subscriptions
// ============================================================

datatype SystemState = SystemState(
  users: seq<User>,
  plans: seq<Plan>,
  subs: seq<Subscription>
)

// Helper: find user by ID
predicate userExists(st: SystemState, uid: UserId)
{
  exists i :: 0 <= i < |st.users| && st.users[i].id == uid
}

predicate userDeleted(st: SystemState, uid: UserId)
{
  exists i :: 0 <= i < |st.users| && st.users[i].id == uid && st.users[i].deleted
}

predicate planPublished(st: SystemState, pid: PlanId)
{
  exists i :: 0 <= i < |st.plans| && st.plans[i].id == pid && st.plans[i].published
}

// ============================================================
// Invariants as predicates
// ============================================================

// I1: At most one non-obsolete record per PlatformA identifier
predicate PlatformAUnique(st: SystemState)
{
  forall i, j :: 0 <= i < |st.subs| && 0 <= j < |st.subs| && i != j ==>
    (st.subs[i].platform.PlatformA? && st.subs[j].platform.PlatformA? &&
     st.subs[i].platform.aId == st.subs[j].platform.aId &&
     !st.subs[i].obsolete && !st.subs[j].obsolete) ==> false
}

// I2: At most one non-obsolete record per PlatformB identifier
predicate PlatformBUnique(st: SystemState)
{
  forall i, j :: 0 <= i < |st.subs| && 0 <= j < |st.subs| && i != j ==>
    (st.subs[i].platform.PlatformB? && st.subs[j].platform.PlatformB? &&
     st.subs[i].platform.bId == st.subs[j].platform.bId &&
     !st.subs[i].obsolete && !st.subs[j].obsolete) ==> false
}

// I3: Deleted user has no live subscriptions
predicate NoLiveSubForDeletedUser(st: SystemState)
{
  forall i :: 0 <= i < |st.subs| && !st.subs[i].obsolete ==>
    !userDeleted(st, st.subs[i].owner)
}

// I4: Active/inactive/canceled subs must be non-obsolete
predicate LiveStatusImpliesLive(st: SystemState)
{
  forall i :: 0 <= i < |st.subs| ==>
    (st.subs[i].status == SubActive ||
     st.subs[i].status == SubInactive ||
     st.subs[i].status == SubCanceled) ==> !st.subs[i].obsolete
}

// I5: Active subs require published plans
predicate ActiveSubRequiresPublishedPlan(st: SystemState)
{
  forall i :: 0 <= i < |st.subs| ==>
    st.subs[i].status == SubActive ==> planPublished(st, st.subs[i].plan)
}

// All invariants hold
predicate ValidState(st: SystemState)
{
  PlatformAUnique(st) &&
  PlatformBUnique(st) &&
  NoLiveSubForDeletedUser(st) &&
  LiveStatusImpliesLive(st) &&
  ActiveSubRequiresPublishedPlan(st)
}

// ============================================================
// Assertions as lemmas
// ============================================================

// A1: Soft-deleted user never owns a live subscription
lemma SoftDeletedUserHasNoLiveSub(st: SystemState, subIdx: int)
  requires ValidState(st)
  requires 0 <= subIdx < |st.subs|
  requires !st.subs[subIdx].obsolete
  ensures !userDeleted(st, st.subs[subIdx].owner)
{
  // Follows from NoLiveSubForDeletedUser invariant
}

// A2: Obsolete record cannot have active status
lemma ObsoleteIsNeverLive(st: SystemState, subIdx: int)
  requires ValidState(st)
  requires 0 <= subIdx < |st.subs|
  requires st.subs[subIdx].obsolete
  ensures st.subs[subIdx].status != SubActive
  ensures st.subs[subIdx].status != SubInactive
  ensures st.subs[subIdx].status != SubCanceled
{
  // Follows from LiveStatusImpliesLive: contrapositive
}

// ============================================================
// Scenario: plan upgrade preserves uniqueness (witness construction)
// ============================================================

lemma UpgradePreservesUniqueness()
  ensures exists st ::
    ValidState(st) &&
    |st.subs| == 1 &&
    st.subs[0].status == SubActive &&
    !st.subs[0].obsolete
{
  var u := User(0, false);
  var p := Plan(0, true);
  var s := Subscription(0, 0, SubActive, false, PlatformA(0));
  var st := SystemState([u], [p], [s]);
  // Help Z3 with the existential in planPublished
  assert st.plans[0].id == 0 && st.plans[0].published;
  assert planPublished(st, 0);
  assert ValidState(st);
}
