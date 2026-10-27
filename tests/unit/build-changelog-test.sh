#!/usr/bin/env bash
# Unit tests for tools/build-changelog.sh: a build's notes hold the Unreleased entries added or
# changed since the previous build, under their headings. Prints PASS/FAIL per case and exits 1 if
# any case fails.
#
# Usage: tests/unit/build-changelog-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/build-changelog.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0

# expect <case> <expected notes> <previous CHANGELOG> <current CHANGELOG>
expect() {
    local name="$1" want="$2" got
    printf '%s' "$3" >"$WORK/previous.md"
    printf '%s' "$4" >"$WORK/current.md"
    got="$("$TOOL" "$WORK/previous.md" "$WORK/current.md" 2>&1)" || got="exit $?: $got"
    if [[ "$got" == "$want" ]]; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      wanted:\n%s\n      got:\n%s\n' "$name" "$want" "$got"
        FAILED=$((FAILED + 1))
    fi
}

HEAD=$'# Changelog\n\nIntro.\n\n'
OLDER=$'\n## [0.0.7] - 2026-10-27\n\n### Added\n\n- Released.\n'

expect "A new entry is listed under its heading" \
    $'### Added\n\n- Two.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n'"${OLDER}" \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n- Two.\n'"${OLDER}"

expect "Only headings with new entries are listed, in the CHANGELOG's order" \
    $'### Added\n\n- New feature.\n\n### Fixed\n\n- New fix.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Old.\n\n### Changed\n\n- Same.\n'"${OLDER}" \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Old.\n- New feature.\n\n### Changed\n\n- Same.\n\n### Fixed\n\n- New fix.\n'"${OLDER}"

expect "An entry whose text changed counts as new" \
    $'### Changed\n\n- Better wording.' \
    "${HEAD}"$'## [Unreleased]\n\n### Changed\n\n- Wording.\n' \
    "${HEAD}"$'## [Unreleased]\n\n### Changed\n\n- Better wording.\n'

expect "An entry with a new sub-entry is listed whole" \
    $'### Added\n\n- Pages:\n  - Download;\n  - News.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Pages:\n  - Download;\n- Other.\n' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Pages:\n  - Download;\n  - News.\n- Other.\n'

expect "Nothing new prints nothing" \
    "" \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n'

expect "With no previous CHANGELOG everything under Unreleased is new" \
    $'### Added\n\n- One.' \
    "" \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- One.\n'"${OLDER}"

expect "Entries that moved into a released version aren't listed" \
    $'### Fixed\n\n- After the release.' \
    "${HEAD}"$'## [Unreleased]\n\n### Added\n\n- Released.\n' \
    "${HEAD}"$'## [Unreleased]\n\n### Fixed\n\n- After the release.\n'"${OLDER}"

expect "Text that isn't an entry is kept" \
    $'Read this first.\n\n### Added\n\n- One.' \
    "${HEAD}"$'## [Unreleased]\n' \
    "${HEAD}"$'## [Unreleased]\n\nRead this first.\n\n### Added\n\n- One.\n'

expect "Windows line endings are read" \
    $'### Added\n\n- Two.' \
    "${HEAD}"$'## [Unreleased]\r\n\r\n### Added\r\n\r\n- One.\r\n' \
    "${HEAD}"$'## [Unreleased]\r\n\r\n### Added\r\n\r\n- One.\r\n- Two.\r\n'

expect "A CHANGELOG without Unreleased is refused" \
    "exit 1: error: $WORK/current.md has no Unreleased section" \
    "" \
    "${HEAD}${OLDER}"

if "$TOOL" --help | grep -q '^Usage: tools/build-changelog.sh PREVIOUS CURRENT$'; then
    printf 'PASS  %s\n' "--help prints the usage"
    PASSED=$((PASSED + 1))
else
    printf 'FAIL  %s\n' "--help prints the usage"
    FAILED=$((FAILED + 1))
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
