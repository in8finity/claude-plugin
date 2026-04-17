# Downstream User Licensing — Derived Claude-Code Work

**Question.** A developer uses this plugin (formal-methods skill) inside Claude Code to build their own software. What parts of what they produce are encumbered by the plugin's CC BY-NC-SA 4.0 license, and what parts are free? Who needs a commercial license, and when?

**Model:** `system-models/derived-claude-code-work/derived-claude-code-work.als`
**Date:** 2026-04-17

## Short answer by user type

| User type | Can they use the skill? | Can they sell the software they build with it? |
|-----------|-------------------------|------------------------------------------------|
| Hobbyist / open-source developer, noncommercial context | ✓ Yes, default CC grant covers them | ✓ Yes — their own code is not a derivative of the skill |
| Employee at for-profit company, using the skill at work | ✗ Not under the default grant — commercial use of the skill itself requires a paid license | ✓ If they *did* hold a paid license, their own code would still be theirs to sell |
| Someone who forks the skill and distributes their fork | ✓ Free to do so under CC BY-NC-SA 4.0 (noncommercial + ShareAlike) | ✗ Not commercially, unless they hold a paid license from the rights holder |
| Someone who copies a `references/*.als` verbatim into their product | That verbatim copy is Adapted Material under CC 4.0 — inherits CC BY-NC-SA 4.0 | ✗ Not commercially for that verbatim portion without a paid license |

The model verifies all four of these at scope 8 via the assertions below.

## The two dimensions the model splits on

### Dimension 1 — Derivative-work status of the output

CC 4.0 §1(a) defines **Adapted Material** as material *"derived from or based upon the Licensed Material and in which the Licensed Material is translated, altered, arranged, transformed, or otherwise modified."* Under copyright law's idea-expression dichotomy, **ideas and patterns are not protected; only specific expressions are.**

So:

| User artefact | Derivative? | Why |
|---|---|---|
| User's application code (their product) | ✗ | The code is the user's expression, informed by — but not copied from — the skill |
| User's Alloy model describing their own system | ✗ | Patterns like *"state machine with var sig"* are ideas; the specific model is the user's expression |
| User's verification / reconciliation report | ✗ | Report structure is format (not copyrightable); content is about user's system |
| User's fork of the skill | ✓ | Direct modification of the skill's files |
| Verbatim paste of a `references/*.als` file | ✓ | Direct copying of protected expression |

This is the same legal framework that lets a commercial programmer use a Python tutorial to learn Python, then write proprietary software in Python without paying the tutorial author — unless they literally copy tutorial code into their product.

### Dimension 2 — Usage context (commercial vs. noncommercial)

CC BY-NC-SA 4.0 §2(a)(1) grants rights **"for NonCommercial purposes only."** The key phrase in §1(k): *"NonCommercial means not primarily intended for or directed towards commercial advantage or monetary compensation."*

A read of the text that affects this plugin: **the act of *using* the Licensed Material in a commercial context is itself "commercial use" of the material.** An employee at a for-profit company, using the plugin as part of their paid development work on a revenue-generating product, is using the plugin for commercial advantage — that exceeds the default public grant.

This is why software tools licensed CC BY-NC-* are uncommon — the NC restriction bites the tool's *use*, not just the redistribution of output. Open-source software projects usually pick permissive (MIT, Apache) or copyleft (GPL, LGPL) licenses, not CC-NC.

## Formal verification — four assertions

The Alloy model encodes the four user types along both axes and verifies:

| # | Assertion | Verdict |
|---|-----------|---------|
| A1 | `UsersOwnNonDerivativeWorkIsFree` — non-derivative outputs are unencumbered regardless of context or license tier | ✓ |
| A2 | `DerivativesInheritCCForDefaultLicensee` — a commercial user on the default CC license cannot use derivatives commercially | ✓ |
| A3 | `CommercialUseOfSkillRequiresCommercialLicense` — commercial context + default license = usage itself is not permitted | ✓ |
| A4 | `PaidLicenseCoversEverything` — a paid commercial license authorizes both usage and derivative commercial distribution | ✓ |

Plus four scenario runs:

- `HobbyistScenario` — satisfiable (witness exists)
- `CommercialUserWithoutLicense_UsageViolates` — **UNSAT** (confirms A3: the solver cannot construct a state where a commercial user on the default license is permitted to use the skill)
- `CommercialUserWithPaidLicense` — satisfiable
- `NoncommercialForkingIsFine` — satisfiable

## The four scenarios in practice

### Scenario 1 — Hobbyist building open-source software

A developer uses the plugin on their personal time to verify an Alloy model of their open-source project. They publish their project under MIT.

- **Usage:** permitted (noncommercial context; default CC grant covers them).
- **Their project's license:** their choice, including MIT. Not a derivative of the skill.
- **Their Alloy model:** their choice. Not a derivative.
- **What they should do:** nothing special. Use freely. Optional — credit the plugin in their README.

### Scenario 2 — Employee at for-profit company

A developer at a SaaS company uses Claude Code + this plugin to verify the authorization state machine of their product.

- **Usage:** arguably **not permitted** under the default grant. §2(a)(1) restricts rights to NonCommercial use; using the plugin as part of paid product-development work is "directed towards commercial advantage."
- **Their authorization code:** their code. Not a derivative of the skill. No CC encumbrance.
- **Their Alloy model of authorization:** their model. Not a derivative.
- **What they should do:** contact the plugin author for a paid commercial license before using the plugin in their work. The author's negotiated license removes the NC restriction for their use.

### Scenario 3 — Fork and modification

Someone forks the plugin to add a new skill, new reference models, or new scripts.

- **Usage:** permitted under the default CC grant if the fork stays noncommercial.
- **Fork's license:** **must** be CC BY-NC-SA 4.0 (ShareAlike §3(b)). Attribution required.
- **Commercial redistribution of the fork:** requires a paid commercial license from the upstream rights holder. CC 4.0 §2(a)(1) forbids commercial redistribution without one.

### Scenario 4 — Verbatim copy of a reference file

A user copies `references/pipeline-example.als` into their repo unmodified and commits it as part of their build.

- **That file in the user's repo:** Adapted Material (verbatim copy) — inherits CC BY-NC-SA 4.0.
- **Their repo as a whole:** not necessarily encumbered; only the copied file triggers CC terms per §1(a) derivation test.
- **Commercial use of the copied file:** not permitted without a paid license.
- **What they should do:** (a) rewrite the model from scratch informed by the skill's patterns — typical and cheap; or (b) obtain a commercial license for that file; or (c) keep the repo noncommercial if the copy stays.

## Recommendations

### For the plugin (rights holder)

1. **Add a `COMMERCIAL.md` pointer in the README** with a one-paragraph note:

   > *"This plugin is free for noncommercial use under CC BY-NC-SA 4.0. Using the plugin as part of paid development work at a for-profit company, or shipping derivative works commercially, requires a commercial license. Contact [email] for terms."*

   This doesn't obligate anything — no published pricing needed. Just surfaces the option so commercial users know where to ask.

2. **Add a short disclaimer in `SKILL.md`** near the top:

   > *"Using this skill as part of commercial development work requires a commercial license from the rights holder; see [link]."*

   Claude Code will surface this when the skill activates, so users are aware at the moment of use.

3. **Do not require CLA on PRs today.** No contributors yet. When the first PR arrives, add a `CONTRIBUTING.md` with the relicensing clause so contributor code can flow into the commercial license too. (This is already documented in `system-models/dual-license/analysis.md`.)

### For a downstream user

Before using this plugin as part of paid work, check three things:

1. **Am I using it in a commercial context?** Employment at a for-profit company, contract work, or any revenue-generating activity counts. If yes, you need a commercial license.

2. **Am I copying anything verbatim from the plugin into my output?** If yes, that verbatim portion inherits CC BY-NC-SA 4.0. Either rewrite or obtain a license.

3. **Am I modifying the plugin itself and redistributing the fork?** If yes, the ShareAlike clause applies; your fork is CC BY-NC-SA 4.0 by default, commercial redistribution requires a paid license.

If all three answers are "no" (pure noncommercial use, no verbatim copies, no fork), you're free. **Your own code — the product you build — is yours, regardless of what license the plugin is under.**

## What this model does not attempt

Three things explicitly out of scope:

1. **AI-output copyright questions.** Whether Claude's output is copyrightable at all (US Copyright Office 2023 position: mostly no) is an orthogonal issue. The model assumes the user is the copyright holder of their output, however that question resolves.

2. **Patent claims.** CC 4.0 explicitly does not grant patent rights. If the user's product incorporates patentable techniques from the skill, that's a separate legal analysis.

3. **Jurisdictional variance on "commercial use" definition.** The model uses CC 4.0's own §1(k) wording. Some jurisdictions have case law interpreting "commercial" more narrowly; the model doesn't capture that. Take the model's verdict as the baseline; specific-jurisdiction variance is a lawyer question.

## Verdict

Non-derivative outputs are fully the user's — commercially usable, no CC obligations. The pinch point is **the act of using the plugin in a commercial context**, which the default CC BY-NC-SA 4.0 grant does not cover. A paid commercial license lifts that restriction. The branch `dual-license-investigation` (commit `45cf37c`) already proved that dual-licensing is legally viable on our side; this model proves it's the right mechanism to offer to commercial downstream users.
