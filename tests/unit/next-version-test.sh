#!/usr/bin/env bash
# Unit tests for tools/next-version.sh: the version the next published build gets from the tags
# already in the registry, with PATCH rolling over after 10 and MINOR after 100. Prints PASS/FAIL
# per case and exits 1 if any case fails.
#
# Usage: tests/unit/next-version-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/next-version.sh"
PASSED=0
FAILED=0

# expect <case> <expected version> <tags, one per line>
expect() {
    local name="$1" want="$2" got
    got="$(printf '%s' "$3" | "$TOOL" 2>&1)" || got="exit $?: $got"
    if [[ "$got" == "$want" ]]; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      wanted %s, got %s\n' "$name" "$want" "$got"
        FAILED=$((FAILED + 1))
    fi
}

expect "No tags at all gives v0.0.1" v0.0.1 ""
expect "Only channel and date tags gives v0.0.1" v0.0.1 $'testing\nstable\n44.20261026\n44.20261026.2\n'
expect "PATCH goes up by one" v0.0.2 $'testing\nv0.0.1\n44.20261026\n'
expect "The highest version counts, not the last listed" v0.0.8 $'v0.0.7\nv0.0.3\nv0.0.5\n'
expect "PATCH compares as a number" v0.1.0 $'v0.0.9\nv0.0.10\nv0.0.2\n'
expect "v0.0.10 rolls over to v0.1.0" v0.1.0 "v0.0.10"
expect "MINOR compares as a number" v0.10.1 $'v0.9.10\nv0.10.0\nv0.2.5\n'
expect "v0.97.10 rolls over to v0.98.0" v0.98.0 "v0.97.10"
expect "v0.100.10 rolls over to v1.0.0" v1.0.0 "v0.100.10"
expect "MAJOR has no limit" v112.90.3 $'v112.90.2\nv99.100.10\n'
expect "MAJOR outranks MINOR and PATCH" v2.0.1 $'v1.100.10\nv2.0.0\n'
expect "PATCH above 10 isn't a version" v0.0.4 $'v0.0.3\nv0.0.11\n'
expect "MINOR above 100 isn't a version" v0.0.4 $'v0.0.3\nv0.101.0\n'
expect "Leading zeros, missing parts and suffixes aren't versions" v0.0.2 $'v0.0.1\nv0.01.5\nv1.2\nv3.0.0-rc1\n0.5.0\n'
expect "Windows line endings are read" v0.0.6 $'v0.0.5\r\n'

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
