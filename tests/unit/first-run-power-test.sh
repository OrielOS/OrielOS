#!/usr/bin/env bash
# Unit tests for the first-run setup's power helper, image/system/usr/libexec/orielos/first-run-power:
# the PowerDevil settings it writes for each choice, and what it refuses. It works in a scratch
# root folder (ORIELOS_FIRST_RUN_ROOT) with a stand-in for kwriteconfig6 that keeps one
# "<group>/<group> <key>=<value>" line per setting, so it needs no root or KDE.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/first-run-power-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/libexec/orielos/first-run-power"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0

pass() {
    printf 'PASS  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/      /'; fi
    FAILED=$((FAILED + 1))
}

check() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT; settings: $(settings)"; fi
}

# A fresh scratch root with the kwriteconfig6 stand-in.
setup() {
    rm -rf "${WORK:?}/root" "${WORK:?}/bin"
    mkdir -p "$WORK/root/etc" "$WORK/bin"
    cat >"$WORK/bin/kwriteconfig6" <<'SH'
#!/usr/bin/env bash
file="" groups=() key=""
while [[ $# -gt 1 ]]; do
    case "$1" in
        --file) file="$2" ;;
        --group) groups+=("$2") ;;
        --key) key="$2" ;;
    esac
    shift 2
done
group="$(IFS=/; echo "${groups[*]}")"
touch "$file"
grep -v -F -e "$group $key=" "$file" >"$file.new" || true
printf '%s %s=%s\n' "$group" "$key" "$1" >>"$file.new"
mv "$file.new" "$file"
SH
    chmod +x "$WORK/bin/kwriteconfig6"
}

run() {
    RC=0
    OUT="$(ORIELOS_FIRST_RUN_ROOT="$WORK/root" PATH="$WORK/bin:$PATH" bash "$TOOL" "$@" 2>&1)" || RC=$?
}

# The settings written, sorted, one per line.
settings() {
    if [[ -r "$WORK/root/etc/xdg/powerdevilrc" ]]; then sort "$WORK/root/etc/xdg/powerdevilrc"; fi
}

is() {
    [[ "$(settings)" == "$(printf '%s\n' "$@" | sort)" ]]
}

setup
run 30 5
check "sleep after 30 minutes and the screen off after 5, on mains and on battery" is \
    "AC/SuspendAndShutdown AutoSuspendAction=1" "AC/SuspendAndShutdown AutoSuspendIdleTimeoutSec=1800" \
    "AC/Display TurnOffDisplayWhenIdle=true" "AC/Display TurnOffDisplayIdleTimeoutSec=300" \
    "Battery/SuspendAndShutdown AutoSuspendAction=1" "Battery/SuspendAndShutdown AutoSuspendIdleTimeoutSec=1800" \
    "Battery/Display TurnOffDisplayWhenIdle=true" "Battery/Display TurnOffDisplayIdleTimeoutSec=300"
check "the file is readable by everyone" test "$(stat -c %a "$WORK/root/etc/xdg/powerdevilrc")" = 644
check "it says what new users get" test "$OUT" = "first-run-power: new users sleep after 30 min and turn the screen off after 5 min"

setup
run 0 0
check "never sleeping and never turning the screen off" is \
    "AC/SuspendAndShutdown AutoSuspendAction=0" "AC/Display TurnOffDisplayWhenIdle=false" \
    "Battery/SuspendAndShutdown AutoSuspendAction=0" "Battery/Display TurnOffDisplayWhenIdle=false"

setup
run 15 10
run 0 10
check "a second choice replaces the first" is \
    "AC/SuspendAndShutdown AutoSuspendAction=0" "AC/SuspendAndShutdown AutoSuspendIdleTimeoutSec=900" \
    "AC/Display TurnOffDisplayWhenIdle=true" "AC/Display TurnOffDisplayIdleTimeoutSec=600" \
    "Battery/SuspendAndShutdown AutoSuspendAction=0" "Battery/SuspendAndShutdown AutoSuspendIdleTimeoutSec=900" \
    "Battery/Display TurnOffDisplayWhenIdle=true" "Battery/Display TurnOffDisplayIdleTimeoutSec=600"

setup
run 0010 1440
check "leading zeros are decimal, and a day is the longest wait" is \
    "AC/SuspendAndShutdown AutoSuspendAction=1" "AC/SuspendAndShutdown AutoSuspendIdleTimeoutSec=600" \
    "AC/Display TurnOffDisplayWhenIdle=true" "AC/Display TurnOffDisplayIdleTimeoutSec=86400" \
    "Battery/SuspendAndShutdown AutoSuspendAction=1" "Battery/SuspendAndShutdown AutoSuspendIdleTimeoutSec=600" \
    "Battery/Display TurnOffDisplayWhenIdle=true" "Battery/Display TurnOffDisplayIdleTimeoutSec=86400"

setup
: >"$WORK/root/etc/plasma-setup-done"
run 30 5
check "after the setup has finished it refuses with exit 2" test "$RC" -eq 2
check "and writes nothing" test ! -e "$WORK/root/etc/xdg/powerdevilrc"

for args in "" "30" "30 5 1" "1441 5" "5 -1" "x 5" "5 1e3" "12345 5"; do
    setup
    # shellcheck disable=SC2086 # the arguments are split on purpose
    run $args
    check "'$args' is refused with exit 2 and writes nothing" test "$RC" -eq 2 -a ! -e "$WORK/root/etc/xdg/powerdevilrc"
done

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
