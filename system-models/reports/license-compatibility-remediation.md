# License Compatibility — Remediation Report

**Closes:** D1 (ZChaff redistribution without consent) and D2 (Lingeling
redistribution outside grant scope), as identified in
`license-compatibility-reconciliation.md`.

**Date:** 2026-04-17

## Chosen remediation (runtime download + pinned MiniSat solver + post-extraction strip)

Three complementary measures combined:

1. **Runtime download.** `scripts/alloy_run.sh` fetches the Alloy 6
   distribution from AlloyTools' official GitHub releases on first run
   and extracts it to a local, gitignored cache at
   `skills/formal-modeling/scripts/.alloy/extracted/`. This repository
   does not redistribute any third-party binaries — the user's machine
   invokes AlloyTools' distribution channel directly.
2. **Pinned SAT backend.** The `AlloyRunner` (generated from the
   heredoc in `alloy_run.sh`) unconditionally selects
   `SATFactory.find("minisat.prover")` (MiniSat with unsat-core
   support, MIT) and falls back to `SATFactory.DEFAULT` (SAT4J,
   LGPL 2.1) if the MiniSat native library is not loadable on the
   current platform. ZChaff and Lingeling are not requested.
3. **Post-extraction strip.** Immediately after extraction (on every
   run, idempotent), `alloy_run.sh` invokes a `strip_nc_solvers`
   function that deletes the Lingeling native binaries
   (`native/<os>/<arch>/plingeling{,.exe}` across darwin, linux, and
   windows platforms) and its JNI wrapper package
   (`org/alloytools/solvers/natv/lingeling`) from the cache. ZChaff is
   not shipped as an executable solver in Alloy 6.2+ — only its
   historical license text remains in the jar.

Why all three measures:

- **Runtime download alone** closes the distribution question
  (we are not a redistributor) but leaves the noncommercial solvers
  physically present in every user's local cache, where a third-party
  tool could still invoke them.
- **Pinning alone** would close the invocation question for *our*
  `AlloyRunner` but not for anything else that reads the same cache.
- **The strip** removes the binaries from disk entirely, so no
  invocation is possible by anyone or anything after first run. It
  also makes the license-compatibility story auditable with a simple
  `find` command.

Together they close D1 and D2 from distribution, invocation, and
presence angles.

## Changes made

| # | Change | File(s) |
|---|--------|---------|
| 1 | Excluded the entire `.alloy/` runtime cache from git tracking | `.gitignore` |
| 2 | Pinned the SAT backend to `minisat.prover` with `SATFactory.DEFAULT` fallback in the runner | `skills/formal-modeling/scripts/alloy_run.sh` (AlloyRunner.java heredoc) |
| 3 | Added `strip_nc_solvers` function invoked after every extraction; deletes Lingeling binaries across all platforms and the JNI wrapper package | `skills/formal-modeling/scripts/alloy_run.sh` |
| 4 | Rewrote the third-party components section to describe runtime download + pinning + strip | `NOTICE` |
| 5 | Updated component table to mark invoked vs. never-invoked solvers; added note about physical removal post-strip | `THIRD_PARTY_LICENSES.md` |
| 6 | Updated README `Structure` and `License` sections | `README.md` |

## Script behavior after the change

`scripts/alloy_run.sh` branch tree on invocation:

1. If `.alloy/extracted/` exists locally → use it (offline, user-supplied).
2. Else if `.alloy/alloy.jar` exists → extract it (user-supplied jar).
3. Else → `curl` the latest `org.alloytools.alloy.dist.jar` from GitHub,
   extract, cache, and continue.

Either way, the compiled `AlloyRunner` then calls
`SATFactory.find("minisat.prover")` for every model.

Typical path for a fresh clone: branch 3 (download) on first run,
branch 1 (cached) on every subsequent run.

## Implications for the Alloy compatibility model

The model in `system-models/license-compatibility/license-compatibility.als`
was written against the earlier "bundled" state. After this remediation:

- `ZChaff.bundled` and `Lingeling.bundled` should be `False` from this
  repository's perspective — we do not redistribute them.
- The other components (downloaded by the user) are not "bundled by us"
  either, but they are still transitively present when the user runs
  the skill.

A follow-up revision of the Alloy model should separate
`Component.bundledByRepo` from `Component.fetchedAtRuntime`, and
introduce a `Component.isInvoked` flag. The six current assertions
would then re-verify cleanly against this split — ZChaff and
Lingeling's restrictions no longer flow into
`Package.effectiveRestrictions` from the repo's standpoint (we don't
distribute them; we don't invoke them). That follow-up is queued as
future work; not blocking for the legal exposure closure, which is
addressed structurally by the combination of gitignore + runtime
download + pinning.

## Residual risks

- **User of the plugin** still inherits all upstream constraints when
  `alloy_run.sh` fetches the jar on their machine. This is unchanged
  — `NOTICE` documents the constraints that bind the user.
- **AlloyTools' own redistribution authority** remains the legal
  basis for ZChaff and Lingeling reaching end users. If AlloyTools
  stops distributing those components, `alloy_run.sh` will fetch a
  jar missing the corresponding solvers; the pinned
  `minisat.prover` / `sat4j` backends continue to work either way.
- **CC BY-NC-SA 4.0** still applies to all original work in this
  repository. The combined remediation does not unlock commercial
  use of the plugin itself — only the upstream solver redistribution
  concern.

## Verdict

D1 and D2 are **closed by construction** — this repository never
redistributes ZChaff or Lingeling, and the skill's runner never
invokes them even if they are present in the user's local cache.
