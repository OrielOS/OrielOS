#!/usr/bin/env bash
# Unit tests for tools/release-changelog.sh: a released version's section holds what Unreleased said
# at the build's commit, and whatever was added or changed after it stays under Unreleased. Prints
# PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/release-changelog-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/release-changelog.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0

# expect <case> <expected CHANGELOG> <CHANGELOG> <released section>
expect() {
    local name="$1" want="$2" got
    printf '%s' "$3" >"$WORK/CHANGELOG.md"
    printf '%s' "$4" >"$WORK/released.md"
    got="$("$TOOL" "$WORK/CHANGELOG.md" "$WORK/released.md" v0.0.7 2026-10-27 2>&1)" || got="exit $?: $got"
    if [[ "$got" == "$want" ]]; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      wanted:\n%s\n      got:\n%s\n' "$name" "$want" "$got"
        FAILED=$((FAILED + 1))
    fi
}

HEAD=$'# Changelog\n\nIntro.\n\n'

expect "Everything released leaves Unreleased empty" \
    "${HEAD}"$'## [Unreleased]\n\n## [0.0.7] - 2026-10-27\n\n### Added\n\n- One.\n- Two.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n- Two.\n' \
    $'\n### Added\n\n- One.\n- Two.\n'

expect "A change merged after the build stays under Unreleased" \
    "${HEAD}"$'## [Unreleased]\n\n### Fixed\n\n- Later.\n\n## [0.0.7] - 2026-10-27\n\n### Added\n\n- One.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n\n### Fixed\n\n- Later.\n' \
    $'### Added\n\n- One.\n'

expect "An entry whose sub-entry changed stays whole under Unreleased" \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Setup.\n  - New text.\n\n## [0.0.7] - 2026-10-27\n\n### Added\n\n- Setup.\n  - Old text.\n- Other.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Setup.\n  - New text.\n- Other.\n' \
    $'### Added\n\n- Setup.\n  - Old text.\n- Other.\n'

expect "Earlier versions' sections are kept after the new one" \
    "${HEAD}"$'## [Unreleased]\n\n## [0.0.7] - 2026-10-27\n\n- Two.\n\n## [0.0.6] - 2026-10-20\n\n- One.' \
    "${HEAD}"$'## [Unreleased]\n\n- Two.\n\n## [0.0.6] - 2026-10-20\n\n- One.' \
    $'- Two.\n'

expect "Windows line endings are read" \
    "${HEAD}"$'## [Unreleased]\n\n## [0.0.7] - 2026-10-27\n\n- One.' \
    "${HEAD}"$'## [Unreleased]\r\n\r\n- One.\r\n' \
    $'- One.\r\n'

expect "An empty released section is refused" \
    "exit 1: error: $WORK/released.md is empty" \
    "${HEAD}"$'## [Unreleased]\n\n- One.\n' \
    $'\n\n'

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
