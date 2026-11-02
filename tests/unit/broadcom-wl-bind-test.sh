#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/broadcom-wl-bind, which gives an older Broadcom
# Wi-Fi card to Broadcom's wl driver: an unbound card gets wl's driver_override, wl is loaded and
# the card probed again; a card ssb already holds is taken from ssb first; a card wl holds is left
# alone; bad arguments fail. It also checks 70-orielos-broadcom-wl.rules lists exactly the cards
# that need wl, and none brcmsmac drives. It works on a scratch sysfs tree (ORIELOS_SYSFS) with a
# stand-in modprobe (ORIELOS_MODPROBE), so it needs no root, Broadcom card or VM. Prints PASS/FAIL
# per case and exits 1 if any case fails.
#
# Usage: tests/unit/broadcom-wl-bind-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/libexec/orielos/broadcom-wl-bind"
RULES="$ROOT/image/system/usr/lib/udev/rules.d/70-orielos-broadcom-wl.rules"
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
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT"; fi
}

SYS="$WORK/sys"
DEV=0000:03:00.0
DEVPATH="$SYS/bus/pci/devices/$DEV"

# A fresh scratch sysfs with one PCI device bound to DRIVER (or to nothing), the drivers' unbind
# and drivers_probe files, and a modprobe that records its arguments.
setup() {
    local driver="${1:-}"
    rm -rf "${WORK:?}/sys" "${WORK:?}/bin" "${WORK:?}/modprobe.log"
    mkdir -p "$DEVPATH" "$SYS/bus/pci/drivers/ssb" "$SYS/bus/pci/drivers/wl" "$WORK/bin"
    : >"$DEVPATH/driver_override"
    : >"$SYS/bus/pci/drivers/ssb/unbind"
    : >"$SYS/bus/pci/drivers/wl/unbind"
    : >"$SYS/bus/pci/drivers_probe"
    if [[ -n "$driver" ]]; then ln -s "../../../bus/pci/drivers/$driver" "$DEVPATH/driver"; fi
    cat >"$WORK/bin/modprobe" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/modprobe.log"
SH
    chmod +x "$WORK/bin/modprobe"
}

run() {
    RC=0
    OUT="$(ORIELOS_SYSFS="$SYS" ORIELOS_MODPROBE="$WORK/bin/modprobe" "$TOOL" "$@" 2>&1)" || RC=$?
}

content_is() { [[ "$(cat "$1" 2>/dev/null)" == "$2" ]]; }

setup
run "$DEV"
check "an unbound card is handled" test "$RC" -eq 0
check "and gets wl as its driver_override" content_is "$DEVPATH/driver_override" wl
check "wl is loaded by name" content_is "$WORK/modprobe.log" wl
check "the card is probed again" content_is "$SYS/bus/pci/drivers_probe" "$DEV"
check "nothing is unbound" content_is "$SYS/bus/pci/drivers/ssb/unbind" ""

setup ssb
run "$DEV"
check "a card ssb holds is handled" test "$RC" -eq 0
check "and is taken from ssb first" content_is "$SYS/bus/pci/drivers/ssb/unbind" "$DEV"
check "then gets wl" content_is "$DEVPATH/driver_override" wl

setup wl
run "$DEV"
check "a card wl holds is fine" test "$RC" -eq 0
check "and is left alone" content_is "$SYS/bus/pci/drivers_probe" ""
check "without loading wl again" test ! -e "$WORK/modprobe.log"

setup
run
check "no argument fails" test "$RC" -ne 0
run "../../etc"
check "something that isn't a PCI address fails" test "$RC" -ne 0
run 0000:04:00.0
check "a device that isn't there fails" test "$RC" -ne 0
check "and changes nothing" content_is "$DEVPATH/driver_override" ""

# The rule's IDs: exactly the cards that only work with wl, none of brcmsmac's.
expected="0x4311 0x4312 0x4315 0x4328 0x4329 0x432a 0x432b 0x432c 0x432d 0x4331 0x4358 0x4359 0x4360 0x4365 0x43a0 0x43b1"
ids="$(grep -o 'ATTR{device}=="[^"]*"' "$RULES" | sed 's/.*=="//; s/"$//' | tr '|' '\n' | sort | xargs)"
OUT="$ids"
check "the rule lists exactly the cards that need wl" test "$ids" == "$expected"
no_brcmsmac_ids() { ! grep -qE '0x4727|0x0576|0x4353|0x4357' <<<"$ids"; }
check "and none that brcmsmac drives" no_brcmsmac_ids
check "the rule sets driver_override before running the helper" grep -q 'ATTR{driver_override}="wl", RUN+="/usr/libexec/orielos/broadcom-wl-bind %k"' "$RULES"

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
