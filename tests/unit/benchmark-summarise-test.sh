#!/usr/bin/env bash
# Unit tests for tests/benchmark/summarise.py, which turns MangoHud's frame logs into average FPS
# and 1% lows. Builds logs with known frame times and checks the numbers.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/benchmark-summarise-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/tests/benchmark/summarise.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0

check() {
    local name="$1"
    shift
    if "$@"; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      output: %s\n' "$name" "$OUT"
        FAILED=$((FAILED + 1))
    fi
}

# A MangoHud log: log <file> <slow frame in ms>, with 99 frames of 10 ms and one slow one.
log() {
    {
        printf 'os,cpu,gpu,ram,kernel,driver,cpuscheduler\n'
        printf 'OrielOS,CPU,GPU,32,7.2,595,\n'
        printf 'fps,frametime,cpu_load,gpu_load,cpu_temp,gpu_temp,elapsed\n'
        for _ in $(seq 99); do printf '100,10.0,20,90,50,60,1\n'; done
        printf '20,%s,20,90,50,60,1\n' "$2"
    } >"$1"
}

run() {
    RC=0
    OUT="$(python3 "$SCRIPT" "$@" 2>&1)" || RC=$?
}

log "$WORK/Game_2026-11-02_10-00-00.csv" 50.0
log "$WORK/Game_2026-11-02_10-05-00.csv" 50.0
run "$WORK/Game_2026-11-02_10-00-00.csv" "$WORK/Game_2026-11-02_10-05-00.csv"
check "two runs of one game are grouped" grep -q '^Game: 2 runs' <<<"$OUT"
# 100 frames over 1040 ms: 96.2 FPS; the slowest 1 % (one frame of 50 ms): 20 FPS.
check "average FPS is frames over time" grep -q 'average 96.2 FPS' <<<"$OUT"
check "the 1% low is the slowest 1% of frames" grep -q '1% low 20.0 FPS' <<<"$OUT"
check "identical runs don't spread" grep -q 'spread 0.0 %' <<<"$OUT"

log "$WORK/Other_2026-11-02_11-00-00.csv" 10.0
run --markdown "$WORK/Other_2026-11-02_11-00-00.csv"
check "--markdown prints a table row" grep -q '^| Other | 1 | 100.0 | 100.0 | 0.0 % |$' <<<"$OUT"

printf 'not a log\n' >"$WORK/broken.csv"
run "$WORK/broken.csv"
check "a file without frame times is skipped, and nothing left fails" test "$RC" -eq 1

run
check "no files is a usage error" test "$RC" -eq 2

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
