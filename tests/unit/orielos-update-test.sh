#!/usr/bin/env bash
# Unit tests for orielos-update's check, pause, channel and going-back logic, undoing an update that
# didn't start, removing the previous build, automatic app updates, and the state file it writes for
# the desktop. Runs the real script against a scratch directory (ORIELOS_UPDATE_ROOT) with stand-ins
# for bootc, skopeo, busctl, systemctl, ostree, flatpak and the boot menu's flag helper, so it needs
# no root, VM or network.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/orielos-update-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/bin/orielos-update"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
# A fixed "now", 2026-10-25T12:00:00Z, and the digests of three builds.
NOW=1792929600
WEEK=$((7 * 24 * 60 * 60))
RUNNING="sha256:$(printf 'a%.0s' {1..64})"
NEWER="sha256:$(printf 'b%.0s' {1..64})"
OTHER="sha256:$(printf 'c%.0s' {1..64})"
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

# check <name> <condition...>: PASS if the command succeeds, else FAIL with the last output.
check() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT"; fi
}

iso() {
    date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

# bootc's status JSON: bootc_status <booted digest> <booted version> [staged digest staged version]
bootc_status() {
    jq -n --arg bd "$1" --arg bv "$2" --arg sd "${3:-}" --arg sv "${4:-}" '{
        status: {
            booted: {image: {image: {image: "example.test/orielos:stable", transport: "registry"}, version: $bv, imageDigest: $bd},
                ostree: {checksum: "aaaa", deploySerial: 0, stateroot: "default"}},
            staged: (if $sd == "" then null else {image: {image: {image: "example.test/orielos", transport: "registry"}, version: $sv, imageDigest: $sd}} end),
            rollback: null,
            rollbackQueued: false
        }
    }'
}

# Give a bootc status file a previous build, which going back would start, and say whether going
# back is queued: with_previous <file> <digest> <version> [true|false]
with_previous() {
    local status
    status="$(jq --arg d "$2" --arg v "$3" --argjson q "${4:-false}" '
        .status.rollback = {image: {image: {image: "example.test/orielos", transport: "registry"}, version: $v, imageDigest: $d},
            ostree: {checksum: "bbbb", deploySerial: 0, stateroot: "default"}}
        | .status.rollbackQueued = $q' "$1")"
    printf '%s\n' "$status" >"$1"
}

# skopeo inspect's JSON: skopeo_info <digest> <version>
skopeo_info() {
    jq -n --arg d "$1" --arg v "$2" '{Digest: $d, Labels: {"org.opencontainers.image.version": $v}}'
}

# A fresh scratch system running build RUNNING (44.1), with stand-in commands that log their
# arguments to $WORK/stub/calls and read their answers from files in $WORK/stub.
setup() {
    rm -rf "${WORK:?}/root" "${WORK:?}/stub" "${WORK:?}/bin"
    mkdir -p "$WORK/root/usr/lib/orielos" "$WORK/root/etc/orielos" "$WORK/root/proc/sys/kernel/random" \
        "$WORK/stub" "$WORK/bin"
    printf 'source=docker://example.test/orielos\n' >"$WORK/root/usr/lib/orielos/update.conf"
    printf 'VERSION=44.1\n' >"$WORK/root/usr/lib/orielos/build-info"
    printf 'boot-1\n' >"$WORK/root/proc/sys/kernel/random/boot_id"
    bootc_status "$RUNNING" 44.1 >"$WORK/stub/bootc-status.json"
    skopeo_info "$RUNNING" 44.1 >"$WORK/stub/skopeo.json"
    printf 'u 4\n' >"$WORK/stub/metered"
    : >"$WORK/stub/calls"
    cat >"$WORK/bin/bootc" <<'SH'
#!/usr/bin/env bash
printf 'bootc %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
case "$1" in
    status) cat "$ORIELOS_TEST_STUB/bootc-status.json" ;;
    switch)
        if [[ -e "$ORIELOS_TEST_STUB/switch-fails" ]]; then
            echo "error: switching failed" >&2
            exit 1
        fi
        if [[ -e "$ORIELOS_TEST_STUB/status-after-switch.json" ]]; then
            cp "$ORIELOS_TEST_STUB/status-after-switch.json" "$ORIELOS_TEST_STUB/bootc-status.json"
        fi
        ;;
    rollback)
        if [[ -e "$ORIELOS_TEST_STUB/status-after-rollback.json" ]]; then
            cp "$ORIELOS_TEST_STUB/status-after-rollback.json" "$ORIELOS_TEST_STUB/bootc-status.json"
        fi
        ;;
esac
SH
    cat >"$WORK/bin/skopeo" <<'SH'
#!/usr/bin/env bash
printf 'skopeo %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ -e "$ORIELOS_TEST_STUB/skopeo-fails" ]]; then
    echo "manifest unknown" >&2
    exit 1
fi
cat "$ORIELOS_TEST_STUB/skopeo.json"
SH
    cat >"$WORK/bin/busctl" <<'SH'
#!/usr/bin/env bash
printf 'busctl %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
cat "$ORIELOS_TEST_STUB/metered"
SH
    cat >"$WORK/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
SH
    cat >"$WORK/bin/flatpak" <<'SH'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ -e "$ORIELOS_TEST_STUB/flatpak-fails" ]]; then
    echo "error: Unable to connect to dl.flathub.org" >&2
    exit 1
fi
echo "Nothing to do."
SH
    # ostree lists the booted deployment, then the previous one.
    cat >"$WORK/bin/ostree" <<'SH'
#!/usr/bin/env bash
printf 'ostree %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ "$1 $2" == "admin status" ]]; then
    printf '* default aaaa.0\n    origin: <unknown origin type>\n  default bbbb.0 (rollback)\n    origin: <unknown origin type>\n'
fi
SH
    # The boot menu's flag helper, inside the scratch root: it logs its command, and status prints
    # the flags in $ORIELOS_TEST_STUB/flags.
    mkdir -p "$WORK/root/usr/libexec/orielos"
    cat >"$WORK/root/usr/libexec/orielos/boot-flags" <<'SH'
#!/usr/bin/env bash
printf 'boot-flags %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ "$1" == status && -r "$ORIELOS_TEST_STUB/flags" ]]; then cat "$ORIELOS_TEST_STUB/flags"; fi
SH
    chmod +x "$WORK/bin/"* "$WORK/root/usr/libexec/orielos/boot-flags"
}

# Run orielos-update at time <now>, keeping its output in OUT and its exit status in RC.
#   at <now> <arguments...>
at() {
    local now="$1"
    shift
    RC=0
    OUT="$(ORIELOS_UPDATE_ROOT="$WORK/root" ORIELOS_UPDATE_NOW="$now" ORIELOS_TEST_STUB="$WORK/stub" \
        PATH="$WORK/bin:$PATH" bash "$TOOL" "$@" 2>&1)" || RC=$?
}

run() {
    at "$NOW" "$@"
}

state() {
    jq -r "$1" "$WORK/root/var/lib/orielos/update/state.json"
}

setting() {
    sed -n "s/^$1=//p" "$WORK/root/var/lib/orielos/update/settings"
}

called() {
    grep -qF -- "$1" "$WORK/stub/calls"
}

not_called() {
    ! grep -qF -- "$1" "$WORK/stub/calls"
}

#BEGIN Pause and resume
setup
run pause 1
check "pause 1 pauses for one week" test "$RC" -eq 0 -a "$(setting paused_until)" == "$(iso $((NOW + WEEK)))"
check "pause writes the pause into state.json" test "$(state .pausedUntil)" == "$(iso $((NOW + WEEK)))"
check "state.json says no check has run yet" test "$(state .result)" == never-checked -a "$(state .checkedAt)" == null

setup
run pause 5
check "pause 5 pauses for five weeks" test "$RC" -eq 0 -a "$(setting paused_until)" == "$(iso $((NOW + 5 * WEEK)))"

for weeks in 0 6 x 1.5 -1; do
    setup
    run pause "$weeks"
    check "pause $weeks is refused with exit 2 and changes nothing" \
        test "$RC" -eq 2 -a ! -e "$WORK/root/var/lib/orielos/update/settings"
done

setup
run pause 2
run check
check "a check while paused reports paused" test "$RC" -eq 0 -a "$(state .result)" == paused
check "a check while paused reads no channel and stages nothing" not_called "skopeo inspect"

setup
run pause 1
at $((NOW + 8 * 24 * 60 * 60)) check
check "an ended pause is cleared" test -z "$(setting paused_until)" -a "$(state .pausedUntil)" == null
check "an ended pause lets the check go ahead" called "skopeo inspect docker://example.test/orielos:stable"

setup
run pause 3
run resume
check "resume ends the pause" test "$RC" -eq 0 -a -z "$(setting paused_until)" -a "$(state .pausedUntil)" == null
#END

#BEGIN Channels
setup
run check
check "the default channel is stable" called "skopeo inspect docker://example.test/orielos:stable"

setup
run channel testing
check "channel testing is saved" test "$RC" -eq 0 -a "$(setting channel)" == testing -a "$(state .channel)" == testing
run check
check "the check after a channel change reads the new channel" called "skopeo inspect docker://example.test/orielos:testing"

setup
run pause 2
run channel testing
check "changing channel keeps a pause" test "$(setting paused_until)" == "$(iso $((NOW + 2 * WEEK)))"

for name in beta Stable ""; do
    setup
    run channel "$name"
    check "channel '$name' is refused with exit 2" test "$RC" -eq 2 -a ! -e "$WORK/root/var/lib/orielos/update/settings"
done
#END

#BEGIN Checks
setup
run check
check "the running build is reported up to date" test "$RC" -eq 0 -a "$(state .result)" == up-to-date
check "an up-to-date check stages nothing" not_called "bootc switch"

setup
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/status-after-switch.json"
run check
check "a newer build is staged" test "$RC" -eq 0 -a "$(state .result)" == staged -a "$(state .staged.digest)" == "$NEWER"
check "a registry build is staged pinned to its digest" called "bootc switch --quiet example.test/orielos@$NEWER"
check "state.json names the staged version" test "$(state .staged.version)" == 44.2

setup
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/bootc-status.json"
run check
check "an already staged build is reported staged" test "$RC" -eq 0 -a "$(state .result)" == staged
check "an already staged build isn't staged twice" not_called "bootc switch"

setup
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
mkdir -p "$WORK/root/var/lib/orielos/update"
printf '%s  # rejected\n' "$NEWER" >"$WORK/root/var/lib/orielos/update/rejected-digests"
run check
check "a rejected build is reported and not staged" test "$RC" -eq 0 -a "$(state .result)" == rejected
check "a rejected build isn't staged" not_called "bootc switch"

setup
: >"$WORK/stub/skopeo-fails"
run check
check "an unreadable channel exits 0 and reports unreachable" test "$RC" -eq 0 -a "$(state .result)" == unreachable
check "the unreachable message says why" test "$(state .message)" == "Couldn't read the stable channel: manifest unknown"

setup
printf 'u 1\n' >"$WORK/stub/metered"
run check
check "a metered connection skips the check" test "$RC" -eq 0 -a "$(state .result)" == metered
check "a metered connection downloads nothing" not_called "skopeo inspect"

setup
printf 'u 3\n' >"$WORK/stub/metered"
run check
check "a guessed metered connection skips the check" test "$(state .result)" == metered

setup
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
: >"$WORK/stub/switch-fails"
run check
check "a failed stage exits 1 and reports an error" test "$RC" -eq 1 -a "$(state .result)" == error

setup
printf 'source=oci:/srv/updates\n' >"$WORK/root/etc/orielos/update.conf"
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/status-after-switch.json"
run check
check "/etc/orielos/update.conf overrides the source" called "skopeo inspect oci:/srv/updates:stable"
check "an OCI directory build is staged by its tag" called "bootc switch --quiet --transport oci /srv/updates:stable"
check "an OCI directory build is staged" test "$(state .result)" == staged

setup
printf 'source=oci:/srv/updates\n' >"$WORK/root/etc/orielos/update.conf"
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
bootc_status "$RUNNING" 44.1 "$OTHER" 44.3 >"$WORK/stub/status-after-switch.json"
run check
check "a channel that moved while staging is an error" test "$RC" -eq 1 -a "$(state .result)" == error

setup
printf 'source=ftp://example.test/orielos\n' >"$WORK/root/etc/orielos/update.conf"
run check
check "an unsupported source is refused" test "$RC" -eq 1

setup
run check-now
check "check-now starts the check unit without waiting" called "systemctl start --no-block orielos-update-check.service"
#END

#BEGIN The state file
# Succeed if state.json has exactly the contract's fields, with the values of an up-to-date check.
matches_contract() {
    jq -e --arg d "$RUNNING" --arg t "$(iso "$NOW")" '
        .bootId == "boot-1" and .channel == "stable" and .pausedUntil == null and .checkedAt == $t
        and .result == "up-to-date" and (.message | type) == "string"
        and .running == {version: "44.1", digest: $d} and .staged == null
        and .previous == null and .rollbackQueued == false
        and .appUpdates == true and .appsUpdatedAt == null
        and (keys | sort) == ["appUpdates", "appsUpdatedAt", "bootId", "channel", "checkedAt", "message", "pausedUntil",
            "previous", "result", "rollbackQueued", "running", "staged"]
    ' "$WORK/root/var/lib/orielos/update/state.json" >/dev/null
}

setup
run check
check "state.json has the contract's fields and types" matches_contract
check "state.json is readable by everyone" test "$(stat -c %a "$WORK/root/var/lib/orielos/update/state.json")" == 644

at $((NOW + 60)) refresh
check "refresh keeps the last check's time and result" \
    test "$(state .result)" == up-to-date -a "$(state .checkedAt)" == "$(iso "$NOW")"

setup
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/status-after-switch.json"
run check
# After the restart, the staged build is running and nothing is staged.
bootc_status "$NEWER" 44.2 >"$WORK/stub/bootc-status.json"
printf 'boot-2\n' >"$WORK/root/proc/sys/kernel/random/boot_id"
run refresh
check "refresh after restarting into the update reports up to date" \
    test "$(state .result)" == up-to-date -a "$(state .staged)" == null -a "$(state .running.digest)" == "$NEWER"
check "refresh records the new boot" test "$(state .bootId)" == boot-2

setup
run refresh
check "refresh before any check reports never-checked" test "$(state .result)" == never-checked -a "$(state .checkedAt)" == null
#END

#BEGIN Going back
REJECTED_FILE="$WORK/root/var/lib/orielos/update/rejected-digests"

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
run refresh
check "state.json names the previous build" \
    test "$(state .previous.version)" == 44.0 -a "$(state .previous.digest)" == "$OTHER" -a "$(state .previous.rejected)" == false
check "state.json says going back isn't queued" test "$(state .rollbackQueued)" == false

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
mkdir -p "$WORK/root/var/lib/orielos/update"
printf '%s  # rejected
' "$OTHER" >"$REJECTED_FILE"
run refresh
check "a previous build that was rolled back is marked rejected" test "$(state .previous.rejected)" == true

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
cp "$WORK/stub/bootc-status.json" "$WORK/stub/status-after-rollback.json"
with_previous "$WORK/stub/status-after-rollback.json" "$OTHER" 44.0 true
run rollback
check "rollback exits 0 and goes back with bootc" test "$RC" -eq 0 -a -n "$(grep -F 'bootc rollback' "$WORK/stub/calls")"
check "rollback rejects the running build" grep -qF "$RUNNING" "$REJECTED_FILE"
check "after rollback, state.json says the previous build starts next" \
    test "$(state .rollbackQueued)" == true -a "$(state .previous.version)" == 44.0

setup
run rollback
check "rollback without a previous build fails with exit 1" test "$RC" -eq 1
check "rollback without a previous build leaves bootc alone" not_called "bootc rollback"

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0 true
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
run check
check "a check while going back is queued reports rollback-queued" \
    test "$RC" -eq 0 -a "$(state .result)" == rollback-queued
check "the rollback-queued message names the previous version" \
    test "$(state .message)" == "OrielOS 44.0 starts at the next restart; updates continue after it."
check "a check while going back is queued reads no channel" not_called "skopeo inspect"
check "a check while going back is queued stages nothing" not_called "bootc switch"
# After the restart, the previous build is running and nothing is queued.
bootc_status "$OTHER" 44.0 >"$WORK/stub/bootc-status.json"
with_previous "$WORK/stub/bootc-status.json" "$RUNNING" 44.1
printf 'boot-2\n' >"$WORK/root/proc/sys/kernel/random/boot_id"
run refresh
check "refresh after going back reports up to date" \
    test "$(state .result)" == up-to-date -a "$(state .rollbackQueued)" == false -a "$(state .running.version)" == 44.0

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
cp "$WORK/stub/bootc-status.json" "$WORK/stub/status-after-rollback.json"
with_previous "$WORK/stub/status-after-rollback.json" "$OTHER" 44.0 true
run rollback
check "going back takes the previous build off trial" called "boot-flags clear"
#END

#BEGIN Undoing an update that didn't start
setup
skopeo_info "$NEWER" 44.2 >"$WORK/stub/skopeo.json"
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/status-after-switch.json"
run check
check "a newly staged build is put on trial" called "boot-flags trial"

setup
run check
check "an up-to-date check puts nothing on trial" not_called "boot-flags trial"

# The boot loader started the previous build, 44.0, in place of 44.2, which failed twice: 44.2 is
# still set to start next.
fallback() {
    setup
    bootc_status "$OTHER" 44.0 >"$WORK/stub/bootc-status.json"
    with_previous "$WORK/stub/bootc-status.json" "$NEWER" 44.2 true
    bootc_status "$OTHER" 44.0 >"$WORK/stub/status-after-rollback.json"
    with_previous "$WORK/stub/status-after-rollback.json" "$NEWER" 44.2
    printf 'orielos_boot_ok=0\norielos_trial=fallback\norielos_fails=1\n' >"$WORK/stub/flags"
}

fallback
run refresh
check "refresh after the boot loader fell back keeps the running build" \
    test "$RC" -eq 0 -a -n "$(grep -F 'bootc rollback' "$WORK/stub/calls")"
check "the failed update is rejected" grep -qF "$NEWER" "$WORK/root/var/lib/orielos/update/rejected-digests"
check "the flags say the previous build was kept" called "boot-flags kept"
check "state.json says the update was undone" \
    test "$(state .result)" == went-back -a "$(state .message)" == "OrielOS 44.2 didn't start properly, so OrielOS went back to 44.0. It won't be offered again; a newer version will be."

fallback
printf 'orielos_boot_ok=0\norielos_trial=1\norielos_fails=1\n' >"$WORK/stub/flags"
run refresh
check "refresh keeps nothing when the boot loader didn't fall back" not_called "bootc rollback"

fallback
run undo-update
check "undo-update keeps the running build" test "$RC" -eq 0 -a "$(state .result)" == went-back

setup
run undo-update
check "undo-update without another build fails with exit 1" test "$RC" -eq 1

fallback
run refresh
printf 'boot-2\n' >"$WORK/root/proc/sys/kernel/random/boot_id"
run refresh
check "at the next boot the undone update is no longer the news" test "$(state .result)" == up-to-date
#END

#BEGIN Removing the previous build
DAY=$((24 * 60 * 60))
setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
run refresh
check "refresh records when the running build first started" \
    test "$(sed -n 's/^since=//p' "$WORK/root/var/lib/orielos/update/running")" == "$(iso "$NOW")"
check "state.json says when the previous build is removed" test "$(state .previous.removedAfter)" == "$(iso $((NOW + 14 * DAY)))"
at $((NOW + 13 * DAY)) check
check "the previous build is kept for 14 days" not_called "ostree admin undeploy"
check "a later refresh keeps the first start's time" \
    test "$(sed -n 's/^since=//p' "$WORK/root/var/lib/orielos/update/running")" == "$(iso "$NOW")"
at $((NOW + 14 * DAY)) refresh
check "refresh at boot never removes it, so the login screen isn't delayed" not_called "ostree admin undeploy"
at $((NOW + 14 * DAY)) check
check "after 14 days the check removes the previous build" called "ostree admin undeploy 1"
check "removing it also prunes the image data no deployment uses" called "ostree container image prune-images --sysroot / --full"

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
run refresh
run pause 2
at $((NOW + 15 * DAY)) check
check "the check removes a previous build that's due even while updates are paused" called "ostree admin undeploy 1"

setup
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/bootc-status.json"
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
run refresh
at $((NOW + 15 * DAY)) check
check "a previous build isn't removed while an update is staged" not_called "ostree admin undeploy"

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0 true
run refresh
at $((NOW + 15 * DAY)) check
check "a previous build isn't removed while going back to it is queued" not_called "ostree admin undeploy"

setup
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
run remove-previous
check "remove-previous removes the previous build now" test "$RC" -eq 0 -a -n "$(grep -F 'ostree admin undeploy 1' "$WORK/stub/calls")"

setup
run remove-previous
check "remove-previous without a previous build fails with exit 1" test "$RC" -eq 1 -a -z "$(grep -F 'ostree admin undeploy' "$WORK/stub/calls")"

setup
bootc_status "$RUNNING" 44.1 "$NEWER" 44.2 >"$WORK/stub/bootc-status.json"
with_previous "$WORK/stub/bootc-status.json" "$OTHER" 44.0
run remove-previous
check "remove-previous refuses while an update is staged" test "$RC" -eq 1
#END

#BEGIN Apps from the Store
setup
run refresh
check "app updates are on by default" test "$(state .appUpdates)" == true -a "$(state .appsUpdatedAt)" == null

setup
run app-updates off
check "app-updates off turns them off" test "$RC" -eq 0 -a "$(setting app_updates)" == off -a "$(state .appUpdates)" == false
run pause 2
check "pausing OS updates keeps app updates off" test "$(setting app_updates)" == off -a -n "$(setting paused_until)"
run channel testing
check "changing the channel keeps app updates off and the pause" \
    test "$(setting app_updates)" == off -a "$(setting channel)" == testing -a -n "$(setting paused_until)"
run apps
check "apps does nothing while app updates are off" test "$RC" -eq 0 -a "$(state .appsUpdatedAt)" == null
check "and runs no flatpak" not_called "flatpak"
run app-updates on
check "app-updates on turns them back on" test "$RC" -eq 0 -a "$(setting app_updates)" == on -a "$(state .appUpdates)" == true

setup
run apps
check "apps updates every system-wide app and runtime without asking" called "flatpak update --system --noninteractive"
check "apps records when the apps were updated" test "$RC" -eq 0 -a "$(state .appsUpdatedAt)" == "$(iso "$NOW")"
run status
check "status shows app updates and when they last ran" grep -qF "App updates: on, last updated $(iso "$NOW")" <<<"$OUT"

setup
: >"$WORK/stub/flatpak-fails"
run apps
check "a failed app update exits 1, so the service tries again" test "$RC" -eq 1
check "and doesn't record an update" test ! -e "$WORK/root/var/lib/orielos/update/apps"

setup
printf 'u 1\n' >"$WORK/stub/metered"
run apps
check "apps skips a metered connection" test "$RC" -eq 0
check "and runs no flatpak" not_called "flatpak"

for value in "" yes 1; do
    setup
    # shellcheck disable=SC2086 # an empty value is meant to be left out
    run app-updates $value
    check "app-updates '$value' is refused with exit 2 and changes nothing" \
        test "$RC" -eq 2 -a ! -e "$WORK/root/var/lib/orielos/update/settings"
done
#END

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
