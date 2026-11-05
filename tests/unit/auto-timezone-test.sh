#!/usr/bin/env bash
# Unit tests for setting the time zone automatically and syncing the clock now, from Settings ›
# Date & time: image/system/usr/libexec/orielos/auto-timezone (turning it on and off, and setting
# the zone only when the location service names a known zone that differs from the one set),
# NetworkManager's dispatcher script for it, and image/system/usr/libexec/orielos/time-sync. Runs
# the real scripts against a scratch directory (ORIELOS_AUTO_TIMEZONE_ROOT, ORIELOS_TIME_SYNC_TEST)
# with stand-ins for curl, timedatectl, systemctl, chronyc and sleep, so it needs no root, network
# or VM. Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/auto-timezone-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/libexec/orielos/auto-timezone"
DISPATCHER="$ROOT/image/system/usr/lib/NetworkManager/dispatcher.d/90-orielos-auto-timezone"
SYNC="$ROOT/image/system/usr/libexec/orielos/time-sync"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0
R=""
STUB=""

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

# A fresh scratch computer whose time zone is Europe/London, with stand-in commands that log their
# arguments to $STUB/calls. curl answers with $STUB/geoip, or fails while $STUB/curl-fails exists;
# timedatectl keeps the zone in $STUB/zone; chronyc answers tracking with $STUB/tracking, and with
# $STUB/tracking-next once sleep has run (a new measurement arriving); systemctl reports chronyd
# running unless $STUB/chronyd-stopped exists.
setup() {
    rm -rf "${WORK:?}/root" "${WORK:?}/stub" "${WORK:?}/bin"
    R="$WORK/root"
    STUB="$WORK/stub"
    mkdir -p "$R/etc" "$STUB" "$WORK/bin"
    : >"$STUB/calls"
    printf 'Europe/London\n' >"$STUB/zone"
    printf '{"city": "Paris", "country_code": "FR", "time_zone": "Europe/Paris"}\n' >"$STUB/geoip"

    cat >"$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ -e "$ORIELOS_TEST_STUB/curl-fails" ]]; then
    echo "curl: (6) Could not resolve host: geoip.fedoraproject.org" >&2
    exit 6
fi
cat "$ORIELOS_TEST_STUB/geoip"
SH
    cat >"$WORK/bin/timedatectl" <<'SH'
#!/usr/bin/env bash
printf 'timedatectl %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
case "$1" in
    list-timezones) printf '%s\n' Africa/Abidjan America/New_York Europe/London Europe/Paris UTC ;;
    show) cat "$ORIELOS_TEST_STUB/zone" ;;
    set-timezone) printf '%s\n' "$2" >"$ORIELOS_TEST_STUB/zone" ;;
esac
SH
    cat >"$WORK/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ "$1" == is-active ]]; then
    [[ ! -e "$ORIELOS_TEST_STUB/chronyd-stopped" ]]
fi
SH
    cat >"$WORK/bin/chronyc" <<'SH'
#!/usr/bin/env bash
printf 'chronyc %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ "${*: -1}" == tracking ]]; then
    if [[ -e "$ORIELOS_TEST_STUB/slept" && -e "$ORIELOS_TEST_STUB/tracking-next" ]]; then
        cat "$ORIELOS_TEST_STUB/tracking-next"
    else
        cat "$ORIELOS_TEST_STUB/tracking"
    fi
else
    echo "200 OK"
fi
SH
    cat >"$WORK/bin/sleep" <<'SH'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
touch "$ORIELOS_TEST_STUB/slept"
SH
    chmod +x "$WORK/bin/"*
}

run() {
    RC=0
    OUT="$(ORIELOS_AUTO_TIMEZONE_ROOT="$R" ORIELOS_TEST_STUB="$STUB" PATH="$WORK/bin:$PATH" bash "$TOOL" "$@" 2>&1)" || RC=$?
}

dispatch() {
    RC=0
    OUT="$(ORIELOS_AUTO_TIMEZONE_ROOT="$R" ORIELOS_TEST_STUB="$STUB" PATH="$WORK/bin:$PATH" bash "$DISPATCHER" "$@" 2>&1)" || RC=$?
}

sync_now() {
    RC=0
    OUT="$(ORIELOS_TIME_SYNC_TEST=1 ORIELOS_TEST_STUB="$STUB" PATH="$WORK/bin:$PATH" bash "$SYNC" "$@" 2>&1)" || RC=$?
}

called() {
    grep -qF -- "$1" "$STUB/calls"
}

not_called() {
    ! grep -qF -- "$1" "$STUB/calls"
}

zone_is() {
    [[ "$(cat "$STUB/zone")" == "$1" ]]
}

turn_on() {
    mkdir -p "$R/etc/orielos"
    printf '# on\n' >"$R/etc/orielos/auto-timezone"
}

# chronyc -c tracking lines: synchronised to a server at a time, or not synchronised.
synced_at() {
    printf 'C0A80101,192.168.1.1,3,%s.471107394,-0.000016084,-0.000000519,0.000004434,-21.519,-0.003,0.040,0.000356485,0.000569195,1064.4,Normal\n' "$1"
}

not_synced() {
    printf '00000000,,0,0.000000000,0.000000000,0.000000000,0.000000000,0.000,0.000,0.000,1.000000000,1.000000000,0.0,Not synchronised\n'
}

#BEGIN Turning it on and off
setup
run on
check "on succeeds" test "$RC" -eq 0
check "on creates the setting's file" test -f "$R/etc/orielos/auto-timezone"
check "on enables and starts the timer" called "systemctl enable --now orielos-auto-timezone.timer"
check "on sets the time zone at once" zone_is Europe/Paris
check "on says what changed" grep -q "from Europe/London to Europe/Paris" <<<"$OUT"

run off
check "off succeeds" test "$RC" -eq 0
check "off removes the setting's file" test ! -e "$R/etc/orielos/auto-timezone"
check "off disables and stops the timer" called "systemctl disable --now orielos-auto-timezone.timer"
check "off leaves the time zone as it is" zone_is Europe/Paris

setup
touch "$STUB/curl-fails"
run on
check "on still turns it on when the lookup fails" test "$RC" -eq 0 -a -f "$R/etc/orielos/auto-timezone"
check "and changes nothing then" zone_is Europe/London
#END

#BEGIN Setting the time zone
setup
run set
check "set does nothing while it's turned off" test "$RC" -eq 0
check "and doesn't ask the location service" not_called "curl"
check "and doesn't change the zone" not_called "timedatectl set-timezone"

setup
turn_on
run set
check "set asks Fedora's location service, with a time limit" called "curl -fsS --max-time 10 https://geoip.fedoraproject.org/city"
check "set changes the zone to the one the service names" zone_is Europe/Paris

setup
turn_on
printf 'Europe/Paris\n' >"$STUB/zone"
run set
check "set leaves the same zone alone" test "$RC" -eq 0
check "without asking timedated to change it" not_called "timedatectl set-timezone"

setup
turn_on
printf '{"time_zone": "Mars/Olympus_Mons"}\n' >"$STUB/geoip"
run set
check "set ignores a zone the system doesn't know" test "$RC" -eq 0
check "and leaves the zone as it is" not_called "timedatectl set-timezone"

setup
turn_on
printf '{"time_zone": "../../etc/passwd"}\n' >"$STUB/geoip"
run set
check "set ignores something that isn't a zone name" not_called "timedatectl set-timezone"

setup
turn_on
printf '{"city": "Paris"}\n' >"$STUB/geoip"
run set
check "set ignores an answer without a zone" test "$RC" -eq 0
check "and changes nothing" not_called "timedatectl set-timezone"

setup
turn_on
printf '<html>Service unavailable</html>\n' >"$STUB/geoip"
run set
check "set ignores an answer that isn't JSON" test "$RC" -eq 0 -a "$(cat "$STUB/zone")" == Europe/London

setup
turn_on
touch "$STUB/curl-fails"
run set
check "set ignores a failed lookup" test "$RC" -eq 0
check "and says so" grep -q "couldn't ask the location service" <<<"$OUT"
check "and changes nothing" not_called "timedatectl set-timezone"
#END

#BEGIN Usage
setup
run
check "no command is wrong usage" test "$RC" -eq 2
run sideways
check "an unknown command is wrong usage" test "$RC" -eq 2
run on now
check "on takes no arguments" test "$RC" -eq 2
sync_now now
check "time-sync takes no arguments" test "$RC" -eq 2
if [[ "$EUID" -ne 0 ]]; then
    RC=0
    OUT="$(env -u ORIELOS_AUTO_TIMEZONE_ROOT PATH="$WORK/bin:$PATH" ORIELOS_TEST_STUB="$STUB" bash "$TOOL" set 2>&1)" || RC=$?
    check "it refuses to run as anyone but root" test "$RC" -eq 1
    check "and says to run it as root" grep -q "as root" <<<"$OUT"
    RC=0
    OUT="$(env -u ORIELOS_TIME_SYNC_TEST PATH="$WORK/bin:$PATH" ORIELOS_TEST_STUB="$STUB" bash "$SYNC" 2>&1)" || RC=$?
    check "time-sync refuses to run as anyone but root" test "$RC" -eq 1 -a ! -s "$STUB/calls"
else
    printf 'SKIP  the root checks (the tests are running as root)\n'
fi
#END

#BEGIN NetworkManager
setup
turn_on
dispatch wlan0 up
check "getting online starts the service" called "systemctl start --no-block orielos-auto-timezone.service"

setup
turn_on
CONNECTIVITY_STATE=FULL dispatch "" connectivity-change
check "full connectivity starts the service" called "systemctl start --no-block orielos-auto-timezone.service"

setup
turn_on
CONNECTIVITY_STATE=PORTAL dispatch "" connectivity-change
check "a captive portal doesn't" not_called "systemctl"

setup
turn_on
dispatch wlan0 down
check "going offline doesn't" not_called "systemctl"

setup
dispatch wlan0 up
check "nothing starts while it's turned off" test "$RC" -eq 0 -a ! -s "$STUB/calls"
#END

#BEGIN Sync now
setup
synced_at 1700000000 >"$STUB/tracking"
synced_at 1700000100 >"$STUB/tracking-next"
sync_now
check "sync succeeds when a new measurement arrives" test "$RC" -eq 0
check "sync asks chronyd to measure the servers at once" called "chronyc burst 4/4"
check "sync steps the clock" called "chronyc makestep"
check "sync stops waiting once the measurement is in" test "$(grep -c '^sleep' "$STUB/calls")" -eq 1

setup
not_synced >"$STUB/tracking"
sync_now
check "sync fails when no server answers" test "$RC" -eq 1
check "and says so in one line" test "$OUT" == "time-sync: no time server answered; check the internet connection"
check "and doesn't step the clock" not_called "chronyc makestep"
check "after about ten seconds" test "$(grep -c '^sleep' "$STUB/calls")" -eq 10

setup
synced_at 1700000000 >"$STUB/tracking"
sync_now
check "an earlier measurement still counts" test "$RC" -eq 0
check "and the clock is stepped" called "chronyc makestep"

setup
printf '7F7F0101,,10,1700000000.000000000,0,0,0,0,0,0,0,0,0,Normal\n' >"$STUB/tracking"
sync_now
check "the PC's own clock doesn't count as a server" test "$RC" -eq 1

setup
touch "$STUB/chronyd-stopped"
not_synced >"$STUB/tracking"
sync_now
check "sync fails when chronyd isn't running" test "$RC" -eq 1
check "and says why" grep -q "isn't running" <<<"$OUT"
check "without asking chronyd anything" not_called "chronyc"
#END

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
