-- ================================================================
-- Data Conversion & Time-Series Verification (generic example)
--
-- Demonstrates formal verification of data format pipelines:
--   • Axiomatic timezone conversion (properties, not implementation)
--   • Wire-format encoding mismatch (double-offset bug detection)
--   • Database column type semantics (with-TZ vs without-TZ casts)
--   • Singleton lookup map (ternary relation for global functions)
--   • Effect bag (typed contributions replacing Int accumulation)
--   • Sliding window (which records fall in/out under timezone shifts)
--
-- Domain: a metrics system where sensors submit readings with timestamps.
-- Readings are attributed to daily metric records within a 2-day window.
-- The system stores timestamps in a wire format that can be misinterpreted.
--
-- Checks (9 assertions):
--   A1  UtcIdentity               — UTC timezone preserves the day
--   A2  EastBound                  — East TZ shifts at most +1 day
--   A3  WestBound                  — West TZ shifts at most -1 day
--   A4  Monotonicity               — larger offset never gives earlier day
--   A5  CorrectDecoderWorks        — correct decoder recovers intended day
--   A6  BrokenDecoderFails         — broken decoder gives wrong day for East TZ
--   A7  WithoutTZIgnoresSession    — timestamp-no-TZ is session-independent
--   A8  WithTZInUtcGivesUtcDay     — timestamptz in UTC session = UTC day
--   A9  NoWrongDayWithCorrectPath  — correct lookup + UTC session = no wrong-day hits
-- ================================================================

module data_conversion


-- ================================================================
-- 1. CALENDAR DAY (acyclic chain)
-- ================================================================

sig Day { next: lone Day }

fact DayOrdering {
  all d: Day | d not in d.^next       -- acyclic
  lone { d: Day | no next.d }         -- single root
}


-- ================================================================
-- 2. TIMEZONE + DIRECTION
-- ================================================================

sig Timezone { offsetHours: Int }

fact TimezoneRange {
  all tz: Timezone | tz.offsetHours >= -12 and tz.offsetHours <= 14
}

abstract sig Direction {}
one sig West, Utc, East extends Direction {}

fun dir[tz: Timezone]: Direction {
  tz.offsetHours = 0 => Utc else
  tz.offsetHours > 0 => East else West
}


-- ================================================================
-- 3. TIMESTAMP + AXIOMATIC LOCAL DAY CONVERSION
-- ================================================================

sig Timestamp { utcDay: Day }

-- Singleton lookup map: global function (Timestamp, Timezone) → Day
one sig DayMap { of: Timestamp -> Timezone -> one Day }

fun localDay[t: Timestamp, tz: Timezone]: Day { DayMap.of[t][tz] }

-- Axiom 1: UTC preserves the day
fact UtcIdentity {
  all t: Timestamp, tz: Timezone |
    dir[tz] = Utc implies localDay[t, tz] = t.utcDay
}

-- Axiom 2: East shifts at most +1 day
fact EastBound {
  all t: Timestamp, tz: Timezone |
    dir[tz] = East implies
      (localDay[t, tz] = t.utcDay or localDay[t, tz] = t.utcDay.next)
}

-- Axiom 3: West shifts at most -1 day
fact WestBound {
  all t: Timestamp, tz: Timezone |
    dir[tz] = West implies
      (localDay[t, tz] = t.utcDay or t.utcDay = localDay[t, tz].next)
}

-- Axiom 4: Larger offset never gives earlier day
fact Monotonicity {
  all t: Timestamp, tz1, tz2: Timezone |
    tz1.offsetHours < tz2.offsetHours implies
      (localDay[t, tz1] = localDay[t, tz2]
       or localDay[t, tz1].next = localDay[t, tz2])
}


-- ================================================================
-- 4. WIRE FORMAT ENCODING + MISMATCH
-- ================================================================

-- Wire-format: UTC fields = local wall-clock (not real UTC)
pred wireEncoded[t: Timestamp, intendedDay: Day] {
  t.utcDay = intendedDay
}

-- Correct decoder: extract literal day from wire format
fun correctDecode[t: Timestamp]: Day { t.utcDay }

-- Broken decoder: applies timezone offset to wire format (double-shifts)
fun brokenDecode[t: Timestamp, tz: Timezone]: Day { localDay[t, tz] }


-- ================================================================
-- 5. DATABASE COLUMN TYPES
-- ================================================================

abstract sig ColumnKind {}
one sig WithTZ    extends ColumnKind {}   -- timestamptz
one sig WithoutTZ extends ColumnKind {}   -- timestamp (no TZ)

sig StoredValue {
  colKind : one ColumnKind,
  epoch   : one Timestamp,
  wallDay : lone Day
}

fact WithTZHasNoWallDay    { all v: StoredValue | v.colKind = WithTZ    implies no  v.wallDay }
fact WithoutTZHasWallDay   { all v: StoredValue | v.colKind = WithoutTZ implies one v.wallDay }

sig DBSession { sessionTZ: one Timezone }

fun dateCast[v: StoredValue, s: DBSession]: Day {
  v.colKind = WithTZ => localDay[v.epoch, s.sessionTZ]
  else v.wallDay
}


-- ================================================================
-- 6. METRIC RECORDS + EFFECT BAG
-- ================================================================

abstract sig Bool {}
one sig True, False extends Bool {}

sig Sensor { tz: one Timezone }

sig MetricRecord {
  sensor: one Sensor,
  day:    one Day,
  score:  one ScoreRange
}

fact MetricUnique {
  all s: Sensor, d: Day | lone { r: MetricRecord | r.sensor = s and r.day = d }
}

-- Score ranges (ordered enum chain, no Int needed)
abstract sig ScoreRange { higher: lone ScoreRange }
one sig Low  extends ScoreRange {}
one sig Mid  extends ScoreRange {}
one sig High extends ScoreRange {}
one sig Peak extends ScoreRange {}

fact ScoreChain {
  Low.higher = Mid
  Mid.higher = High
  High.higher = Peak
  no Peak.higher
}

-- Readings (events that contribute to metric records)
sig Reading {
  sensor:    one Sensor,
  timestamp: one Timestamp,
  sensorTZ:  one Timezone,
  intensity: one Intensity,
  positive:  one Bool
}

abstract sig Intensity {}
one sig None, Small, Medium, Large extends Intensity {}

pred activates[r: Reading] { r.intensity != None }

fun readingDay[r: Reading]: Day { localDay[r.timestamp, r.sensorTZ] }

-- 2-day attribution window
fun targetWindow[r: Reading]: set MetricRecord {
  let d = readingDay[r] |
  { mr: MetricRecord | mr.sensor = r.sensor and (mr.day = d or mr.day = d.next) }
}

pred contributes[r: Reading, mr: MetricRecord] {
  activates[r] and mr in targetWindow[r]
}

-- Effect bag: one contribution per (reading, record) pair
sig Contribution {
  source: one Reading,
  target: one MetricRecord,
  strength: one Intensity,
  polarity: one Bool
}

fact ContributionUnique {
  all r: Reading, mr: MetricRecord |
    lone c: Contribution | c.source = r and c.target = mr
}

fact ContributionMatchesSource {
  all c: Contribution | c.strength = c.source.intensity and c.polarity = c.source.positive
}

fact ContributionBijection {
  all c: Contribution | contributes[c.source, c.target]
  all r: Reading, mr: MetricRecord |
    contributes[r, mr] implies one c: Contribution | c.source = r and c.target = mr
}

fun contributionsFor[mr: MetricRecord]: set Contribution {
  { c: Contribution | c.target = mr }
}


-- ================================================================
-- 7. ASSERTIONS
-- ================================================================

-- A1-A4: Timezone axiom properties (proved by the axioms themselves)
assert UtcPreservesDay {
  all t: Timestamp, tz: Timezone | dir[tz] = Utc implies localDay[t, tz] = t.utcDay
}

assert EastNeverShiftsTwoDays {
  all t: Timestamp, tz: Timezone | dir[tz] = East implies
    localDay[t, tz] in t.utcDay + t.utcDay.next
}

assert WestNeverShiftsTwoDays {
  all t: Timestamp, tz: Timezone, d: Day |
    dir[tz] = West and localDay[t, tz] = d implies
      (t.utcDay = d or t.utcDay = d.next)
}

assert LargerOffsetNeverEarlier {
  all t: Timestamp, tz1, tz2: Timezone |
    (dir[tz1] = West and dir[tz2] = East) implies
      localDay[t, tz1] in localDay[t, tz2].*(~next)
}

-- A5: Correct decoder always recovers intended day
assert CorrectDecoderWorks {
  all t: Timestamp, d: Day | wireEncoded[t, d] => correctDecode[t] = d
}

-- A6: Broken decoder gives wrong result for East TZ midnight crossing
assert BrokenDecoderWrongForEast {
  all t: Timestamp, tz: Timezone, d: Day |
    wireEncoded[t, d] and dir[tz] = East and brokenDecode[t, tz] = d.next
    => brokenDecode[t, tz] != d
}

-- A7: timestamp-no-TZ is session-independent
assert WithoutTZIgnoresSession {
  all v: StoredValue, s1, s2: DBSession |
    v.colKind = WithoutTZ => dateCast[v, s1] = dateCast[v, s2]
}

-- A8: timestamptz in UTC session = UTC day
assert WithTZInUtcGivesUtcDay {
  all v: StoredValue, s: DBSession |
    v.colKind = WithTZ and dir[s.sessionTZ] = Utc =>
      dateCast[v, s] = v.epoch.utcDay
}

-- A9: Correct decode + UTC session → no wrong-day metric hits
assert NoWrongDayWithCorrectPath {
  all t: Timestamp, v: StoredValue, s: DBSession, dPrev, d: Day |
    dPrev.next = d and wireEncoded[t, d]
    and v.colKind = WithTZ and v.epoch.utcDay = dPrev
    and dir[s.sessionTZ] = Utc
  => dateCast[v, s] != d and dateCast[v, s] != d.next
}


-- ================================================================
-- 8. CHECKS
-- ================================================================

check UtcPreservesDay           for 3 but 6 Contribution, 6 Int
check EastNeverShiftsTwoDays    for 3 but 6 Contribution, 6 Int
check WestNeverShiftsTwoDays    for 3 but 6 Contribution, 6 Int
check LargerOffsetNeverEarlier  for 3 but 6 Contribution, 6 Int
check CorrectDecoderWorks       for 3 but 6 Contribution, 6 Int
check BrokenDecoderWrongForEast for 3 but 6 Contribution, 6 Int
check WithoutTZIgnoresSession   for 3 but 6 Contribution, 6 Int
check WithTZInUtcGivesUtcDay    for 3 but 6 Contribution, 6 Int
check NoWrongDayWithCorrectPath for 3 but 6 Contribution, 6 Int


-- ================================================================
-- 9. SCENARIOS
-- ================================================================

-- S1: East TZ midnight crossing — same UTC instant, different local days
run MidnightCrossing {
  some t: Timestamp, tzUtc, tzEast: Timezone, d: Day |
    dir[tzUtc] = Utc and dir[tzEast] = East
    and t.utcDay = d
    and localDay[t, tzUtc] = d
    and localDay[t, tzEast] = d.next
} for 3 but exactly 2 Timezone, exactly 1 Timestamp, exactly 3 Day,
      0 Reading, 0 MetricRecord, 0 Contribution, 0 StoredValue, 0 DBSession, 6 Int

-- S2: Double-offset bug witness
run DoubleOffsetBug {
  some t: Timestamp, tz: Timezone, d: Day |
    dir[tz] = East and wireEncoded[t, d]
    and brokenDecode[t, tz] = d.next
    and correctDecode[t] = d
} for 3 but exactly 1 Timestamp, exactly 1 Timezone, exactly 3 Day,
      0 Reading, 0 MetricRecord, 0 Contribution, 0 StoredValue, 0 DBSession, 6 Int

-- S3: Non-UTC session shifts date cast (latent bug)
run NonUtcSessionShifts {
  some v: StoredValue, s: DBSession, d: Day |
    v.colKind = WithTZ and dir[s.sessionTZ] = East
    and v.epoch.utcDay = d and dateCast[v, s] = d.next
} for 3 but exactly 1 StoredValue, exactly 1 DBSession, exactly 3 Day,
      0 Reading, 0 MetricRecord, 0 Contribution, 6 Int

-- S4: Reading contributes to 2-day window
run TwoDayAttribution {
  some r: Reading, mr1, mr2: MetricRecord |
    mr1 != mr2
    and contributes[r, mr1] and contributes[r, mr2]
    and mr1.day.next = mr2.day
} for 3 but exactly 1 Sensor, exactly 1 Reading,
      exactly 2 MetricRecord, exactly 2 Contribution, exactly 3 Day, 6 Int

-- S5: Cross-timezone disjoint windows — same timestamp targets different records
run CrossTZDisjointWindows {
  some r1, r2: Reading, d: Day |
    r1.timestamp = r2.timestamp and r1.sensor = r2.sensor
    and dir[r1.sensorTZ] = Utc and dir[r2.sensorTZ] = East
    and readingDay[r1] = d and readingDay[r2] = d.next
} for 3 but exactly 1 Sensor, exactly 2 Reading, exactly 2 Timezone,
      exactly 3 Day, 6 Int
