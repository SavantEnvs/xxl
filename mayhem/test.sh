#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the upstream XXL selftest built by mayhem/build.sh (/mayhem/xxl-test),
# THEN layer known-answer (KAT) probes on top: fixed one-line XXL programs whose exact stdout
# is asserted via grep -qxF against the CLEAN (non-sanitized, non-watchdogged) /mayhem/xxl-test
# binary — the honest oracle build.
#
# XXL's own test suite is its built-in selftest: built -DDEBUG and invoked with no args, main() ->
# args() -> selftest() runs test_basics/nest/ctx/eval/logic/semantics. Each check is an ASSERT()
# that raises SIGABRT + exit(1) on failure and the runner prints "TESTS PASSED" only when all six
# groups pass. This asserts real behavior/values (not just exit status): if the interpreter is
# neutered to exit(0), no group runs and "TESTS PASSED" never prints -> this oracle FAILS.
#
# The KAT probes go further: each feeds a fixed program (arithmetic, string concatenation, a list
# reduction, a list reorder) to /mayhem/xxl-test and asserts the EXACT computed stdout value, lifted
# from a real interactive run of the built binary -- so a neutered/no-op binary (empty stdout) fails
# every one of them too.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

RUNNER=/mayhem/xxl-test
if [ ! -x "$RUNNER" ]; then
  echo "test runner $RUNNER missing — build.sh must produce it" >&2
  emit_ctrf "xxl-selftest+kat" 0 1
  exit 1
fi

TOTAL_PASSED=0
TOTAL_FAILED=0

# ---- 1) upstream built-in selftest -----------------------------------------------------
# The six built-in test groups (each aborts the process on the first failed ASSERT).
# NB: do NOT name this GROUPS — that's a readonly bash special variable.
TEST_GROUPS="TEST_BASICS TEST_NEST TEST_CTX TEST_EVAL TEST_LOGIC TEST_SEMANTICS"
SELFTEST_TOTAL=$(echo $TEST_GROUPS | wc -w)

# No args -> selftest; feed /dev/null on stdin so the post-test repl reads EOF and exits.
out="$("$RUNNER" </dev/null 2>&1)"
echo "$out"

passed=0
for g in $TEST_GROUPS; do
  echo "$out" | grep -q "^$g$" && passed=$((passed+1))
done

if echo "$out" | grep -q "^TESTS PASSED$" && ! echo "$out" | grep -q "^ASSERT:"; then
  TOTAL_PASSED=$((TOTAL_PASSED + SELFTEST_TOTAL))
else
  # A group that ran but did not reach TESTS PASSED means an ASSERT fired -> at least one failure.
  failed=$((SELFTEST_TOTAL - passed))
  [ "$failed" -lt 1 ] && failed=1
  TOTAL_PASSED=$((TOTAL_PASSED + passed))
  TOTAL_FAILED=$((TOTAL_FAILED + failed))
fi

# ---- 2) known-answer probes -------------------------------------------------------------
# Each is an UNCONDITIONAL assertion: a missing script or a mismatched/empty value is a
# FAILURE, never a skip. Fixed program -> exact computed stdout value.
kat() {
  local name="$1" script="$2" expected="$3"
  if [ ! -f "$script" ]; then
    echo "KAT_$name: FAIL (missing fixture $script)"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    return
  fi
  local got
  got="$("$RUNNER" "$script" </dev/null 2>&1)"
  if printf '%s\n' "$got" | grep -qxF "$expected"; then
    echo "KAT_$name=$expected (pass)"
    TOTAL_PASSED=$((TOTAL_PASSED + 1))
  else
    echo "KAT_$name: FAIL (expected exact line '$expected', got '$got')"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
  fi
}

kat ARITH  "$SRC/mayhem/xxl/kat/arith.xxl"  "20"
kat CONCAT "$SRC/mayhem/xxl/kat/concat.xxl" "abcd"
kat SUM    "$SRC/mayhem/xxl/kat/sum.xxl"    "15"
kat REV    "$SRC/mayhem/xxl/kat/rev.xxl"    "(3,2,1)"

emit_ctrf "xxl-selftest+kat" "$TOTAL_PASSED" "$TOTAL_FAILED"
