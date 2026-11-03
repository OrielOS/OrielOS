#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/first-sign-in, which runs at each sign-in and,
# only the first time, hands later sign-ins the usual welcome screen, opens Set up this PC once and
# suggests a PIN. Each case uses a made-up home folder and --dry-run, with a stub tour program.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/first-sign-in-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/image/system/usr/libexec/orielos/first-sign-in"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""

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

# A fresh home folder with the first sign-in's welcome screen chosen, and a stub tour.
setup() {
    rm -rf "${WORK:?}"/*
    mkdir -p "$WORK/home/.config" "$WORK/bin"
    printf '[KSplash]\nTheme=/usr/share/orielos/first-sign-in/org.orielos.firstsignin\n' >"$WORK/home/.config/ksplashrc"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$WORK/bin/orielos-tour"
    chmod +x "$WORK/bin/orielos-tour"
}

run() {
    OUT="$(HOME="$WORK/home" XDG_CONFIG_HOME="" XDG_STATE_HOME="" ORIELOS_FIRST_UID=0 ORIELOS_TOUR="${TOUR:-$WORK/bin/orielos-tour}" \
        "$SCRIPT" --dry-run 2>&1)" || true
}

has_line() { grep -qxF -- "$1" <<<"$OUT"; }
lacks_line() { ! grep -qxF -- "$1" <<<"$OUT"; }
in_order() { [[ "$(grep -nxF -- "$1" <<<"$OUT" | cut -d: -f1)" -lt "$(grep -nxF -- "$2" <<<"$OUT" | cut -d: -f1)" ]]; }

setup
run
check "the first sign-in removes the welcome screen's setting" has_line "remove $WORK/home/.config/ksplashrc"
check "the first sign-in opens the tour" has_line "open the tour"
check "the tour comes before the PIN suggestion" in_order "open the tour" "suggest a PIN"

setup
mkdir -p "$WORK/home/.local/state/orielos"
touch "$WORK/home/.local/state/orielos/tour-shown"
run
check "a tour already opened once isn't opened again" lacks_line "open the tour"

setup
mkdir -p "$WORK/home/.local/state/orielos"
touch "$WORK/home/.local/state/orielos/first-sign-in-done"
run
check "an account that has signed in before gets nothing" test -z "$OUT"

setup
TOUR="$WORK/bin/no-such-tour" run
check "without the tour the rest still happens" has_line "remove $WORK/home/.config/ksplashrc"
check "without the tour nothing tries to open it" lacks_line "open the tour"

setup
rm "$WORK/home/.config/ksplashrc"
run
check "an account without the first welcome screen keeps its splash setting" lacks_line "remove $WORK/home/.config/ksplashrc"

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
