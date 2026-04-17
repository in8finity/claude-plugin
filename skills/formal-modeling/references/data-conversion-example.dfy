/**
 * Data Conversion & Timezone Verification — Dafny port
 *
 * Ported from references/data-conversion-example.als.
 *
 * Verifies axiomatic timezone properties, wire-format encoding/decoding,
 * DB column type semantics (timestamptz vs timestamp), and effect bags.
 *
 * Key insight: we don't implement timezone math — we axiomatize properties
 * (UTC identity, monotonicity, bounded shift) and prove consequences.
 */

// ============================================================
// Day ordering (abstract timeline)
// ============================================================

// We model days as integers (position on timeline)
type Day = int

predicate dayBefore(a: Day, b: Day) { a < b }
predicate dayAtOrBefore(a: Day, b: Day) { a <= b }

// ============================================================
// Timezone model (axiomatic — no actual clock math)
// ============================================================

// Offset in hours from UTC (-12 to +14)
type TzOffset = int

predicate validOffset(o: TzOffset) { -12 <= o && o <= 14 }

datatype Direction = West | Utc | East

function direction(offset: TzOffset): Direction
  requires validOffset(offset)
{
  if offset == 0 then Utc
  else if offset > 0 then East
  else West
}

// Local day = UTC day + shift (may be -1, 0, or +1 day)
// We axiomatize this as: localDay(utcDay, offset) = utcDay + dayShift(offset)
// where dayShift is bounded to {-1, 0, +1}
function dayShift(offset: TzOffset): int
  requires validOffset(offset)
  ensures -1 <= dayShift(offset) <= 1
{
  if offset >= 12 then 1      // far east: next day
  else if offset <= -12 then -1  // far west: prev day
  else 0                        // same day
}

function localDay(utcDay: Day, offset: TzOffset): Day
  requires validOffset(offset)
{
  utcDay + dayShift(offset)
}

// ============================================================
// Timezone axiom proofs
// ============================================================

// UTC preserves day (offset 0 → no shift)
lemma UtcPreservesDay(utcDay: Day)
  ensures localDay(utcDay, 0) == utcDay
{}

// East timezone never shifts by more than 1 day
lemma EastNeverShiftsTwoDays(utcDay: Day, offset: TzOffset)
  requires validOffset(offset)
  requires direction(offset) == East
  ensures localDay(utcDay, offset) - utcDay <= 1
{}

// West timezone never shifts by more than 1 day
lemma WestNeverShiftsTwoDays(utcDay: Day, offset: TzOffset)
  requires validOffset(offset)
  requires direction(offset) == West
  ensures utcDay - localDay(utcDay, offset) <= 1
{}

// Monotonicity: larger offset → same or later local day
lemma LargerOffsetNeverEarlier(utcDay: Day, o1: TzOffset, o2: TzOffset)
  requires validOffset(o1) && validOffset(o2)
  requires o1 <= o2
  ensures localDay(utcDay, o1) <= localDay(utcDay, o2)
{}

// ============================================================
// Wire format encoding/decoding
// ============================================================

datatype WireTimestamp = WireTimestamp(utcDay: Day)

// Correct decoder: just read the UTC day
function correctDecode(t: WireTimestamp): Day { t.utcDay }

// Broken decoder: applies timezone offset (double-conversion bug)
function brokenDecode(t: WireTimestamp, offset: TzOffset): Day
  requires validOffset(offset)
{ localDay(t.utcDay, offset) }

// Correct decoder always returns the original day
lemma CorrectDecoderWorks(t: WireTimestamp)
  ensures correctDecode(t) == t.utcDay
{}

// Broken decoder gives wrong result for east timezones
lemma BrokenDecoderWrongForEast(t: WireTimestamp, offset: TzOffset)
  requires validOffset(offset)
  requires offset >= 12  // far east
  ensures brokenDecode(t, offset) != t.utcDay
{
  assert dayShift(offset) == 1;
}

// ============================================================
// DB column types: timestamptz vs timestamp
// ============================================================

datatype ColumnKind = WithTZ | WithoutTZ

datatype StoredValue = StoredValue(
  colKind: ColumnKind,
  utcDay: Day,
  wallDay: Day  // only meaningful for WithoutTZ columns
)

// ::date cast behavior depends on column type and session timezone
function dateCast(v: StoredValue, sessionOffset: TzOffset): Day
  requires validOffset(sessionOffset)
{
  match v.colKind {
    case WithTZ    => localDay(v.utcDay, sessionOffset)  // converts to session TZ
    case WithoutTZ => v.wallDay                           // returns stored wall-clock day
  }
}

// WithoutTZ ignores session timezone
lemma WithoutTZIgnoresSession(v: StoredValue, o1: TzOffset, o2: TzOffset)
  requires v.colKind == WithoutTZ
  requires validOffset(o1) && validOffset(o2)
  ensures dateCast(v, o1) == dateCast(v, o2)
{}

// WithTZ in UTC session gives UTC day
lemma WithTZInUtcGivesUtcDay(v: StoredValue)
  requires v.colKind == WithTZ
  ensures dateCast(v, 0) == v.utcDay
{}

// No wrong day with correct path: store as timestamptz, read in UTC session
lemma NoWrongDayWithCorrectPath(v: StoredValue)
  requires v.colKind == WithTZ
  ensures dateCast(v, 0) == v.utcDay
{}

// ============================================================
// Effect bags (typed contributions)
// ============================================================

datatype Intensity = NoEffect | SmallEffect | MediumEffect | LargeEffect

datatype Reading = Reading(
  sensorOffset: TzOffset,
  utcDay: Day,
  intensity: Intensity
)

predicate activates(r: Reading) { r.intensity != NoEffect }

function readingLocalDay(r: Reading): Day
  requires validOffset(r.sensorOffset)
{ localDay(r.utcDay, r.sensorOffset) }

// A reading contributes to a metric record on the same local day
predicate contributes(r: Reading, targetDay: Day)
  requires validOffset(r.sensorOffset)
{
  activates(r) && readingLocalDay(r) == targetDay
}

// Readings from the same UTC day but different timezones may land on different local days
lemma CrossTZDisjointDays(r1: Reading, r2: Reading)
  requires validOffset(r1.sensorOffset) && validOffset(r2.sensorOffset)
  requires r1.utcDay == r2.utcDay
  requires r1.sensorOffset >= 12 && r2.sensorOffset <= -12
  ensures readingLocalDay(r1) != readingLocalDay(r2)
{
  assert dayShift(r1.sensorOffset) == 1;
  assert dayShift(r2.sensorOffset) == -1;
}

// ============================================================
// Sliding window: readings within N days of a target
// ============================================================

predicate inWindow(r: Reading, targetDay: Day, windowSize: nat)
  requires validOffset(r.sensorOffset)
{
  var ld := readingLocalDay(r);
  targetDay - windowSize as int <= ld && ld <= targetDay + windowSize as int
}

// Timezone shift can push a reading outside a 0-width window
lemma TimezoneCanBreakWindow(r: Reading, targetDay: Day)
  requires validOffset(r.sensorOffset)
  requires r.utcDay == targetDay
  requires r.sensorOffset >= 12  // far east
  ensures !inWindow(r, targetDay, 0)
{
  assert dayShift(r.sensorOffset) == 1;
  assert readingLocalDay(r) == targetDay + 1;
}
