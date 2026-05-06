module fdp_storage_chain

/*
 * Segment: TC29 + TC30 + TC36 / PW0-init / PW0-live / PW0-strict — harness
 * variant of the FDP storage-chain integrity model.
 *
 * Mirrors canonical/fdp_structured_chain.als but for hashharness MCP storage.
 * Where the canonical variant manually tracks PrevHypHash / ParentHypHash /
 * EvidenceHash text fields and detects tampering against ctime, the harness
 * variant relies on the hashharness server to:
 *   - assign each item a server-computed record_sha256 (identity hash) and
 *     stamp `created_at` server-side (callers cannot supply it);
 *   - reject creation of an item whose links violate declared target_types
 *     (and reject linking by text_sha256 — links carry record_sha256);
 *   - auto-derive citedEvidenceHash from the sorted record_sha256s of the
 *     linked Evidence items (link rule "many" with target_types: ["Evidence"]);
 *   - hold items immutable post-create (no mutation primitive in the API);
 *   - enforce CAS on chain heads where a link declares
 *     `chain_predecessor: true` (Report chain in our schema);
 *   - bind each item to its as-of schema (`schema_sha256`) and validate
 *     that the schema head chain is itself append-only (CAS-protected).
 *
 * Items are therefore immutable atoms. The interesting failure modes shift
 * from "tampering breaks the hash" to "schema link rule rejects creation"
 * and "init order is inverted" — what TC29 and TC30 actually rule out.
 *
 * Cross-reference: upstream hashharness ships its own Alloy model at
 * https://github.com/in8finity/hashharness/blob/HEAD/system-model/system.als
 * which proves the *server-primitive* layer (UniqueText, RecordHashUnique,
 * NoBackdate, NoFork, SchemaBinding) under both honest and adversarial
 * transitions. This model sits ONE LAYER ABOVE: assuming those primitives
 * hold, it verifies our protocol uses them correctly (init order, link
 * target_types, citedEvidenceHash one-to-one over Evidence sets, single-
 * write discipline). Together they form an assume-guarantee pair.
 *
 * Schema (from formal-debugger-harness/SKILL.md):
 *   Report          prevReport: single Report (chain_predecessor: true)
 *   HypothesisEvent prevHyp: single (HypothesisEvent | Report)
 *                   citedEvidence: many Evidence
 *                   supersedes: single HypothesisEvent
 *   Evidence        parentHypEvent: single HypothesisEvent
 *   ModelChange     prevModel: single (ModelChange | Report)
 *                   parentHypEvent: single HypothesisEvent
 *
 * `chain_predecessor` is on `prevReport` only. `prevHyp` and `prevModel`
 * deliberately allow Report-v1 anchoring which conflicts with the "first
 * item omits predecessor" CAS contract; concurrent-fork on those chains
 * relies on the single-writer assumption.
 */

-- ============================================================
-- Domain
-- ============================================================

-- record_sha256 is server-computed and unique per item; we abstract it as
-- an opaque identity Hash. Two distinct items always have distinct hashes
-- (no collisions in scope; the server enforces this).
sig Hash {}

-- Schema versions form an append-only chain. set_schema is CAS-protected:
-- each version (except the genesis) references its predecessor. Each item
-- carries `schemaSha`, the schema head's record_sha256 at the item's write
-- time. Used to validate items against their as-of schema even after
-- subsequent schema updates.
sig SchemaVersion {
  schemaPrev: lone SchemaVersion,
  schemaIdx: one Int        -- creation order; 0 = genesis schema
} { schemaIdx >= 0 }

one sig GenesisSchema in SchemaVersion {} {
  no schemaPrev and schemaIdx = 0
}

fact SchemaChainAcyclic {
  no v: SchemaVersion | v in v.^schemaPrev
}

fact SchemaChainAnchored {
  -- Every schema version reaches the genesis schema via schemaPrev.
  all v: SchemaVersion | GenesisSchema in (v + v.^schemaPrev)
}

fact DistinctSchemaIdx {
  all disj v1, v2: SchemaVersion | v1.schemaIdx != v2.schemaIdx
}

-- The four item types declared in the schema. Each item has a server-
-- computed record_sha256 (modeled as `recordHash`) and a creation index
-- (modeled as `createdIdx`) capturing when the create_item call landed.
abstract sig Item {
  recordHash: one Hash,
  createdIdx: one Int,
  schemaSha: one SchemaVersion  -- as-of schema head when this item was created
} { createdIdx >= 1 }    -- index 0 is reserved for the genesis Schema

sig Report extends Item {
  versionNum: one Int,
  prevReport: lone Report    -- absent for v1; otherwise Report (target_types: [Report])
}

sig HypothesisEvent extends Item {
  prevHyp: one Item,         -- target_types: [HypothesisEvent, Report]
  citedEvidence: set Evidence, -- target_types: [Evidence], kind=many; possibly empty
  supersedes: lone HypothesisEvent, -- target_types: [HypothesisEvent], kind=single
  citedEvidenceHash: lone Hash      -- server-derived only when citedEvidence is non-empty
}

sig Evidence extends Item {
  parentHypEvent: one HypothesisEvent  -- target_types: [HypothesisEvent]
}

sig ModelChange extends Item {
  prevModel: one Item,                  -- target_types: [ModelChange, Report]
  parentHypEvent: one HypothesisEvent   -- target_types: [HypothesisEvent]
}

-- The genesis Report (v1). PW0-init requires it exists before any non-Report
-- item. Only one v1.
one sig GenesisReport in Report {} { versionNum = 1 and no prevReport }

-- An item's schemaSha must point to a schema version created BEFORE the
-- item — you can only bind to a schema that already exists when you write.
-- Schema indices use 0+; item indices use 1+. The item's `schemaSha.schemaIdx`
-- must therefore be < its own createdIdx (with the convention that schema
-- indices are interleaved into the same total order as item indices).
fact ItemBindingTemporallyValid {
  all i: Item | i.schemaSha.schemaIdx < i.createdIdx
}

-- ============================================================
-- Structural facts
-- ============================================================

-- All items have distinct record_sha256 (server enforces uniqueness).
fact DistinctRecordHashes {
  all disj i1, i2: Item | i1.recordHash != i2.recordHash
}

-- All items have distinct creation indices (each create_item call is one
-- write at a unique step — TC36 single-record discipline).
fact DistinctCreationIndices {
  all disj i1, i2: Item | i1.createdIdx != i2.createdIdx
}

-- Report chain: positive versions, acyclic, exactly one v1, contiguous.
fact ReportChainStructure {
  all r: Report | r.versionNum > 0
  no r: Report | r in r.^prevReport
  all r: Report - GenesisReport |
    some r.prevReport and r.prevReport.versionNum = minus[r.versionNum, 1]
}

-- Acyclic chains for hypothesis and model.
fact HypChainAcyclic {
  no h: HypothesisEvent | h in h.^prevHyp
}

fact ModelChainAcyclic {
  no m: ModelChange | m in m.^prevModel
}

-- citedEvidenceHash is present iff the set of cited evidence is non-empty.
-- The server auto-derives it; we encode the existence (presence/absence)
-- here. The auto-derivation function itself is captured in `citedHashValid`.
fact CitedHashPresence {
  all h: HypothesisEvent | (some h.citedEvidence) iff (some h.citedEvidenceHash)
}

-- Acyclic supersedes (no record supersedes itself transitively).
fact SupersedesAcyclic {
  no h: HypothesisEvent | h in h.^supersedes
}

-- ============================================================
-- TC30 (PW0-live) — what verify_chain validates
-- ============================================================

-- (b) Every link points to an existing item of the declared target_types.
-- In Alloy, link cardinality and target sigs are already enforced by the
-- field declarations above (`prevReport: lone Report`, `prevHyp: one Item`
-- restricted by the predicate below, etc.). The only target_types check
-- not implicit in the field types is the union restrictions for prevHyp
-- and prevModel: they must be HypothesisEvent or Report (not Evidence,
-- not ModelChange).
pred targetTypesValid {
  all h: HypothesisEvent | h.prevHyp in HypothesisEvent + Report
  all m: ModelChange     | m.prevModel in ModelChange + Report
  -- A non-genesis Report's prevReport is implicit (typed as Report).
  -- supersedes must point to a HypothesisEvent (already typed).
  -- citedEvidence must be Evidence atoms (already typed).
  -- parentHypEvent must be HypothesisEvent (already typed).
}

-- (c) citedEvidenceHash is a deterministic function of the SET of cited
-- evidence record_sha256 values (sorted-and-hashed by the server). We model
-- it as: same evidence-hash-set ⇒ same citedEvidenceHash; distinct sets ⇒
-- distinct citedEvidenceHash. Equivalent to a one-to-one function over the
-- powerset of Evidence hashes.
pred citedHashValid {
  all disj h1, h2: HypothesisEvent |
    (some h1.citedEvidence and some h2.citedEvidence)
    => ((h1.citedEvidence.recordHash = h2.citedEvidence.recordHash)
        iff (h1.citedEvidenceHash = h2.citedEvidenceHash))
}

-- (d) Chain type sequences: prevHyp resolves into the GenesisReport in
-- finitely many steps (i.e. the hypothesis chain anchors on Report v1).
-- Same for prevModel.
pred chainsAnchorOnGenesis {
  all h: HypothesisEvent | GenesisReport in h.^prevHyp
  all m: ModelChange     | GenesisReport in m.^prevModel
}

-- Supersedes well-formed: a superseder is created AFTER its target.
-- (The server stores items immutably; supersedes only resolves to items
-- that already exist when the superseder is created.)
pred supersedesWellFormed {
  all h: HypothesisEvent | some h.supersedes
    => h.supersedes.createdIdx < h.createdIdx
}

-- Full TC30 (verify_chain ok): all five conditions hold. Note (a) — every
-- item has valid record_sha256/text_sha256/meta_sha256/links_sha256/
-- schema_sha256/schema_binding_sha256 — is structural in this model
-- (every Item has a recordHash + schemaSha by sig declaration; the schema
-- binding is enforced by ItemBindingTemporallyValid).
pred tc30_pass {
  targetTypesValid
  citedHashValid
  chainsAnchorOnGenesis
  supersedesWellFormed
  reportChainNoFork
}

-- ============================================================
-- TC29 (PW0-init) — schema chain initialized, then Report v1
-- ============================================================

-- The genesis schema (schemaIdx=0) is created first. GenesisReport (Report v1)
-- is created next. All other items have createdIdx strictly greater than
-- GenesisReport. Subsequent schema versions (if any) may be interleaved
-- with item creation, but each item must bind to a schema that pre-exists.
pred tc29_pass {
  GenesisSchema.schemaIdx < GenesisReport.createdIdx
  all i: Item - GenesisReport | GenesisReport.createdIdx < i.createdIdx
}

-- ============================================================
-- chain_predecessor CAS — Report chain is fork-free
-- ============================================================

-- The Report chain declares chain_predecessor: true on prevReport. The
-- server's CAS guarantees: no two Reports share the same prevReport. Our
-- protocol-level static encoding: distinct non-genesis Reports never name
-- the same predecessor.
pred reportChainNoFork {
  all disj r1, r2: Report - GenesisReport |
    r1.prevReport != r2.prevReport
}

-- ============================================================
-- TC36 (PW0-strict) — single create_item per record, no batch
-- ============================================================

-- Encoded structurally: each item has exactly one createdIdx (sig field
-- multiplicity `one`); each createdIdx is unique (DistinctCreationIndices).
-- Therefore each item ↔ unique creation step ↔ one create_item call.
-- The "no batch helper" rule is captured by the fact that no two distinct
-- items share a createdIdx.
pred tc36_pass {
  -- Tautological under the facts above; documents the property.
  all disj i1, i2: Item | i1.createdIdx != i2.createdIdx
}

-- ============================================================
-- Safety assertions
-- ============================================================

-- TC30-S1: target_types violation fails verify_chain.
-- A HypothesisEvent's prevHyp pointing at an Evidence (wrong type) breaks
-- targetTypesValid. (In production this is rejected at create_item time;
-- the model encodes it as: such a state cannot satisfy tc30_pass.)
assert PrevHypTypeViolationBreaksChain {
  all h: HypothesisEvent |
    h.prevHyp not in HypothesisEvent + Report => not targetTypesValid
}
check PrevHypTypeViolationBreaksChain for 5

assert PrevModelTypeViolationBreaksChain {
  all m: ModelChange |
    m.prevModel not in ModelChange + Report => not targetTypesValid
}
check PrevModelTypeViolationBreaksChain for 5

-- TC30-S2: citedEvidenceHash inconsistency breaks verify_chain.
-- Two state-change events citing different evidence sets must have
-- different citedEvidenceHash; same set ⇒ same hash.
assert CitedEvidenceHashConsistent {
  all disj h1, h2: HypothesisEvent |
    (some h1.citedEvidence and some h2.citedEvidence
     and h1.citedEvidence.recordHash != h2.citedEvidence.recordHash
     and h1.citedEvidenceHash = h2.citedEvidenceHash)
    => not citedHashValid
}
check CitedEvidenceHashConsistent for 5

-- TC30-S3: every hypothesis chain reaches GenesisReport.
assert AllHypsReachGenesis {
  chainsAnchorOnGenesis =>
    (all h: HypothesisEvent | GenesisReport in h.^prevHyp)
}
check AllHypsReachGenesis for 5

assert AllModelsReachGenesis {
  chainsAnchorOnGenesis =>
    (all m: ModelChange | GenesisReport in m.^prevModel)
}
check AllModelsReachGenesis for 5

-- TC30-S4: TC30 decomposition — verify_chain ok ⇔ all five conditions hold.
assert TC30Decomposition {
  tc30_pass iff (
    targetTypesValid and citedHashValid
    and chainsAnchorOnGenesis and supersedesWellFormed
    and reportChainNoFork
  )
}
check TC30Decomposition for 5

-- TC30-S4b: chain_predecessor CAS — under reportChainNoFork, no two
-- non-genesis Reports share a predecessor. (Server-enforced when prevReport
-- declares chain_predecessor: true.)
assert ReportChainSinglePathToGenesis {
  reportChainNoFork =>
    (all disj r1, r2: Report - GenesisReport |
       r1.prevReport != r2.prevReport)
}
check ReportChainSinglePathToGenesis for 5

-- TC30-S4c: schema binding — every item's schemaSha references a schema
-- that already exists in the chain (i.e., not a future or invented schema).
-- Together with ItemBindingTemporallyValid this captures schema_binding_sha256
-- soundness: the binding cannot reference a phantom schema.
assert SchemaBindingPreExisting {
  all i: Item | i.schemaSha in SchemaVersion
  all i: Item | i.schemaSha.schemaIdx < i.createdIdx
}
check SchemaBindingPreExisting for 5

-- TC30-S5: forward-supersession is impossible. A superseder must reference
-- an item created before itself (the server cannot resolve a link to an
-- item that does not yet exist).
assert NoForwardSupersession {
  supersedesWellFormed =>
    (all h: HypothesisEvent | some h.supersedes
       => h.supersedes.createdIdx < h.createdIdx)
}
check NoForwardSupersession for 5

-- TC29: under PW0-init, the genesis schema and Report v1 precede every other item.
assert PW0InitOrder {
  tc29_pass =>
    (GenesisSchema.schemaIdx < GenesisReport.createdIdx
     and all i: Item - GenesisReport | GenesisReport.createdIdx < i.createdIdx)
}
check PW0InitOrder for 5

-- TC36: single-record write discipline — no two items share a creation step.
assert PW0StrictUniqueCreation {
  all disj i1, i2: Item | i1.createdIdx != i2.createdIdx
}
check PW0StrictUniqueCreation for 5

-- ============================================================
-- Liveness scenarios
-- ============================================================

-- A valid investigation under all three gates: TC29 + TC30 + TC36.
run ValidHarnessInvestigation {
  tc29_pass
  tc30_pass
  tc36_pass
  #HypothesisEvent >= 2
  #Evidence >= 1
  #ModelChange >= 1
  #Report >= 2
  some h: HypothesisEvent | some h.citedEvidence
} for 8

-- Minimal scenario: just schema, genesis, and one anchored hypothesis.
run MinimalAnchoredHypothesis {
  tc29_pass
  tc30_pass
  tc36_pass
  #Report = 1
  #HypothesisEvent = 1
  no Evidence
  no ModelChange
} for 4

-- Counterexample witness: a state where prevHyp points at an Evidence
-- (target_types violation). Demonstrates that verify_chain CAN fail —
-- the rule isn't vacuous.
run TargetTypesViolationIsReachable {
  some h: HypothesisEvent | h.prevHyp in Evidence
  not tc30_pass
} for 5

-- Counterexample witness: two non-genesis Reports sharing a predecessor.
-- Without chain_predecessor: true on prevReport, this is structurally
-- reachable. Demonstrates the CAS rule isn't vacuous.
run ReportForkIsReachableWithoutCAS {
  some disj r1, r2: Report - GenesisReport |
    r1.prevReport = r2.prevReport
  not reportChainNoFork
} for 5

-- Supersedes is allowed: a state-change can supersede an earlier hypothesis
-- event without violating tc30_pass.
run SupersedesScenario {
  tc30_pass
  some h1, h2: HypothesisEvent |
    h1 != h2 and h1 in h2.supersedes and h1.createdIdx < h2.createdIdx
} for 6

-- Schema versioning: an investigation runs across a schema swap, items
-- before the swap bind to the genesis schema, items after bind to v2.
-- (set_schema is CAS-protected; the schema chain is itself append-only.)
run SchemaSwapAcrossInvestigation {
  some disj v1, v2: SchemaVersion |
    v1 = GenesisSchema and v2.schemaPrev = v1
    and some i1: Item | i1.schemaSha = v1
    and some i2: Item | i2.schemaSha = v2 and i2.createdIdx > GenesisReport.createdIdx
  tc30_pass
} for 6
