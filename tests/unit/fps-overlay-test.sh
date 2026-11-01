#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/fps-overlay, the FPS overlay's switch, its
# options and Windows + G. Each case runs it against a made-up home folder, without the session or
# Flatpak (ORIELOS_FPS_TEST_HOME).
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/fps-overlay-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/image/system/usr/libexec/orielos/fps-overlay"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0
CONF="$WORK/home/.config/MangoHud/MangoHud.conf"
ENV_FILE="$WORK/home/.config/environment.d/90-orielos-fps-overlay.conf"

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

run() {
    RC=0
    OUT="$(ORIELOS_FPS_TEST_HOME="$WORK/home" bash "$SCRIPT" "$@" 2>&1)" || RC=$?
}

status_is() {
    run status
    grep -qx "$1" <<<"$OUT"
}

rm -rf "${WORK:?}/home"
status_is enabled=off
check "the overlay starts off" test "$RC" -eq 0
run toggle
check "Windows + G while it's off says so and changes nothing" test "$OUT" == off -a ! -e "$CONF"

run on
check "on sets MANGOHUD=1 for the session" grep -qx 'MANGOHUD=1' "$ENV_FILE"
check "and writes MangoHud's settings, hidden" grep -qx 'no_display' "$CONF"
check "status says it's on and hidden" status_is enabled=on
check "status says hidden" status_is shown=no
check "it shows the frame rate" grep -qx 'fps' "$CONF"

run toggle
check "Windows + G shows it" test "$OUT" == yes
check "by dropping no_display" bash -c "! grep -qx no_display '$CONF'"
run toggle
check "and hides it again" grep -qx 'no_display' "$CONF"

run option frametime on
check "the frame time option shows frame time" grep -qx 'frametime' "$CONF"
check "and status says so" status_is frametime=on
run option stats on
check "the stats option shows processor and graphics card use" grep -qx 'cpu_stats' "$CONF"
check "and keeps the frame time" grep -qx 'frametime' "$CONF"
check "and keeps it hidden" grep -qx 'no_display' "$CONF"
run option frametime off
check "an option turns off again" bash -c "! grep -qx frametime '$CONF'"

run option colour on
check "an unknown option is refused with exit 2" test "$RC" -eq 2
run option stats maybe
check "a value other than on or off is refused with exit 2" test "$RC" -eq 2

run off
check "off removes MANGOHUD=1" test ! -e "$ENV_FILE"
check "status says it's off" status_is enabled=off
run toggle
check "Windows + G does nothing once it's off" test "$OUT" == off

run nonsense
check "an unknown command is refused with exit 2" test "$RC" -eq 2

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
