-- ================================================================
-- Derived Claude-Code Work: Downstream User Licensing Model
--
-- Question: a developer uses this plugin (formal-methods skill)
-- inside Claude Code to build their own software. What parts of what
-- they produce are encumbered by the plugin's CC BY-NC-SA 4.0
-- license, and what parts are free?
--
-- Two axes:
--   1. Derivative-work status of the output. Copyright law and CC 4.0
--      §1(a) say a work is "Adapted Material" when it is "translated,
--      altered, arranged, transformed, or otherwise modified" from the
--      Licensed Material. Merely being informed by the skill's ideas
--      or patterns does NOT create a derivative (idea-expression
--      dichotomy: ideas are not copyrightable, only specific
--      expressions are).
--
--   2. Usage context. CC BY-NC-SA 4.0 §2(a)(1) grants rights "for
--      NonCommercial purposes only." The act of *using* the skill in
--      a commercial context (e.g., at a for-profit employer, to build
--      a revenue-generating product) arguably exceeds the default
--      public grant — separate from what the output looks like.
--
-- The model encodes five common artefact types a user might produce,
-- two usage contexts, and two possible user licenses (the default
-- public CC grant, or a privately negotiated commercial license).
--
-- Assertions:
--   A1 UsersOwnNonDerivativeWorkIsFree
--   A2 DerivativesInheritCCForDefaultLicensee
--   A3 CommercialUseOfSkillRequiresCommercialLicense
--   A4 PaidLicenseCoversEverything
-- ================================================================

module derived_claude_code_work

abstract sig Bool {}
one sig True, False extends Bool {}

-- ─── Usage context ──────────────────────────────────────────────
abstract sig UsageContext {}
one sig NoncommercialContext extends UsageContext {}
one sig CommercialContext    extends UsageContext {}

-- ─── What license the user holds ────────────────────────────────
abstract sig UserLicense {}
one sig DefaultCCLicense      extends UserLicense {} -- the public grant (CC BY-NC-SA 4.0)
one sig PaidCommercialLicense extends UserLicense {} -- privately negotiated with the rights holder

-- A single user, parameterized for scenario runs.
one sig User {
  context : one UsageContext,
  license : one UserLicense
}

-- ─── Artefacts a user typically produces ────────────────────────
--
-- Each artefact is classified along three dimensions:
--   copiesSkillMaterial  : did the user paste verbatim chunks of
--                          our skill files into this artefact?
--   modifiesSkillFiles   : did the user edit SKILL.md, scripts,
--                          references, or other files of the skill
--                          itself?
--   basedOnUserSystem    : does this artefact describe or implement
--                          the user's own system (not the skill)?
abstract sig Artefact {
  copiesSkillMaterial : one Bool,
  modifiesSkillFiles  : one Bool,
  basedOnUserSystem   : one Bool
}

one sig UserApplicationCode   extends Artefact {} -- their proprietary software
one sig UserAlloyModel        extends Artefact {} -- .als model of their system
one sig UserVerificationReport extends Artefact {} -- reconciliation / enforcement / etc.
one sig UserSkillFork         extends Artefact {} -- they forked our repo to modify the skill
one sig VerbatimReferenceCopy extends Artefact {} -- they pasted a reference .als verbatim

fact ArtefactProfiles {
  UserApplicationCode.copiesSkillMaterial = False
  UserApplicationCode.modifiesSkillFiles  = False
  UserApplicationCode.basedOnUserSystem   = True

  UserAlloyModel.copiesSkillMaterial = False
  UserAlloyModel.modifiesSkillFiles  = False
  UserAlloyModel.basedOnUserSystem   = True

  UserVerificationReport.copiesSkillMaterial = False
  UserVerificationReport.modifiesSkillFiles  = False
  UserVerificationReport.basedOnUserSystem   = True

  UserSkillFork.copiesSkillMaterial = True
  UserSkillFork.modifiesSkillFiles  = True
  UserSkillFork.basedOnUserSystem   = False

  VerbatimReferenceCopy.copiesSkillMaterial = True
  VerbatimReferenceCopy.modifiesSkillFiles  = False
  VerbatimReferenceCopy.basedOnUserSystem   = False
}

-- ─── Derivative-work predicate ──────────────────────────────────
-- An artefact is a derivative of the skill (triggering CC 4.0
-- §1(a) "Adapted Material") if the user has either copied protected
-- expression verbatim or modified the skill's own files. Being
-- informed by the skill's ideas and patterns does not count.
pred isDerivativeOfSkill[a: Artefact] {
  a.copiesSkillMaterial = True or a.modifiesSkillFiles = True
}

-- ─── Permission predicates ──────────────────────────────────────

-- Is the USE of the skill permitted for this user? CC BY-NC-SA 4.0
-- §2(a)(1) restricts the default grant to NonCommercial purposes.
-- A commercial user needs either a Paid license or to be operating
-- in a noncommercial context.
pred usagePermitted {
  User.context = NoncommercialContext
  or User.license = PaidCommercialLicense
}

-- Is commercial distribution / sale / deployment of this artefact
-- permitted? Three independent sufficient conditions:
--   (a) the artefact is not a derivative of the skill, so CC terms
--       don't apply — user has full commercial rights to their own
--       work.
--   (b) the user holds a paid commercial license — overrides NC.
--   (c) the use is noncommercial — NC itself isn't triggered.
pred commercialUsePermitted[a: Artefact] {
  not isDerivativeOfSkill[a]
  or User.license = PaidCommercialLicense
  or User.context = NoncommercialContext
}

-- ─── Assertions ─────────────────────────────────────────────────

-- A1: A user's non-derivative output (their own code, their own
-- models, reports about their own system) is theirs to use
-- commercially, regardless of the usage context or license tier.
-- This is the core protection for downstream users.
assert UsersOwnNonDerivativeWorkIsFree {
  all a: Artefact | not isDerivativeOfSkill[a]
    implies commercialUsePermitted[a]
}

-- A2: Derivative artefacts (forks, verbatim reference copies)
-- inherit CC BY-NC-SA 4.0 obligations for users on the default
-- license. A commercial user of a derivative without a paid
-- license is in violation.
assert DerivativesInheritCCForDefaultLicensee {
  all a: Artefact |
    isDerivativeOfSkill[a]
    and User.context = CommercialContext
    and User.license = DefaultCCLicense
    implies not commercialUsePermitted[a]
}

-- A3: A commercial user without a paid license cannot even USE
-- the skill, regardless of whether their output is derivative.
-- This is the "commercial use of the Licensed Material" restriction
-- from §2(a)(1) — it applies to the act of using, not just to the
-- distribution of output.
assert CommercialUseOfSkillRequiresCommercialLicense {
  User.context = CommercialContext and User.license = DefaultCCLicense
    implies not usagePermitted
}

-- A4: Paying for a commercial license authorizes both the usage
-- and any downstream commercial distribution of derivatives.
assert PaidLicenseCoversEverything {
  User.license = PaidCommercialLicense
    implies ( usagePermitted
            and (all a: Artefact | commercialUsePermitted[a]) )
}

-- ─── Scenario runs ──────────────────────────────────────────────

-- R1: the hobbyist / open-source developer path.
--     Noncommercial context, default CC license, ordinary outputs.
--     Expected: usage permitted, outputs unencumbered.
run HobbyistScenario {
  User.context = NoncommercialContext
  and User.license = DefaultCCLicense
  and usagePermitted
  and commercialUsePermitted[UserApplicationCode]
  and commercialUsePermitted[UserAlloyModel]
  and commercialUsePermitted[UserVerificationReport]
} for 8

-- R2: commercial user without a paid license — the problem case.
--     Their output would be legally theirs (non-derivative), but
--     their *use* of the skill violates NC. UNSAT is expected:
--     the solver cannot make usagePermitted = True under these
--     conditions.
run CommercialUserWithoutLicense_UsageViolates {
  User.context = CommercialContext
  and User.license = DefaultCCLicense
  and usagePermitted
} for 8

-- R3: commercial user with paid license — cleanly supported.
run CommercialUserWithPaidLicense {
  User.context = CommercialContext
  and User.license = PaidCommercialLicense
  and usagePermitted
  and commercialUsePermitted[UserApplicationCode]
  and commercialUsePermitted[UserSkillFork]
  and commercialUsePermitted[VerbatimReferenceCopy]
} for 8

-- R4: noncommercial user forks the skill — permitted; fork inherits
--     CC BY-NC-SA 4.0 via ShareAlike but that's fine for their
--     noncommercial distribution.
run NoncommercialForkingIsFine {
  User.context = NoncommercialContext
  and User.license = DefaultCCLicense
  and commercialUsePermitted[UserSkillFork]
} for 8

check UsersOwnNonDerivativeWorkIsFree               for 8
check DerivativesInheritCCForDefaultLicensee        for 8
check CommercialUseOfSkillRequiresCommercialLicense for 8
check PaidLicenseCoversEverything                   for 8
