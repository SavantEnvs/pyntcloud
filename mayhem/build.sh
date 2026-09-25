#!/usr/bin/env bash
#
# pyntcloud/mayhem/build.sh — build the Atheris fuzz target for daavoo/pyntcloud.
#
# This is a PYTHON (Atheris/libFuzzer) project, so the "build" is:
#   1) install pyntcloud + atheris + the readers' deps, OFFLINE, from the wheelhouse the Dockerfile
#      baked into /opt/toolchains/python/wheelhouse (air-gapped, re-runnable — SPEC §6.5);
#   2) compile tiny ELF launchers (launcher.c) so the Mayhem target `cmd` is a native executable
#      (Mayhem rejects script targets; fuzz-smoke checks the ELF magic). Each launcher exec's
#      `python3 <script> "$@"`, forwarding libFuzzer flags to Atheris:
#        - /mayhem/fuzz_parser             : the Mayhem libFuzzer target (Atheris iterates).
#        - /mayhem/fuzz_parser-standalone  : run-once reproducer (Atheris replays one file arg).
#        - /mayhem/run-cli                 : the oracle runner mayhem/test.sh drives (show_cloud.py).
#
# NOTE on sanitizers: the fuzzed code is Python; coverage/instrumentation come from Atheris
# (atheris.instrument_imports), not from clang $SANITIZER_FLAGS — those apply to native C/C++ code,
# of which this project has none. We still thread $DEBUG_FLAGS into the launcher compile so the
# spec's debug-info contract (DWARF < 4) holds on every emitted ELF.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) so an explicit empty --build-arg SANITIZER_FLAGS= builds without sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS: explicit DWARF-3 so Mayhem triage can read symbols (clang-19's plain -g emits DWARF-5).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${SRC:=/mayhem}"
: "${WHEELHOUSE:=/opt/toolchains/python/wheelhouse}"
# pyntcloud uses setuptools_scm for its version; pin a value so the offline build never needs git
# tags (and stays deterministic across the air-gapped re-run).
: "${SETUPTOOLS_SCM_PRETEND_VERSION:=0.3.1}"
export SANITIZER_FLAGS DEBUG_FLAGS CC SRC WHEELHOUSE SETUPTOOLS_SCM_PRETEND_VERSION
OUT=/mayhem

cd "$SRC"

# ── 1) Python deps — OFFLINE from the baked wheelhouse (idempotent; "already satisfied" on re-run) ──
# atheris: the fuzzing engine. setuptools/setuptools_scm/wheel: pyntcloud's PEP-517 build backend
# (needed to install the source with build isolation disabled). numpy/scipy/pandas: core runtime.
# laspy/lazrs: the .las/.laz reader backend (so that path is fuzzed, not import-skipped).
PIP="python3 -m pip install --user --break-system-packages"
DEPS="atheris setuptools setuptools_scm wheel numpy scipy pandas laspy lazrs"
if [ -d "$WHEELHOUSE" ]; then
  $PIP --no-index --find-links "$WHEELHOUSE" $DEPS
  $PIP --no-index --find-links "$WHEELHOUSE" --no-build-isolation .
else
  # First build only (no wheelhouse yet): allow the network. The Dockerfile bakes the wheelhouse so
  # the air-gapped PATCH re-run takes the --no-index branch above.
  $PIP $DEPS
  $PIP --no-build-isolation .
fi

# Sanity: the harnessed modules must import.
python3 -c 'import atheris, pyntcloud, pyntcloud.io' \
  || { echo "FATAL: pyntcloud failed to import" >&2; exit 1; }

# ── 2) Native ELF launchers ─────────────────────────────────────────────────────────────────────
# Sanitizing a ~30-line exec shim is pointless (and would drag the ASan runtime into the python
# child), so the launcher is built WITHOUT $SANITIZER_FLAGS but WITH $DEBUG_FLAGS (DWARF-3) to
# satisfy the debug-info contract. The Python code itself is instrumented by Atheris.
"$CC" $DEBUG_FLAGS -O1 \
    -DHARNESS_PATH="\"$SRC/mayhem/fuzz_parser.py\"" \
    -o "$OUT/fuzz_parser" "$SRC/mayhem/launcher.c"

# Standalone run-once reproducer: same binary (Atheris replays a single file argument).
cp -f "$OUT/fuzz_parser" "$OUT/fuzz_parser-standalone"

# CLI runner for the test oracle: exec's show_cloud.py. Because it lives at a NON-system path, the
# anti-reward-hack neuter (LD_PRELOAD _exit(0) on non-system exes) trips it, making mayhem/test.sh
# a genuinely behavioral oracle.
"$CC" $DEBUG_FLAGS -O1 \
    -DHARNESS_PATH="\"$SRC/mayhem/show_cloud.py\"" \
    -o "$OUT/run-cli" "$SRC/mayhem/launcher.c"

echo "build.sh complete:"
ls -la "$OUT/fuzz_parser" "$OUT/fuzz_parser-standalone" "$OUT/run-cli"
