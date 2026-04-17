# Third-Party Licenses

**This repository does not redistribute any third-party binaries.** The
Alloy 6 distribution is downloaded at runtime by `skills/formal-modeling/
scripts/alloy_run.sh` from the official AlloyTools GitHub releases. The
downloaded jar is extracted into a local, gitignored cache at
`skills/formal-modeling/scripts/.alloy/extracted/`.

The components below are fetched as part of that Alloy distribution by
each user individually. They are **not** governed by this repository's
`LICENSE`; each retains its original license, and the license texts travel
inside the downloaded jar (`Alloy.txt`, `SAT4J.txt`, `MiniSat.txt`, and the
`LICENSES/` subdirectory).

The skill's `AlloyRunner` pins the SAT backend to `minisat.prover` (MiniSat
with unsat-core support, MIT) with `sat4j` (LGPL 2.1) as automatic fallback.
The downloaded jar also contains Lingeling and (historically) ZChaff; after
extraction, `alloy_run.sh` runs a `strip_nc_solvers` step that physically
deletes the Lingeling native binaries and its JNI wrapper package from the
local cache, so the noncommercial solvers are not merely never invoked but
absent from disk.

## Alloy 6 distribution — downloaded at runtime, not redistributed here

| Component       | License                                              | License text location (after download)                                 | Invoked by skill?  |
| --------------- | ---------------------------------------------------- | ---------------------------------------------------------------------- | ------------------ |
| Alloy Analyzer  | MIT                                                  | `.alloy/extracted/Alloy.txt`                                           | yes                |
| Kodkod          | MIT                                                  | `.alloy/extracted/Kodkod.txt`                                          | yes                |
| MiniSat         | MIT (**pinned SAT backend**)                         | `.alloy/extracted/MiniSat.txt`                                         | **yes**            |
| SAT4J           | LGPL 2.1 (fallback SAT backend)                      | `.alloy/extracted/SAT4J.txt`                                           | fallback only      |
| JavaCup         | MIT-like, GPL-compatible                             | `.alloy/extracted/JavaCup.txt`                                         | yes                |
| Gini            | MIT                                                  | `.alloy/extracted/LICENSES/Gini.txt`                                   | yes                |
| Electrod        | MPL 2.0                                              | `.alloy/extracted/LICENSES/Electrod.txt`                               | no                 |
| Glucose/Syrup   | MIT-base + no-SAT-competition restriction            | `.alloy/extracted/LICENSES/Glucose.txt`                                | no                 |
| ZChaff          | Princeton NC — redistribution requires consent       | `.alloy/extracted/ZChaff.txt`                                          | **no**             |
| Lingeling       | Biere NC — evaluation/research only                  | `.alloy/extracted/LICENSES/Lingeling.txt`                              | **no**             |

### Why runtime download rather than bundling

**ZChaff** (Princeton) requires *prior Princeton consent* for any
redistribution, and **Lingeling** (Armin Biere) grants permissions only for
"evaluation and research purposes" with "all other usage reserved." By
fetching the Alloy jar at runtime, each user invokes AlloyTools' own
distribution channel directly, and this repository never acts as a
redistributor of ZChaff or Lingeling. The pinning in `AlloyRunner` is an
additional safeguard — even after download, the skill never invokes those
two solvers. See `system-models/reports/license-compatibility-reconciliation.md`
for the reconciliation finding that drove this design.

**SAT4J** (LGPL 2.1) and **Electrod** (MPL 2.0) are weak-copyleft. Users
who download the jar may redistribute them alongside differently-licensed
work, but modifications to SAT4J or Electrod files must remain under their
original license.

## Invoked tools — not bundled, not downloaded by us

These are executed by the scripts but are not redistributed or fetched by
this repository. Users install them themselves.

| Tool          | License                                |
| ------------- | -------------------------------------- |
| OpenJDK / Java 17+ | GPL 2.0 with Classpath Exception  |
| Python 3      | Python Software Foundation License     |
| Dafny         | MIT License                            |
| Docker (client) | Apache License 2.0                   |

## Offline / air-gapped use

`scripts/alloy_run.sh` detects a pre-existing `.alloy/extracted/` directory
or `.alloy/alloy.jar` file and skips the download. You can place your own
copy of the Alloy jar there — obtained under whatever terms apply to you —
and the script will use it. This is useful for offline / air-gapped
environments, or if you have your own redistribution agreement with
Princeton or Biere.
