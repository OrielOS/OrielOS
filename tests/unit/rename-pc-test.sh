#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/rename-pc, which renames this PC for the About
# settings page: a good name goes to hostnamectl, a name that can't be used is refused before
# hostnamectl runs, hostnamectl's own failure is passed on, and without root it refuses. It runs the
# real script against a scratch directory (ORIELOS_RENAME_ROOT) with a stand-in hostnamectl, so it
# needs no root, VM or network. Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/rename-pc-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/libexec/orielos/rename-pc"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0
R="$WORK/root"
CALLS="$WORK/calls"

pass() {
    printf 'PASS  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/      /'; fi
    FAILED=$((FAILED + 1))
}

# check <name> <condition...>: PASS if the command succeeds, else FAIL with the last output.
check() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT"; fi
}

# A fresh scratch root with a hostnamectl that logs its arguments, and fails when $WORK/fail exists,
# writing a line of detail and then the message in it, or nothing when it's empty.
setup() {
    rm -rf "${WORK:?}/root" "$CALLS" "$WORK/fail"
    mkdir -p "$R/usr/bin"
    cat >"$R/usr/bin/hostnamectl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CALLS"
if [[ -s "$WORK/fail" ]]; then
    echo "Some detail first" >&2
    cat "$WORK/fail" >&2
fi
if [[ -e "$WORK/fail" ]]; then exit 1; fi
SH
    chmod +x "$R/usr/bin/hostnamectl"
}

run() {
    RC=0
    OUT="$(ORIELOS_RENAME_ROOT="$R" bash "$TOOL" "$@" 2>&1)" || RC=$?
}

calls() { if [[ -e "$CALLS" ]]; then cat "$CALLS"; fi; }

setup
run games-pc
check "a good name succeeds" test "$RC" -eq 0
check "a good name goes to hostnamectl hostname" test "$(calls)" == "hostname games-pc"

setup
run "Games-PC-2"
check "letters of either case, numbers and hyphens are good" test "$RC" -eq 0 -a "$(calls)" == "hostname Games-PC-2"

setup
run "$(printf 'a%.0s' {1..63})"
check "63 characters are good" test "$RC" -eq 0

# Each name that can't be used, and part of the reason given for it.
while IFS='|' read -r name reason; do
    setup
    run "$name"
    check "\"$name\" is refused" test "$RC" -eq 2
    check "\"$name\" says why" grep -q "^rename-pc: .*$reason" <<<"$OUT"
    check "\"$name\" doesn't run hostnamectl" test -z "$(calls)"
done <<EOF
|enter a name
$(printf 'a%.0s' {1..64})|up to 63 characters
games pc|spaces
games_pc|only letters A to Z
café|only letters A to Z
games;reboot|only letters A to Z
-games|start or end with a hyphen
games-|start or end with a hyphen
EOF

setup
run
check "no name is wrong usage" test "$RC" -eq 2 -a -z "$(calls)"
run one two
check "two names are wrong usage" test "$RC" -eq 2 -a -z "$(calls)"

setup
printf 'Could not set hostname: Access denied\n' >"$WORK/fail"
run games-pc
check "a hostnamectl failure fails" test "$RC" -eq 1
check "a hostnamectl failure ends with hostnamectl's message" \
    test "$(tail -n 1 <<<"$OUT")" == "rename-pc: Could not set hostname: Access denied"

setup
: >"$WORK/fail"
run games-pc
check "a silent hostnamectl failure still says what failed" \
    test "$RC" -eq 1 -a "$(tail -n 1 <<<"$OUT")" == "rename-pc: hostnamectl failed to set the name"

# Without the test root, it needs root. As root, run it as nobody to see that.
RC=0
if [[ "$EUID" -ne 0 ]]; then
    OUT="$(env -u ORIELOS_RENAME_ROOT bash "$TOOL" games-pc 2>&1)" || RC=$?
    check "it refuses without root" test "$RC" -eq 1 -a "$OUT" == "rename-pc: run rename-pc as root, for example with pkexec"
elif command -v setpriv >/dev/null 2>&1; then
    # A copy nobody can read: the checkout may be in root's home, which nobody can't open.
    OPEN="$(mktemp -d)"
    chmod 0755 "$OPEN"
    install -m 0755 "$TOOL" "$OPEN/rename-pc"
    OUT="$(cd / && env -u ORIELOS_RENAME_ROOT setpriv --reuid=65534 --regid=65534 --clear-groups bash "$OPEN/rename-pc" games-pc 2>&1)" || RC=$?
    rm -rf "$OPEN"
    check "it refuses without root" test "$RC" -eq 1 -a "$OUT" == "rename-pc: run rename-pc as root, for example with pkexec"
else
    printf 'SKIP  it refuses without root (running as root, without setpriv)\n'
fi

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
