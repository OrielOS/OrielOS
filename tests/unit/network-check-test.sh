#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/network-check, the network troubleshooter's
# checks and fixes, and restart-networking, the one fix that needs an administrator. Each case runs
# the real script against a scratch sysfs and configuration (ORIELOS_NETWORK_CHECK_ROOT) with
# stand-ins for nmcli, rfkill, ip, ping, getent, timeout, nm-online, resolvectl, xdg-open, pkexec,
# systemctl and kwriteconfig6 that answer from files and log their arguments, so it needs no root,
# network or VM. Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/network-check-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/libexec/orielos/network-check"
RESTART="$ROOT/image/system/usr/libexec/orielos/restart-networking"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
ERR=""
RC=0
S="$WORK/stub"
R="$WORK/root"

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
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT $ERR"; fi
}

# A PC on Wi-Fi where everything works: NetworkManager running, one Wi-Fi adapter connected with
# an address, a router that answers, names that resolve and full internet access. Cases change the
# stand-ins' answer files to break one thing.
setup() {
    rm -rf "${WORK:?}/stub" "${WORK:?}/root" "${WORK:?}/bin" "${WORK:?}/home"
    mkdir -p "$S" "$WORK/bin" "$WORK/home/.config" "$R/sys/class/rfkill/rfkill0" "$R/usr/lib/NetworkManager/conf.d"
    printf 'wlo1:wifi:connected\np2p-dev-wlo1:wifi-p2p:disconnected\nlo:loopback:connected (externally)\n' >"$S/devices"
    echo enabled >"$S/radio-wifi"
    echo connected >"$S/state"
    printf '802-11-wireless\nloopback\n' >"$S/connections"
    printf 'IP4.ADDRESS[1]:192.168.1.20/24\nIP6.ADDRESS[1]:fe80\\:\\:1234/64\n' >"$S/addresses"
    echo 'default via 192.168.1.1 dev wlo1 proto dhcp src 192.168.1.20 metric 600' >"$S/route4"
    : >"$S/route6"
    echo full >"$S/connectivity"
    echo wlan >"$R/sys/class/rfkill/rfkill0/type"
    echo 0 >"$R/sys/class/rfkill/rfkill0/soft"
    echo 0 >"$R/sys/class/rfkill/rfkill0/hard"
    : >"$S/calls"

    cat >"$WORK/bin/nmcli" <<'SH'
#!/usr/bin/env bash
printf 'nmcli %s\n' "$*" >>"$STUB_DIR/calls"
if [[ -e "$STUB_DIR/nm-stopped" ]]; then
    echo "Error: NetworkManager is not running." >&2
    exit 8
fi
case "$*" in
    "-t -f RUNNING general") echo running ;;
    "-t -f DEVICE,TYPE,STATE device") cat "$STUB_DIR/devices" ;;
    "radio wifi") cat "$STUB_DIR/radio-wifi" ;;
    "-t -f STATE general") cat "$STUB_DIR/state" ;;
    "-t -f TYPE connection show") cat "$STUB_DIR/connections" ;;
    "-t -f IP4.ADDRESS,IP6.ADDRESS device show "*) cat "$STUB_DIR/addresses" ;;
    "-t networking connectivity check") cat "$STUB_DIR/connectivity" ;;
    "-g GENERAL.CON-UUID device show "*) cat "$STUB_DIR/uuid" 2>/dev/null || true ;;
esac
SH
    cat >"$WORK/bin/ip" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == -6 ]]; then cat "$STUB_DIR/route6"; else cat "$STUB_DIR/route4"; fi
SH
    cat >"$WORK/bin/ping" <<'SH'
#!/usr/bin/env bash
printf 'ping %s\n' "$*" >>"$STUB_DIR/calls"
[[ ! -e "$STUB_DIR/router-down" ]]
SH
    cat >"$WORK/bin/getent" <<'SH'
#!/usr/bin/env bash
[[ ! -e "$STUB_DIR/dns-down" ]]
SH
    cat >"$WORK/bin/timeout" <<'SH'
#!/usr/bin/env bash
shift
exec "$@"
SH
    # The commands the fixes run: they log their arguments and succeed, unless <name>-fails exists.
    local cmd
    for cmd in rfkill nm-online resolvectl xdg-open pkexec systemctl kwriteconfig6; do
        cat >"$WORK/bin/$cmd" <<SH
#!/usr/bin/env bash
printf '$cmd %s\n' "\$*" >>"\$STUB_DIR/calls"
if [[ -e "\$STUB_DIR/$cmd-fails" ]]; then
    echo "$cmd failed" >&2
    exit 1
fi
SH
    done
    chmod +x "$WORK/bin"/*
}

run() {
    RC=0
    OUT="$(STUB_DIR="$S" ORIELOS_NETWORK_CHECK_ROOT="$R" PATH="$WORK/bin:$PATH" HOME="$WORK/home" XDG_CONFIG_HOME="" \
        bash "$TOOL" "$@" 2>"$WORK/stderr")" || RC=$?
    ERR="$(<"$WORK/stderr")"
}

# The results in order, comma-separated: ok,ok,problem,skipped,...
results() { jq -r .result <<<"$OUT" | paste -sd, -; }
# One field of one check's line: field <check> <field>
field() { jq -r --arg check "$1" "select(.check == \$check) | .$2" <<<"$OUT"; }
called() { grep -qxF -- "$1" "$S/calls"; }
not_called() { ! grep -q -- "$1" "$S/calls"; }
exited() { [[ "$RC" -eq "$1" ]]; }
# The run succeeded and called every one of these commands.
succeeded_calling() {
    local call
    exited 0 || return 1
    for call in "$@"; do called "$call" || return 1; done
}
# Every check is ok, and <check> for this reason: all_ok [<check> <reason>]
all_ok() {
    exited 0 && [[ "$(results)" == "ok,ok,ok,ok,ok,ok,ok" ]] || return 1
    [[ $# -eq 0 || "$(field "$1" reason)" == "$2" ]]
}

# The first problem is <check>, with this reason and fix, and every check after it is skipped:
#   first_problem <results> <check> <reason> <fix>
first_problem() {
    exited 0 && [[ "$(results)" == "$1" && "$(field "$2" reason)" == "$3" && "$(field "$2" fix)" == "$4" ]] &&
        [[ -n "$(field "$2" message)" ]]
}

setup
run
check "all good: every check is ok" all_ok
check "all good: seven checks, in order" \
    test "$(jq -r .check <<<"$OUT" | paste -sd, -)" == "adapter,radio,connected,address,gateway,dns,internet"
check "all good: every line has the five fields" \
    test "$(jq -c 'keys' <<<"$OUT" | sort -u)" == '["check","fix","message","reason","result"]'
check "all good: pings the router" called "ping -c 2 -W 2 192.168.1.1"

setup
echo disabled >"$S/radio-wifi"
echo 1 >"$R/sys/class/rfkill/rfkill0/soft"
printf 'wlo1:wifi:unavailable\n' >"$S/devices"
echo disconnected >"$S/state"
run
check "Wi-Fi off: the radio is the problem, fixed by wifi-on, the rest skipped" \
    first_problem "ok,problem,skipped,skipped,skipped,skipped,skipped" radio wifi-off wifi-on
check "Wi-Fi off: skipped checks carry no reason or fix" \
    test "$(field internet reason)$(field internet fix)$(field internet message)" == ""

setup
echo 1 >"$R/sys/class/rfkill/rfkill0/hard"
echo disabled >"$S/radio-wifi"
run
check "hard block: no automatic fix, points to the switch" \
    first_problem "ok,problem,skipped,skipped,skipped,skipped,skipped" radio hard-blocked ""

setup
mkdir -p "$R/sys/class/rfkill/rfkill1"
echo bluetooth >"$R/sys/class/rfkill/rfkill1/type"
echo 1 >"$R/sys/class/rfkill/rfkill1/soft"
echo 1 >"$R/sys/class/rfkill/rfkill0/soft"
echo disabled >"$S/radio-wifi"
run
check "airplane mode (every radio blocked): fixed by airplane-off" \
    first_problem "ok,problem,skipped,skipped,skipped,skipped,skipped" radio airplane airplane-off

setup
printf '[General]\nAirplaneModeEnabled=true\n' >"$WORK/home/.config/plasma-nm"
echo disabled >"$S/radio-wifi"
run
check "airplane mode (Plasma's): fixed by airplane-off" \
    first_problem "ok,problem,skipped,skipped,skipped,skipped,skipped" radio airplane airplane-off

setup
printf '[General]\nAirplaneModeEnabled=true\n' >"$WORK/home/.config/plasma-nm"
run
check "a stale airplane mode setting with Wi-Fi on isn't a problem" all_ok radio radio-ok

setup
printf 'enp3s0:ethernet:connected\nwlo1:wifi:unavailable\n' >"$S/devices"
echo disabled >"$S/radio-wifi"
run
check "connected by cable: Wi-Fi being off doesn't matter" \
    all_ok radio radio-not-needed
check "connected by cable: both adapters are found" test "$(field adapter reason)" == adapter-both

setup
printf 'wlo1:wifi:disconnected\n' >"$S/devices"
echo disconnected >"$S/state"
run
check "not connected, with a saved Wi-Fi network: fixed by reconnect" \
    first_problem "ok,ok,problem,skipped,skipped,skipped,skipped" connected disconnected reconnect

setup
printf 'wlo1:wifi:disconnected\n' >"$S/devices"
echo disconnected >"$S/state"
printf 'loopback\n' >"$S/connections"
run
check "not connected, no saved network: no fix, choose one in Quick Settings" \
    first_problem "ok,ok,problem,skipped,skipped,skipped,skipped" connected no-saved-network ""

setup
printf 'enp3s0:ethernet:unavailable\n' >"$S/devices"
echo disconnected >"$S/state"
run
check "no cable plugged in: no fix" \
    first_problem "ok,ok,problem,skipped,skipped,skipped,skipped" connected no-cable ""

setup
echo asleep >"$S/state"
run
check "networking turned off: fixed by networking-on" \
    first_problem "ok,ok,problem,skipped,skipped,skipped,skipped" connected networking-off networking-on

setup
printf 'IP4.ADDRESS[1]:169.254.10.2/16\nIP6.ADDRESS[1]:fe80\\:\\:1234/64\n' >"$S/addresses"
run
check "no address (only link-local ones): fixed by reconnect" \
    first_problem "ok,ok,ok,problem,skipped,skipped,skipped" address no-address reconnect

setup
printf 'IP4.ADDRESS[1]:\nIP6.ADDRESS[1]:2001\\:db8\\:\\:20/64\n' >"$S/addresses"
run
check "an IPv6 address alone is enough" test "$(field address result)" == ok

setup
touch "$S/router-down"
echo none >"$S/connectivity"
run
check "router down: no automatic fix, restart the router" \
    first_problem "ok,ok,ok,ok,problem,skipped,skipped" gateway gateway-down ""

setup
touch "$S/router-down"
run
check "a router that ignores pings while the internet works is fine" \
    all_ok gateway gateway-quiet

setup
: >"$S/route4"
echo 'default via fe80::1 dev wlo1 proto ra metric 600 pref medium' >"$S/route6"
run
check "an IPv6 router is pinged through its adapter" called "ping -c 2 -W 2 fe80::1%wlo1"

setup
: >"$S/route4"
run
check "no router at all: fixed by reconnect" \
    first_problem "ok,ok,ok,ok,problem,skipped,skipped" gateway no-gateway reconnect

setup
touch "$S/dns-down"
run
check "DNS down: fixed by flush-dns" first_problem "ok,ok,ok,ok,ok,problem,skipped" dns dns-failed flush-dns

setup
echo portal >"$S/connectivity"
run
check "captive portal: fixed by open-portal" first_problem "ok,ok,ok,ok,ok,ok,problem" internet portal open-portal

setup
echo limited >"$S/connectivity"
run
check "limited internet: no automatic fix" first_problem "ok,ok,ok,ok,ok,ok,problem" internet limited ""

setup
touch "$S/nm-stopped"
run
check "NetworkManager not running: fixed by restart-networking, the rest skipped" \
    first_problem "problem,skipped,skipped,skipped,skipped,skipped,skipped" adapter nm-not-running restart-networking

setup
printf 'lo:loopback:connected (externally)\nvirbr0:bridge:connected (externally)\n' >"$S/devices"
run
check "no Wi-Fi or Ethernet adapter: no fix" \
    first_problem "problem,skipped,skipped,skipped,skipped,skipped,skipped" adapter no-adapter ""

# The fixes.
setup
run fix wifi-on
check "fix wifi-on turns the Wi-Fi radio on and waits for a connection" \
    succeeded_calling "nmcli radio wifi on" "rfkill unblock wlan" "nm-online -q -t 15"

setup
run fix airplane-off
check "fix airplane-off turns every radio on and Plasma's airplane mode off" \
    succeeded_calling "nmcli radio all on" "rfkill unblock all" "kwriteconfig6 --file plasma-nm --group General --key AirplaneModeEnabled false"

setup
run fix networking-on
check "fix networking-on turns networking on" succeeded_calling "nmcli networking on"

setup
echo 0b5a4e8e-1111-2222-3333-444444444444 >"$S/uuid"
run fix reconnect
check "fix reconnect brings the connected adapter's connection up again" \
    succeeded_calling "nmcli --wait 30 connection up uuid 0b5a4e8e-1111-2222-3333-444444444444"

setup
printf 'enp3s0:ethernet:unavailable\nwlo1:wifi:disconnected\n' >"$S/devices"
run fix reconnect
check "fix reconnect connects a disconnected Wi-Fi adapter when no cable is in" \
    succeeded_calling "nmcli --wait 30 device connect wlo1"

setup
printf 'enp3s0:ethernet:unavailable\n' >"$S/devices"
run fix reconnect
check "fix reconnect with nothing to connect fails" exited 1

setup
run fix flush-dns
check "fix flush-dns clears resolved's cache" succeeded_calling "resolvectl flush-caches"

setup
touch "$S/resolvectl-fails"
run fix flush-dns
check "a fix that fails exits 1" exited 1
check "a fix that fails says why on its last line" test "$(tail -n1 <<<"$ERR")" == "network-check: couldn't clear the saved website names"

setup
run fix open-portal
check "fix open-portal opens Fedora's connectivity address without a configured one" \
    succeeded_calling "xdg-open http://fedoraproject.org/static/hotspot.txt"

setup
printf '[main]\nplugins=keyfile\n\n[connectivity]\nenabled=true\nuri=http://example.test/check.txt\nresponse=OK\n' \
    >"$R/usr/lib/NetworkManager/conf.d/20-connectivity.conf"
run fix open-portal
check "fix open-portal opens the address NetworkManager's configuration names" \
    succeeded_calling "xdg-open http://example.test/check.txt"

setup
ORIELOS_NETWORK_CHECK_UID=1000 run fix restart-networking
check "fix restart-networking asks an administrator through pkexec" \
    succeeded_calling "pkexec /usr/libexec/orielos/restart-networking"
check "fix restart-networking doesn't restart anything itself" not_called systemctl

setup
cat >"$WORK/bin/restart-networking" <<'SH'
#!/usr/bin/env bash
echo restart-networking >>"$STUB_DIR/calls"
SH
chmod +x "$WORK/bin/restart-networking"
ORIELOS_NETWORK_CHECK_UID=0 ORIELOS_NETWORK_CHECK_RESTART="$WORK/bin/restart-networking" run fix restart-networking
check "fix restart-networking as root runs the restart tool without pkexec" \
    succeeded_calling "restart-networking"
check "fix restart-networking as root doesn't use pkexec" not_called pkexec

setup
run fix bogus
check "an unknown fix exits 2" exited 2
check "an unknown fix runs nothing" not_called "nmcli radio"

setup
run fix
check "fix without an id exits 2" exited 2

setup
run bogus
check "an unknown command exits 2" exited 2

setup
run --help
check "--help prints the usage" grep -qF "network-check fix <fix id>" <<<"$OUT"

setup
RC=0
OUT="$(STUB_DIR="$S" PATH="$WORK/bin:$PATH" bash "$RESTART" 2>&1)" || RC=$?
check "restart-networking restarts NetworkManager and waits for it" \
    succeeded_calling "systemctl restart NetworkManager.service" "nm-online -s -q -t 30"

setup
RC=0
OUT="$(STUB_DIR="$S" PATH="$WORK/bin:$PATH" bash "$RESTART" now 2>&1)" || RC=$?
check "restart-networking takes no arguments" exited 2
check "restart-networking with arguments restarts nothing" not_called systemctl

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
