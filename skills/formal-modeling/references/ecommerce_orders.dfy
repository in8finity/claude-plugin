/**
 * E-commerce Order State Machine — Dafny port
 *
 * Ported from ecommerce_orders.als (Alloy 6 static model).
 *
 * Key difference from Alloy:
 *   - Alloy checks properties within bounded scope (e.g., "for 5 orders")
 *   - Dafny PROVES properties for ALL possible inputs (unbounded)
 *   - Dafny generates executable code; Alloy generates counterexamples
 *   - Dafny verification is SMT-based (Z3); Alloy is SAT-based
 *
 * What translates well:
 *   - Enum states → Dafny datatype
 *   - Facts → function preconditions / lemma postconditions
 *   - Assertions → lemmas that Dafny proves automatically
 *   - Valid transitions → predicate on (from, to) pairs
 *
 * What doesn't translate:
 *   - `run` scenarios (Alloy finds concrete instances; Dafny proves universals)
 *   - Relational algebra (Alloy's core; Dafny is imperative)
 *   - Bounded exploration (Alloy's "for 5" has no Dafny equivalent)
 */

// ============================================================
// Order states
// ============================================================

datatype OrderStatus =
  | Created
  | PaymentPending
  | Paid
  | Shipped
  | Delivered
  | Cancelled
  | Refunded

// ============================================================
// Valid transitions
// ============================================================

predicate ValidTransition(from: OrderStatus, to: OrderStatus)
{
  match (from, to) {
    case (Created, PaymentPending) => true
    case (PaymentPending, Paid)    => true
    case (Paid, Shipped)           => true
    case (Shipped, Delivered)      => true
    case (Created, Cancelled)      => true
    case (PaymentPending, Cancelled) => true
    case (Paid, Cancelled)         => true
    case (Paid, Refunded)          => true
    case _ => false
  }
}

// ============================================================
// Order with transition history
// ============================================================

datatype Order = Order(status: OrderStatus, previousStatus: OrderStatus)

predicate ValidOrder(o: Order)
{
  // Non-initial states must have a valid predecessor
  (o.status == Created || ValidTransition(o.previousStatus, o.status))
}

// ============================================================
// Business rule predicates
// ============================================================

// Rule 1: Cancelled orders were never shipped
predicate CancelledNeverShipped(o: Order)
  requires ValidOrder(o)
{
  o.status == Cancelled ==> o.previousStatus != Shipped
}

// Rule 2: Refunded orders must have been paid
predicate RefundRequiresPaid(o: Order)
  requires ValidOrder(o)
{
  o.status == Refunded ==> o.previousStatus == Paid
}

// Rule 3: Can only cancel before shipping
predicate CancelBeforeShipping(o: Order)
  requires ValidOrder(o)
{
  o.status == Cancelled ==>
    (o.previousStatus == Created ||
     o.previousStatus == PaymentPending ||
     o.previousStatus == Paid)
}

// ============================================================
// Assertions as lemmas — Dafny proves these for ALL orders
// ============================================================

// A1: No valid order is both cancelled and shipped
// (In Alloy: check NoCancelledShipment for 5)
// (In Dafny: proved for ALL orders, not just scope 5)
lemma NoCancelledShipment(o: Order)
  requires ValidOrder(o)
  ensures o.status == Shipped ==> o.previousStatus != Cancelled
{
  // Dafny proves this automatically from ValidTransition:
  // Shipped can only come from Paid, and Cancelled is not Paid.
}

// A2: Every refunded order was paid
lemma RefundImpliesPaid(o: Order)
  requires ValidOrder(o)
  ensures o.status == Refunded ==> o.previousStatus == Paid
{
  // Automatic from ValidTransition: only Paid -> Refunded exists.
}

// A3: Cancelled orders only come from pre-shipping states
lemma CancelOnlyBeforeShip(o: Order)
  requires ValidOrder(o)
  ensures o.status == Cancelled ==>
    (o.previousStatus == Created ||
     o.previousStatus == PaymentPending ||
     o.previousStatus == Paid)
{
  // Automatic from ValidTransition enumeration.
}

// A4: Delivered orders must have been shipped
lemma DeliveryRequiresShipping(o: Order)
  requires ValidOrder(o)
  ensures o.status == Delivered ==> o.previousStatus == Shipped
{
  // Automatic: only Shipped -> Delivered exists.
}

// A5: No direct jump from Created to Shipped
lemma NoDirectShip(o: Order)
  requires ValidOrder(o)
  ensures !(o.status == Shipped && o.previousStatus == Created)
{
  // Automatic: Created -> Shipped is not in ValidTransition.
}

// ============================================================
// Executable transition function (Dafny bonus — Alloy can't do this)
// ============================================================

// Unlike Alloy, Dafny can produce verified EXECUTABLE code.
// This function transitions an order and PROVES the result is valid.

method TransitionOrder(current: OrderStatus, target: OrderStatus)
  returns (result: Order)
  requires ValidTransition(current, target)
  ensures ValidOrder(result)
  ensures result.status == target
  ensures result.previousStatus == current
{
  result := Order(target, current);
}

// Full order lifecycle — verified executable
method ProcessOrder() returns (finalOrder: Order)
  ensures ValidOrder(finalOrder)
  ensures finalOrder.status == Delivered
{
  var o1 := TransitionOrder(Created, PaymentPending);
  var o2 := TransitionOrder(PaymentPending, Paid);
  var o3 := TransitionOrder(Paid, Shipped);
  var o4 := TransitionOrder(Shipped, Delivered);
  finalOrder := o4;
}

// Cancel flow — verified executable
method CancelOrder(fromStatus: OrderStatus) returns (result: Order)
  requires fromStatus == Created || fromStatus == PaymentPending || fromStatus == Paid
  ensures ValidOrder(result)
  ensures result.status == Cancelled
{
  result := TransitionOrder(fromStatus, Cancelled);
}

// Refund flow — verified executable
method RefundOrder() returns (result: Order)
  ensures ValidOrder(result)
  ensures result.status == Refunded
  ensures result.previousStatus == Paid
{
  result := TransitionOrder(Paid, Refunded);
}

// ============================================================
// Multi-step trace verification (closest to Alloy's temporal)
// ============================================================

// Verify that a sequence of transitions is valid
predicate ValidTrace(trace: seq<OrderStatus>)
{
  |trace| >= 1 &&
  forall i :: 0 <= i < |trace| - 1 ==> ValidTransition(trace[i], trace[i+1])
}

// Prove: any valid trace ending in Delivered must pass through Shipped
lemma DeliveredImpliesShippedInTrace(trace: seq<OrderStatus>)
  requires ValidTrace(trace)
  requires |trace| >= 2
  requires trace[|trace|-1] == Delivered
  ensures trace[|trace|-2] == Shipped
{
  // The last transition must be Shipped -> Delivered (only valid predecessor)
  var i := |trace| - 2;
  assert ValidTransition(trace[i], trace[i+1]);
}

// Prove: any valid trace ending in Refunded must pass through Paid
lemma RefundedImpliesPaidInTrace(trace: seq<OrderStatus>)
  requires ValidTrace(trace)
  requires |trace| >= 2
  requires trace[|trace|-1] == Refunded
  ensures trace[|trace|-2] == Paid
{
  var i := |trace| - 2;
  assert ValidTransition(trace[i], trace[i+1]);
}

// Prove: Cancelled can never appear before Shipped in a valid trace
// (stronger than Alloy's single-step check — this covers the full history)
lemma CancelledBlocksShipping(trace: seq<OrderStatus>)
  requires ValidTrace(trace)
  requires exists i :: 0 <= i < |trace| && trace[i] == Cancelled
  ensures forall j :: 0 <= j < |trace| ==>
    (trace[j] == Cancelled ==>
      forall k :: j < k < |trace| ==> trace[k] != Shipped)
{
  // Once Cancelled, no valid transition leads to any state
  // (Cancelled is terminal — it has no outgoing transitions)
  forall i | 0 <= i < |trace| && trace[i] == Cancelled
    ensures forall k :: i < k < |trace| ==> trace[k] != Shipped
  {
    if i < |trace| - 1 {
      assert ValidTransition(trace[i], trace[i+1]);
      // ValidTransition(Cancelled, _) is always false → contradiction
      // So i must be the last index
      assert false;
    }
  }
}
