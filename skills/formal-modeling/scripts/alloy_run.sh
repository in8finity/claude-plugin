#!/usr/bin/env bash
# Run an Alloy model through the official Alloy 6 jar and pretty-print
# the instances with alloy_format.py.
#
# Downloads the Alloy jar on first run; compiles AlloyRunner.java if needed.
# All derived artefacts are cached in .alloy/ next to this script.
#
# Works with local Java 17+ (preferred) or falls back to Docker.
#
# Usage:
#   ./alloy_run.sh [model.als]
#
# Defaults to model.als when no argument is given.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="${1:-$SCRIPT_DIR/model.als}"
CACHE="$SCRIPT_DIR/.alloy"
ALLOY_JAR="$CACHE/alloy.jar"
EXTRACTED="$CACHE/extracted"
RUNNER_SRC="$CACHE/AlloyRunner.java"
RUNNER_CLASS="$CACHE/AlloyRunner.class"

# ── helpers ──────────────────────────────────────────────────────────────────

need() { command -v "$1" &>/dev/null || return 1; }

# ── detect Java runtime ─────────────────────────────────────────────────────
# Alloy 6 requires Java 17+.  We try local java/javac first, then Docker.

USE_DOCKER=false
JAVA_CMD=""
JAVAC_CMD=""
JAR_CMD=""

detect_java() {
  # Check common Java 17+ locations
  local candidates=(
    java                                            # system default
    /opt/homebrew/opt/openjdk/bin/java               # Homebrew Apple Silicon (latest)
    /opt/homebrew/opt/openjdk@21/bin/java            # Homebrew Apple Silicon 21
    /opt/homebrew/opt/openjdk@17/bin/java            # Homebrew Apple Silicon 17
    /usr/local/opt/openjdk/bin/java                  # Homebrew Intel Mac (latest)
    /usr/local/opt/openjdk@21/bin/java               # Homebrew Intel Mac 21
    /usr/local/opt/openjdk@17/bin/java               # Homebrew Intel Mac 17
    "${JAVA_HOME:-/nonexistent}/bin/java"              # JAVA_HOME (if set)
    /usr/lib/jvm/java-21-openjdk-amd64/bin/java     # Debian/Ubuntu 21
    /usr/lib/jvm/java-17-openjdk-amd64/bin/java     # Debian/Ubuntu 17
    /usr/lib/jvm/java-21-openjdk/bin/java            # Fedora/Arch 21
    /usr/lib/jvm/java-17-openjdk/bin/java            # Fedora/Arch 17
  )

  for cmd in "${candidates[@]}"; do
    if [[ -x "$cmd" ]] || command -v "$cmd" &>/dev/null; then
      local ver
      ver=$("$cmd" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+)\..*/\1/' || echo "0")
      if [[ "$ver" -ge 17 ]]; then
        JAVA_CMD="$cmd"
        # Derive javac and jar from same installation
        local bin_dir
        bin_dir="$(dirname "$(command -v "$cmd" 2>/dev/null || echo "$cmd")")"
        if [[ -x "$bin_dir/javac" ]]; then
          JAVAC_CMD="$bin_dir/javac"
        fi
        if [[ -x "$bin_dir/jar" ]]; then
          JAR_CMD="$bin_dir/jar"
        fi
        return 0
      fi
    fi
  done
  return 1
}

if detect_java; then
  echo "Using local Java: $JAVA_CMD" >&2
elif need docker; then
  USE_DOCKER=true
  echo "No local Java 17+ found; using Docker (eclipse-temurin:17-jdk)" >&2
else
  echo "ERROR: No Java 17+ and no Docker found." >&2
  echo "" >&2
  echo "Install one of:" >&2
  echo "  macOS:   brew install openjdk@17" >&2
  echo "  Ubuntu:  sudo apt install openjdk-17-jdk" >&2
  echo "  Any:     install Docker" >&2
  exit 1
fi

need curl  || { echo "Required: curl" >&2; exit 1; }
need python3 || { echo "Required: python3" >&2; exit 1; }

# ── model file ───────────────────────────────────────────────────────────────

if [[ ! -f "$MODEL" ]]; then
  echo "Model not found: $MODEL" >&2
  exit 1
fi

mkdir -p "$CACHE"

# ── 1. download jar + extract ────────────────────────────────────────────────
# The Alloy jar is fetched from the official AlloyTools release on first run
# and extracted into a local, gitignored cache. If `extracted/` already
# exists from a prior run, we skip the download. To force a refresh, delete
# `.alloy/` and re-invoke.

if [[ -d "$EXTRACTED" ]]; then
  echo "Using pre-extracted Alloy classes" >&2
elif [[ -f "$ALLOY_JAR" ]]; then
  echo "Extracting Alloy classes from cached jar..." >&2
  mkdir -p "$EXTRACTED"
  if [[ "$USE_DOCKER" = true ]]; then
    docker run --rm \
      -v "$ALLOY_JAR:/alloy.jar:ro" \
      -v "$EXTRACTED:/extracted" \
      eclipse-temurin:17-jdk \
      bash -c "cd /extracted && jar xf /alloy.jar"
  else
    (cd "$EXTRACTED" && "$JAR_CMD" xf "$ALLOY_JAR")
  fi
  echo "Done." >&2
else
  # Pinned to a known-good release. Override via `ALLOY_VERSION=x.y.z ./alloy_run.sh ...`.
  ALLOY_VERSION="${ALLOY_VERSION:-6.2.0}"
  ALLOY_URL="https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v${ALLOY_VERSION}/org.alloytools.alloy.dist.jar"
  echo "Downloading Alloy ${ALLOY_VERSION} from GitHub..." >&2
  curl -fsSL --progress-bar -o "$ALLOY_JAR" "$ALLOY_URL"
  echo "Saved to $ALLOY_JAR" >&2
  echo "Extracting Alloy classes..." >&2
  mkdir -p "$EXTRACTED"
  if [[ "$USE_DOCKER" = true ]]; then
    docker run --rm \
      -v "$ALLOY_JAR:/alloy.jar:ro" \
      -v "$EXTRACTED:/extracted" \
      eclipse-temurin:17-jdk \
      bash -c "cd /extracted && jar xf /alloy.jar"
  else
    (cd "$EXTRACTED" && "$JAR_CMD" xf "$ALLOY_JAR")
  fi
  # Clean up jar after extraction — only extracted classes are needed at runtime
  rm -f "$ALLOY_JAR"
  echo "Done." >&2
fi

# ── 2. strip noncommercial solvers from the extracted cache ─────────────────
# Lingeling is "evaluation and research purposes only" (Biere). The skill's
# AlloyRunner never invokes it, but we also remove the binaries from disk so
# the noncommercial artefacts are never even present in the user's workspace.
# Idempotent: runs safely against fresh or already-stripped caches.
#
# CRITICAL: the SATFactory SPI registration lists every solver class.
# Deleting the PlingelingRef class without removing its line from the SPI
# file makes ServiceLoader throw ServiceConfigurationError, which aborts SPI
# discovery for ALL solvers — so minisat.prover silently falls back to
# SAT4J. Always drop the Lingeling line when stripping the class.

strip_nc_solvers() {
  local removed=0
  local target
  # Alloy's native/ layout is two levels deep: native/<os>/<arch>/<binary>
  for target in \
    "$EXTRACTED"/native/*/*/plingeling \
    "$EXTRACTED"/native/*/*/plingeling.exe \
    "$EXTRACTED"/native/*/*/lingeling \
    "$EXTRACTED"/native/*/*/lingeling.exe \
    "$EXTRACTED"/org/alloytools/solvers/natv/lingeling
  do
    if [[ -e "$target" ]]; then
      rm -rf "$target"
      removed=$((removed + 1))
    fi
  done
  local spi="$EXTRACTED/META-INF/services/kodkod.engine.satlab.SATFactory"
  if [[ -f "$spi" ]] && grep -q 'lingeling' "$spi"; then
    grep -v 'lingeling' "$spi" > "$spi.tmp" && mv "$spi.tmp" "$spi"
    removed=$((removed + 1))
  fi
  if [[ "$removed" -gt 0 ]]; then
    echo "Stripped $removed noncommercial-solver artefact(s) (Lingeling) from cache" >&2
  fi
}

strip_nc_solvers

# ── 2b. reject GPL-licensed components in the extracted cache ───────────────
# Fail-fast if the downloaded Alloy jar ever introduces a GPL-licensed
# component. GPL §7 forbids adding additional restrictions, so any GPL-
# licensed component would constrain how this distribution can be combined
# with differently-licensed work. LGPL (weak copyleft) is fine — it
# permits aggregation. We detect the difference by the header title:
# "GNU GENERAL PUBLIC LICENSE" (GPL) vs. "GNU LESSER GENERAL PUBLIC
# LICENSE" (LGPL). Checks only the first 20 lines so mentions of GPL
# deeper in an LGPL preamble don't false-positive.

reject_gpl_components() {
  local file
  local gpl_found=0
  for file in "$EXTRACTED"/*.txt "$EXTRACTED"/LICENSES/*.txt "$EXTRACTED"/META-INF/LICENSE.txt; do
    [[ -f "$file" ]] || continue
    if head -20 "$file" | grep -qi 'GENERAL PUBLIC LICENSE' \
       && ! head -20 "$file" | grep -qi 'LESSER'; then
      echo "ERROR: $file appears to be GPL-licensed — incompatible with this workspace's licensing posture (GPL §7 forbids combining with differently-licensed work)." >&2
      gpl_found=1
    fi
  done
  if [[ "$gpl_found" -eq 1 ]]; then
    echo "" >&2
    echo "Refusing to proceed. If this is a false positive, inspect the file(s) listed above and adjust reject_gpl_components in alloy_run.sh." >&2
    exit 1
  fi
}

reject_gpl_components

# ── 2c. verify NOTICE enumerates every component in the extracted cache ─────
# If a NOTICE file exists anywhere in the ancestor chain of this script,
# hard-enforce that every bundled component's basename is named in it.
# Otherwise (e.g., in a development workspace without a NOTICE), the check
# is not applicable and silently no-ops. This lets the same function live
# in both the marketplace-plugin tree (where NOTICE is load-bearing) and
# this workspace (where it isn't) without divergence.

verify_notice_completeness() {
  local d="$SCRIPT_DIR"
  local notice_file=""
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -f "$d/NOTICE" ]]; then
      notice_file="$d/NOTICE"
      break
    fi
    d="$(dirname "$d")"
  done
  [[ -n "$notice_file" ]] || return 0
  local missing=0
  local license_file
  local name
  local seen=""
  for license_file in "$EXTRACTED"/*.txt "$EXTRACTED"/LICENSES/*.txt; do
    [[ -f "$license_file" ]] || continue
    name="$(basename "$license_file" .txt)"
    # Skip duplicate basenames (e.g., SAT4J appears at top-level and in LICENSES/).
    case " $seen " in *" $name "*) continue ;; esac
    seen="$seen $name"
    if ! grep -qi "$name" "$notice_file"; then
      echo "ERROR: Component '$name' (from $license_file) is not mentioned in NOTICE — attribution / restrictions drift" >&2
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    echo "" >&2
    echo "Refusing to proceed. Update NOTICE to enumerate the above component(s)." >&2
    exit 1
  fi
}

verify_notice_completeness

# ── 3. write AlloyRunner.java ────────────────────────────────────────────────

# The runner source is embedded as a heredoc below and written to disk only
# if no compiled .class is already cached. Compilation happens in step 4.
# To force a rebuild after editing the heredoc, delete
# .alloy/AlloyRunner.class (or the whole .alloy/ directory).
if [[ -f "$RUNNER_CLASS" ]]; then
  echo "Using cached AlloyRunner.class" >&2
fi

if [[ ! -f "$RUNNER_CLASS" ]]; then
cat > "$RUNNER_SRC" << 'JAVA'
// AlloyRunner v2 — runs both "run" and "check" commands
import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.Collections;
import java.util.Map;

import edu.mit.csail.sdg.alloy4.A4Reporter;
import edu.mit.csail.sdg.alloy4.ErrorWarning;
import edu.mit.csail.sdg.ast.Command;
import edu.mit.csail.sdg.ast.Module;
import edu.mit.csail.sdg.parser.CompUtil;
import edu.mit.csail.sdg.translator.A4Options;
import edu.mit.csail.sdg.translator.A4Solution;
import edu.mit.csail.sdg.translator.TranslateAlloyToKodkod;
import kodkod.engine.satlab.SATFactory;

public class AlloyRunner {
    public static void main(String[] args) throws Exception {
        String path = args.length > 0 ? args[0] : "model.als";
        A4Reporter rep = new A4Reporter() {
            @Override public void warning(ErrorWarning w) {
                System.err.println("WARNING: " + w);
            }
        };
        Module world = CompUtil.parseEverything_fromFile(rep, null, path);
        A4Options opts = new A4Options();
        opts.originalFilename = path;
        // Pin the SAT backend to MiniSat (MIT) with unsat-core support.
        // Prefer the prover variant so UNSAT results carry a minimal core;
        // fall back to SAT4J (LGPL) if the native library is not available
        // on the current platform.
        SATFactory preferred = SATFactory.find("minisat.prover").orElse(null);
        opts.solver = (preferred != null && preferred.isPresent())
            ? preferred
            : SATFactory.DEFAULT;
        System.err.println("Solver: " + opts.solver.id()
            + (opts.solver == preferred ? "" : " (fallback from minisat.prover)"));

        for (Command cmd : world.getAllCommands()) {
            if (cmd.check) {
                System.out.println("===CHECK " + cmd.label + "===");
                A4Solution sol = TranslateAlloyToKodkod.execute_command(
                    rep, world.getAllReachableSigs(), cmd, opts);
                if (!sol.satisfiable()) {
                    System.out.println("NO_COUNTEREXAMPLE");
                } else {
                    System.out.println("COUNTEREXAMPLE");
                    StringWriter sw = new StringWriter();
                    sol.writeXML(new PrintWriter(sw), Collections.emptyList(), Collections.<String,String>emptyMap());
                    System.out.println(sw.toString());
                }
            } else {
                System.out.println("===RUN " + cmd.label + "===");
                A4Solution sol = TranslateAlloyToKodkod.execute_command(
                    rep, world.getAllReachableSigs(), cmd, opts);
                if (!sol.satisfiable()) {
                    System.out.println("UNSAT");
                } else {
                    StringWriter sw = new StringWriter();
                    sol.writeXML(new PrintWriter(sw), Collections.emptyList(), Collections.<String,String>emptyMap());
                    System.out.println(sw.toString());
                }
            }
            System.out.println("===END===");
            System.out.println();
        }
    }
}
JAVA
fi  # end: write AlloyRunner.java only if .class missing

# ── 4. compile AlloyRunner ───────────────────────────────────────────────────

if [[ ! -f "$RUNNER_CLASS" || ( -f "$RUNNER_SRC" && "$RUNNER_SRC" -nt "$RUNNER_CLASS" ) ]]; then
  echo "Compiling AlloyRunner.java..." >&2
  if [[ "$USE_DOCKER" = true ]]; then
    docker run --rm \
      -v "$CACHE:/cache" \
      eclipse-temurin:17-jdk \
      bash -c "javac -cp /cache/extracted /cache/AlloyRunner.java -d /cache"
  else
    "$JAVAC_CMD" -cp "$EXTRACTED" "$RUNNER_SRC" -d "$CACHE"
  fi
  echo "Done." >&2
fi

# ── 5. run model ─────────────────────────────────────────────────────────────

JVM_OPTS=(-Xms256m -Xmx1g)

# Drop kodkod's chatty INFO lines on stderr (LIBRARYPATH scanning, native
# extraction attempts) but surface anything else — in particular, WARN/ERROR
# and any native-library load failures that would silently fall MiniSat back
# to SAT4J.
filter_runner_stderr() {
  grep -vE '^\[main\] INFO kodkod\.' >&2 || true
}

if [[ "$USE_DOCKER" = true ]]; then
  docker run --rm \
    -v "$CACHE:/cache:ro" \
    -v "$(cd "$(dirname "$MODEL")" && pwd)/$(basename "$MODEL"):/model.als:ro" \
    eclipse-temurin:17-jdk \
    bash -c "java ${JVM_OPTS[*]} -cp /cache:/cache/extracted AlloyRunner /model.als" \
    2> >(filter_runner_stderr) \
  | python3 "$SCRIPT_DIR/alloy_format.py"
else
  "$JAVA_CMD" "${JVM_OPTS[@]}" -cp "$CACHE:$EXTRACTED" AlloyRunner "$MODEL" \
    2> >(filter_runner_stderr) \
  | python3 "$SCRIPT_DIR/alloy_format.py"
fi
