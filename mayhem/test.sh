#!/usr/bin/env bash
#
# pyntcloud/mayhem/test.sh — behavioral oracle for daavoo/pyntcloud.
#
# It RUNS the real reader (via the /mayhem/run-cli launcher built by mayhem/build.sh) over the
# bundled diamond.ply test fixture and ASSERTS the decoded point/color/mesh values (known-answer
# test, the same values tests/integration/io/test_from_file.py asserts). This exercises the SAME
# pipeline the fuzzer drives — file read -> pyntcloud.io parse -> points/mesh DataFrames — so a
# no-op/neutered program (no output, or wrong output) FAILS here. It never builds; it only runs the
# pre-built launcher.
#
# Anti-reward-hack note: run-cli lives at /mayhem (a NON-system path), so the verify-repo sabotage
# neuter (_exit(0) on non-system exes) trips it -> empty output -> assertions fail -> detected.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

CLI="$SRC/run-cli"
PLY="$SRC/tests/data/diamond.ply"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASS=0; FAIL=0
check() { # check <name> <condition-rc>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi
}

if [ ! -x "$CLI" ]; then
  echo "missing $CLI — run mayhem/build.sh first" >&2
  emit_ctrf "pyntcloud-knownanswer" 0 1 0; exit 2
fi
if [ ! -f "$PLY" ]; then
  echo "missing $PLY" >&2
  emit_ctrf "pyntcloud-knownanswer" 0 1 0; exit 2
fi

echo "=== reading diamond.ply (value dump to stdout) ==="
OUT="$("$CLI" "$PLY" 2>/dev/null)"
echo "$OUT"

# Known answers for the bundled diamond.ply fixture (see tests/integration/io/test_from_file.py).
grep -q '^X0=0\.5$'        <<<"$OUT"; check "point x[0] = 0.5"      $?
grep -q '^Y0=0\.0$'        <<<"$OUT"; check "point y[0] = 0.0"      $?
grep -q '^Z0=0\.5$'        <<<"$OUT"; check "point z[0] = 0.5"      $?
grep -q '^RED0=255$'       <<<"$OUT"; check "color red[0] = 255"    $?
grep -q '^GREEN0=0$'       <<<"$OUT"; check "color green[0] = 0"    $?
grep -q '^BLUE0=0$'        <<<"$OUT"; check "color blue[0] = 0"     $?
grep -q '^MESH0=0,1,2$'    <<<"$OUT"; check "mesh face[0] = 0,1,2"  $?

emit_ctrf "pyntcloud-knownanswer" "$PASS" "$FAIL" 0
