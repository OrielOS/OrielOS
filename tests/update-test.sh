#!/usr/bin/env bash
# Tests updating and rolling back an installed OrielOS. Installs the old build to a disk file,
# boots it headless under QEMU/KVM with Secure Boot and a software TPM, finishes setup and
# creates user data over SSH through a vsock device, then stages the new build from an OCI
# archive with orielos-update, restarts into it, rolls back, restarts into the old build again
# and checks that the rolled-back build is refused. Then it tests the background update service:
# it offers the new build as the testing channel of a local update source, checks that the stable
# channel and a pause stage nothing and that the rolled-back build is skipped, logs the user in,
# lets orielos-update-check.service stage the build, checks the notifier's tray icon, chooses
# "Restart to update" in its menu and checks the new build runs. Then it opens Settings → Update by
# clicking the tray icon, opens the same page in kcmshell6 and, with the keyboard (each button's
# Alt mnemonic, and polkit's password prompt), checks for updates, pauses and resumes, switches to
# the stable channel and back, and goes back to the previous version, restarting into it from the
# page. Then it watches the boot
# menu on the serial console: hidden after a boot that reached the desktop, shown after one that
# didn't (the display manager is turned off for it), where the test chooses the other version, and
# shown again when Esc is pressed during the hidden second. It undoes an update that fails to
# start, removes the previous build after 14 days, and last installs the update once more and
# removes the previous version from Settings → Update. Prints PASS/FAIL per check.
#
# Usage: tests/update-test.sh --old IMAGE_OR_ARCHIVE --new ARCHIVE [--timeout SECONDS]
#                             [--memory MIB] [--cpus N] [--results DIR] [--keep] [--help]
#   --old REF|FILE      the build to install first: an image in Podman (such as
#                       localhost/orielos:44.20261025) or an OCI archive from tools/build-image.sh
#   --new FILE          the build to update to: an OCI archive from tools/build-image.sh
#   --timeout SECONDS   time to wait for SSH after power-on and after each restart (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, the status files and summary.txt go
#                       (default tests/results/<run id>)
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is
# update-<new build's tag>-<UTC time>. Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
OLD=""
NEW=""
IMAGE=""
ARCHIVE=""
TIMEOUT=600
MEMORY=6144
CPUS=4
RESULTS=""
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
SUMMARY=""
OLD_VERSION=""
OLD_DIGEST=""
NEW_VERSION=""
NEW_DIGEST=""
REMOTE_ARCHIVE=""
BOOT_ID=""
KEEP_FILE=""
KEEP_TEXT=""
# The deployments bootc reports, read by read_status.
STATUS_JSON=""
BOOTED_DIGEST=""
BOOTED_VERSION=""
STAGED_DIGEST=""
# The local update source the service steps use: an OCI directory with one tag per channel.
SERVICE_SOURCE="/var/lib/orielos/test-source"
# Changing the channel, going back and removing the previous version ask for an administrator's
# password; the test user is one and gets this password.
TEST_PASSWORD="orielos-test-pass"
# The Update settings page, a Plasma settings module that System Settings opens by its name.
SETTINGS_MODULE="kcm_orielos_update"
# Where this boot's output starts in the serial log, and what the boot menu showed (boot menu steps).
SERIAL_MARK=0
NOTIFIER_OUT=""
MENU_SHOWN=0
MENU_TEXT=""
# The versions the boot menu listed, in order and space-separated, and the highlighted one.
MENU_ENTRIES=""
MENU_DEFAULT=""

usage() {
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Print the manifest digest and the version label of the build in an OCI archive, without
# importing it: "<digest> <version>".
archive_info() {
    local file="$1"
    python3 -I - "$file" <<'PY'
import json, sys, tarfile

with tarfile.open(sys.argv[1]) as tar:
    def blob(name):
        return json.load(tar.extractfile(name))

    digest = blob("index.json")["manifests"][0]["digest"]
    config = blob("blobs/sha256/" + digest.split(":", 1)[1])["config"]["digest"]
    labels = blob("blobs/sha256/" + config.split(":", 1)[1])["config"].get("Labels") or {}
    print(digest, labels.get("org.opencontainers.image.version", ""))
PY
}

# Print one field of a deployment from STATUS_JSON: status_field <booted|staged|rollback> <field>
status_field() {
    python3 -I -c '
import json, sys
status = json.loads(sys.argv[1]).get("status") or {}
image = (status.get(sys.argv[2]) or {}).get("image") or {}
print(image.get(sys.argv[3]) or "")' "$STATUS_JSON" "$1" "$2"
}

# Read bootc's status and orielos-update's status inside the VM, keep both in the results as
# bootc-status-<name>.json and status-<name>.txt, and set the BOOTED_* and STAGED_* variables.
read_status() {
    local name="$1"
    STATUS_JSON="$(vm_ssh bootc status --format=json 2>/dev/null)" || STATUS_JSON="{}"
    printf '%s\n' "$STATUS_JSON" >"$RESULTS/bootc-status-$name.json"
    vm_ssh orielos-update status >"$RESULTS/status-$name.txt" 2>&1 || true
    BOOTED_DIGEST="$(status_field booted imageDigest)"
    BOOTED_VERSION="$(status_field booted version)"
    STAGED_DIGEST="$(status_field staged imageDigest)"
    info "bootc: running $BOOTED_VERSION ($BOOTED_DIGEST), staged ${STAGED_DIGEST:-none}"
}

# Print a command's output indented under the previous line, and add it to summary.txt.
show_output() {
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then say "" "    " "$line"; fi
    done <<<"$1"
}

# Restart the VM from inside, wait for SSH to go away and come back, and check that the boot id
# changed. Returns 1 if the VM does not come back as a new boot.
restart_vm() {
    local before="$BOOT_ID" start now=""
    info "Restarting the VM"
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    start=$SECONDS
    while ((SECONDS - start < 300)); do
        now="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || break
        [[ "$now" == "$before" ]] || break
        sleep 2
    done
    BOOT_START=$start
    wait_for_ssh || return 1
    now="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    if [[ -z "$now" || "$now" == "$before" ]]; then
        info "The boot id did not change (${now:-no output}), so the VM did not restart"
        return 1
    fi
    BOOT_ID="$now"
    info "The VM restarted (boot id $BOOT_ID)"
}

# Check that the user's file still holds what was written: check_keepme <when>
check_keepme() {
    local text
    text="$(vm_ssh cat "$KEEP_FILE" 2>&1)" || true
    if [[ "$text" == "$KEEP_TEXT" ]]; then
        pass "$KEEP_FILE is unchanged $1"
    else
        fail "$KEEP_FILE changed $1 (now: ${text:-empty})"
    fi
}

step_boot_old() {
    info "Step 1: install and boot the old build"
    if [[ -f "$OLD" ]]; then
        ARCHIVE="$OLD"
        IMAGE="localhost/orielos-archive:$(basename "$OLD" .ociarchive)"
        load_archive
    else
        IMAGE="$OLD"
    fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"
    OLD_VERSION="$(podman image inspect --format '{{index .Labels "org.opencontainers.image.version"}}' "$IMAGE")"
    info "Old build: $IMAGE, version $OLD_VERSION"
    info "New build: $NEW, version $NEW_VERSION ($NEW_DIGEST)"
    setup_ssh
    install_image
    start_vm
    if ! wait_for_ssh; then
        fail "The old build boots: SSH over vsock did not answer"
        return 1
    fi
    BOOT_ID="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    read_status old
    OLD_DIGEST="$BOOTED_DIGEST"
    if [[ -z "$OLD_DIGEST" || "$BOOTED_VERSION" != "$OLD_VERSION" ]]; then
        fail "The old build boots, but bootc reports version ${BOOTED_VERSION:-none} (${OLD_DIGEST:-no digest}), not $OLD_VERSION"
        return 1
    fi
    pass "The old build boots (version $OLD_VERSION, $OLD_DIGEST)"
}

step_user_data() {
    local out
    info "Step 2: finish setup and create user data"
    finish_setup
    KEEP_FILE="/var/home/$TEST_USER/keepme.txt"
    KEEP_TEXT="$(head -c 24 /dev/urandom | base64)"
    if [[ "$FINISH_OK" -ne 1 ]]; then
        fail "User data created: setup could not be finished"
        return 1
    fi
    if ! out="$(vm_ssh "printf '%s\n' '$KEEP_TEXT' >$KEEP_FILE && chown $TEST_USER: $KEEP_FILE && cat $KEEP_FILE" 2>&1)" ||
        [[ "$out" != "$KEEP_TEXT" ]]; then
        fail "User data created: could not write $KEEP_FILE (${out:-no output})"
        return 1
    fi
    pass "User data created ($TEST_USER and $KEEP_FILE)"
}

step_copy() {
    local here there start=$SECONDS
    REMOTE_ARCHIVE="/var/tmp/${NEW##*/}"
    info "Step 3: copy the new build into the VM ($(du -h "$NEW" | cut -f1))"
    vm_copy "$NEW" "$REMOTE_ARCHIVE" || true
    here="$(sha256sum "$NEW" | cut -d' ' -f1)"
    there="$(vm_ssh sha256sum "$REMOTE_ARCHIVE" 2>/dev/null | cut -d' ' -f1)" || true
    if [[ "$here" != "$there" ]]; then
        fail "The new build was not copied to $REMOTE_ARCHIVE intact (sha256 ${there:-missing})"
        return 1
    fi
    pass "The new build was copied to $REMOTE_ARCHIVE in $((SECONDS - start)) s"
}

step_stage() {
    local out rc=0 start=$SECONDS before="$BOOT_ID" now
    info "Step 4: stage the new build"
    # Staging imports the whole build, which takes longer than vm_ssh normally waits.
    out="$(SSH_TIMEOUT=1800 vm_ssh orielos-update stage "$REMOTE_ARCHIVE" 2>&1)" || rc=$?
    printf '%s\n' "$out" >"$RESULTS/stage.txt"
    if [[ "$rc" -eq 0 ]]; then
        pass "orielos-update stage exits 0 after $((SECONDS - start)) s"
        show_output "$out"
    else
        fail "orielos-update stage exited with status $rc"
        show_output "$out"
        return 1
    fi
    now="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    read_status staged
    if [[ "$BOOTED_DIGEST" == "$OLD_DIGEST" && "$now" == "$before" ]]; then
        pass "The running build is unchanged after staging (still $OLD_VERSION, same boot)"
    else
        fail "The running build changed while staging (running ${BOOTED_DIGEST:-unknown}; boot id $now, was $before)"
    fi
    if [[ "$STAGED_DIGEST" == "$NEW_DIGEST" ]]; then
        pass "The new build is staged for the next restart ($NEW_DIGEST)"
    else
        fail "The staged build is ${STAGED_DIGEST:-none}, not $NEW_DIGEST"
        return 1
    fi
}

step_update_boot() {
    local info_version
    info "Step 5: restart into the new build"
    if ! restart_vm; then
        fail "The new build runs after a restart: the VM did not come back"
        return 1
    fi
    read_status new
    info_version="$(vm_ssh sed -n 's/^VERSION=//p' /usr/lib/orielos/build-info 2>/dev/null)" || true
    if [[ "$BOOTED_DIGEST" == "$NEW_DIGEST" && "$BOOTED_VERSION" == "$NEW_VERSION" && "$info_version" == "$NEW_VERSION" ]]; then
        pass "The new build runs after a restart (version $NEW_VERSION, $NEW_DIGEST; build-info says $info_version)"
    else
        fail "The new build does not run after a restart (running ${BOOTED_VERSION:-unknown}, ${BOOTED_DIGEST:-no digest}; build-info says ${info_version:-nothing})"
        check_keepme "after the update"
        return 1
    fi
    check_keepme "after the update"
}

step_rollback() {
    local out rc=0 rejected
    info "Step 6: roll back and restart into the old build"
    out="$(vm_ssh orielos-update rollback 2>&1)" || rc=$?
    printf '%s\n' "$out" >"$RESULTS/rollback.txt"
    rejected="$(vm_ssh cat /var/lib/orielos/update/rejected-digests 2>/dev/null)" || true
    if [[ "$rc" -eq 0 && "$rejected" == *"$NEW_DIGEST"* ]]; then
        pass "orielos-update rollback exits 0 and rejects the new build"
        show_output "$out"
    else
        fail "orielos-update rollback exited with status $rc (rejected builds: ${rejected:-none})"
        show_output "$out"
        return 1
    fi
    if ! restart_vm; then
        fail "The old build runs after rolling back: the VM did not come back"
        return 1
    fi
    read_status rolled-back
    if [[ "$BOOTED_DIGEST" == "$OLD_DIGEST" && "$BOOTED_VERSION" == "$OLD_VERSION" ]]; then
        pass "The old build runs after rolling back and restarting (version $OLD_VERSION, $OLD_DIGEST)"
    else
        fail "The old build does not run after rolling back (running ${BOOTED_VERSION:-unknown}, ${BOOTED_DIGEST:-no digest})"
    fi
    check_keepme "after the rollback"
}

# Run orielos-update in the VM and print its state file's result: service_run <arguments...>
# Prints "rc=<exit status>" and "result=<state.json's result>" lines.
service_run() {
    local rc=0 out
    out="$(SSH_TIMEOUT=1800 vm_ssh orielos-update "$@" 2>&1)" || rc=$?
    printf '%s\n' "$out" >>"$RESULTS/service.txt"
    printf 'rc=%s\n' "$rc"
    printf 'result=%s\n' "$(vm_ssh jq -r .result /var/lib/orielos/update/state.json 2>/dev/null)"
}

# Read one key from service_run's output: service_value <output> <key>
service_value() {
    sed -n "s/^$2=//p" <<<"$1" | head -n1
}

step_service_source() {
    local out
    info "Step 8: offer the new build as the testing channel of a local update source"
    # An OCI directory with one tag per channel stands in for the registry, so the test needs no
    # network. Only testing has a build; stable has none.
    if ! out="$(SSH_TIMEOUT=1800 vm_ssh "set -e
        skopeo copy --quiet oci-archive:$REMOTE_ARCHIVE oci:$SERVICE_SOURCE:testing
        mkdir -p /etc/orielos
        printf 'source=oci:%s\n' $SERVICE_SOURCE >/etc/orielos/update.conf" 2>&1)"; then
        fail "The local update source was not set up: ${out:-no output}"
        return 1
    fi
    out="$(service_run check)"
    read_status service-stable
    if [[ "$(service_value "$out" rc)" == 0 && "$(service_value "$out" result)" == unreachable && -z "$STAGED_DIGEST" ]]; then
        pass "A check on the stable channel, which has no build, stages nothing (result unreachable)"
    else
        fail "A check on the empty stable channel gave exit $(service_value "$out" rc), result $(service_value "$out" result), staged ${STAGED_DIGEST:-none}"
        return 1
    fi
}

step_service_channel() {
    local out
    info "Step 9: switch to the testing channel, then pause and resume"
    out="$(service_run channel testing)"
    [[ "$(service_value "$out" rc)" == 0 ]] || {
        fail "orielos-update channel testing exited with $(service_value "$out" rc)"
        return 1
    }
    out="$(service_run check)"
    read_status service-rejected
    if [[ "$(service_value "$out" result)" == rejected && -z "$STAGED_DIGEST" ]]; then
        pass "On the testing channel, the check skips the build that was rolled back (result rejected)"
    else
        fail "The check on the testing channel gave result $(service_value "$out" result), staged ${STAGED_DIGEST:-none}, not rejected"
    fi
    vm_ssh orielos-update forget "$NEW_DIGEST" >>"$RESULTS/service.txt" 2>&1 || true
    service_run pause 1 >/dev/null
    out="$(service_run check)"
    read_status service-paused
    if [[ "$(service_value "$out" result)" == paused && -z "$STAGED_DIGEST" ]]; then
        pass "While updates are paused, the check stages nothing (result paused)"
    else
        fail "The check while paused gave result $(service_value "$out" result), staged ${STAGED_DIGEST:-none}"
    fi
    out="$(service_run resume)"
    [[ "$(service_value "$out" rc)" == 0 ]] || {
        fail "orielos-update resume exited with $(service_value "$out" rc)"
        return 1
    }
}

# A script for the VM that reads the update notifier's tray icon as the test user over the
# session bus: prints "notifier=<pid>", "item=<bus name>", "status=<Status property>" and
# "tooltip=<text>". With a label (notifier_script "Restart to update") it also prints the menu's
# visible labels and clicks the item whose label starts with it, the way the tray does; a label
# that starts no item only lists them. With "activate" as the second argument it clicks the icon
# itself (notifier_script "" activate). busctl takes explicit signatures and prints JSON, which jq
# reads.
notifier_script() {
    cat <<SH
label=$(printf '%q' "${1:-}")
activate=$(printf '%q' "${2:-}")
bus() { busctl --user -M $TEST_USER@ --json=short "\$@" 2>/dev/null; }
# The kernel keeps only the first 15 characters of a process's name, so match the command line.
pid="\$(pgrep -u $TEST_USER -f '(^|/)orielos-update-notifier( |\$)' | head -n1)"
echo "notifier=\$pid"
[ -n "\$pid" ] || exit 0
# Tray icons register with Plasma's StatusNotifierWatcher as "<bus name>/<object path>"; the
# notifier's is the one whose connection belongs to its process.
item=""
item_path=""
items="\$(bus get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems)"
for entry in \$(printf '%s' "\$items" | jq -r '.data[]'); do
    name="\${entry%%/*}"
    owner="\$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s "\$name" | jq -r '.data[0]')"
    if [ "\$owner" = "\$pid" ]; then
        item="\$name"
        case "\$entry" in
            */*) item_path="/\${entry#*/}" ;;
            *) item_path=/StatusNotifierItem ;;
        esac
    fi
done
echo "item=\$item"
[ -n "\$item" ] || exit 0
echo "status=\$(bus get-property "\$item" "\$item_path" org.kde.StatusNotifierItem Status | jq -r '.data')"
# The tooltip is (icon name, icon pixmaps, title, text); the text says what the state file says.
echo "tooltip=\$(bus get-property "\$item" "\$item_path" org.kde.StatusNotifierItem ToolTip | jq -r '.data[3]')"
if [ -n "\$activate" ]; then
    bus call "\$item" "\$item_path" org.kde.StatusNotifierItem Activate ii 0 0 >/dev/null && echo activated=yes
fi
if [ -n "\$label" ]; then
    menu="\$(bus get-property "\$item" "\$item_path" org.kde.StatusNotifierItem Menu | jq -r '.data')"
    echo "menu=\$menu"
    # Depth 10 rather than -1 ("all"): busctl would read -1 as an option.
    layout="\$(bus call "\$item" "\$menu" com.canonical.dbusmenu GetLayout iias 0 10 0)"
    # Labels may carry an accelerator mark (KDE adds them to menus), "_" in dbusmenu. Hidden items
    # are in the layout too, with visible set to false.
    echo "labels=\$(printf '%s' "\$layout" | jq -r '[.data[1][2][] | .data[1] | select(.visible.data != false) | .label.data // ""] | join("|")')"
    id="\$(printf '%s' "\$layout" | jq -r --arg label "\$label" '.data[1][2][] | .data | select(.[1].visible.data != false)
        | select(.[1].label.data // "" | gsub("[_&]"; "") | startswith(\$label)) | .[0]' | head -n1)"
    echo "menu_item=\$id"
    [ -n "\$id" ] && bus call "\$item" "\$menu" com.canonical.dbusmenu Event isvu "\$id" clicked s "" 0 >/dev/null &&
        echo clicked=yes
fi
SH
}

# Wait up to 120 s for the update notifier's tray icon in the test user's session, keeping the
# probe's last output in NOTIFIER_OUT. Returns 1, and saves notifier.txt, if it doesn't appear.
wait_for_notifier() {
    local start=$SECONDS
    while ((SECONDS - start < 120)); do
        NOTIFIER_OUT="$(vm_ssh "$(notifier_script)" 2>/dev/null)" || true
        [[ -n "$(service_value "$NOTIFIER_OUT" item)" ]] && return 0
        sleep 3
    done
    vm_ssh "ps -u $TEST_USER -o pid,args; journalctl -b --no-pager | grep -i -E 'update-notifier|UpdateNotifier' | tail -n 40" \
        >"$RESULTS/notifier.txt" 2>&1 || true
    return 1
}

step_service_notify() {
    local out rc
    info "Step 10: log in to the desktop, let the check service stage the build and see the notifier"
    if ! out="$(vm_ssh "set -e
        mkdir -p /etc/sddm.conf.d
        printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' $TEST_USER >/etc/sddm.conf.d/99-update-test-autologin.conf
        systemctl restart sddm" 2>&1)"; then
        fail "Could not log $TEST_USER in to the desktop: ${out:-no output}"
        return 1
    fi
    if ! wait_for_notifier; then
        fail "The update notifier did not start in $TEST_USER's session within 120 s (${NOTIFIER_OUT//$'\n'/; }; see notifier.txt)"
        return 1
    fi
    pass "The update notifier runs in $TEST_USER's session with a tray icon ($(service_value "$NOTIFIER_OUT" item))"

    # The real unit, as the timer starts it.
    rc=0
    SSH_TIMEOUT=1800 vm_ssh systemctl start orielos-update-check.service >>"$RESULTS/service.txt" 2>&1 || rc=$?
    read_status service-staged
    if [[ "$rc" -eq 0 && "$STAGED_DIGEST" == "$NEW_DIGEST" ]]; then
        pass "orielos-update-check.service stages the testing channel's build ($NEW_VERSION)"
    else
        fail "orielos-update-check.service exited with $rc and staged ${STAGED_DIGEST:-nothing}, not $NEW_DIGEST"
        return 1
    fi
    vm_ssh cat /var/lib/orielos/update/state.json >"$RESULTS/state-staged.json" 2>/dev/null || true

    sleep 10
    vm_qmp "shot:$RESULTS/update-ready.png" || true
    out="$(vm_ssh "$(notifier_script)" 2>/dev/null)" || true
    if [[ "$(service_value "$out" status)" == *Active* ]]; then
        pass "The notifier's tray icon asks for attention once the update is staged (see update-ready.png)"
    else
        fail "The notifier's tray icon status is $(service_value "$out" status), not Active (see update-ready.png)"
    fi
}

# Wait for the VM to come back as a new boot after something inside it restarted it. Returns 1 if
# it doesn't within the timeout.
wait_for_new_boot() {
    local before="$BOOT_ID" start=$SECONDS now=""
    while ((SECONDS - start < 300)); do
        now="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
        [[ -z "$now" || "$now" == "$before" ]] || break
        sleep 3
    done
    BOOT_START=$SECONDS
    wait_for_ssh || return 1
    now="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    [[ -n "$now" && "$now" != "$before" ]] || return 1
    BOOT_ID="$now"
}

step_service_restart() {
    local out state state_boot state_summary
    info "Step 11: choose Restart to update in the notifier"
    out="$(vm_ssh "$(notifier_script "Restart to update")" 2>&1)" || true
    if [[ "$(service_value "$out" clicked)" != yes ]]; then
        fail "Could not choose Restart to update in the notifier's menu (${out//$'\n'/; })"
        return 1
    fi
    if ! wait_for_new_boot; then
        fail "Restart to update did not restart the VM within 300 s"
        return 1
    fi
    read_status service-updated
    if [[ "$BOOTED_DIGEST" == "$NEW_DIGEST" ]]; then
        pass "Restart to update restarts into the new build ($NEW_VERSION)"
    else
        fail "After Restart to update, the VM runs ${BOOTED_VERSION:-unknown} (${BOOTED_DIGEST:-no digest}), not $NEW_VERSION"
    fi
    state="$(vm_ssh cat /var/lib/orielos/update/state.json 2>/dev/null)" || true
    printf '%s\n' "$state" >"$RESULTS/state-updated.json"
    state_boot="$(jq -r '.bootId' <<<"$state" 2>/dev/null)" || true
    state_summary="$(jq -r '.result + " " + (.staged | tostring) + " " + .running.digest' <<<"$state" 2>/dev/null)" || true
    if [[ "$state_boot" == "$BOOT_ID" && "$state_summary" == "up-to-date null $NEW_DIGEST" ]]; then
        pass "This boot's update state says OrielOS is up to date, with nothing staged"
    else
        fail "This boot's update state is not up to date (see state-updated.json)"
    fi
    check_keepme "after updating through the notifier"
}

# Print a value from the VM's update state: state_value <jq filter>
state_value() {
    vm_ssh jq -r "$(printf '%q' "$1")" /var/lib/orielos/update/state.json 2>/dev/null || true
}

# Wait up to <seconds> for a value in the VM's update state to become <value>, or, with "!=", to
# stop being it: wait_for_state <jq filter> [!=] <value> <seconds>. Returns 1 if it doesn't.
wait_for_state() {
    local filter="$1" negate=0 value seconds start now
    if [[ "$2" == "!=" ]]; then
        negate=1
        shift
    fi
    value="$2"
    seconds="$3"
    start=$SECONDS
    while ((SECONDS - start < seconds)); do
        now="$(state_value "$filter")"
        if [[ "$negate" -eq 0 && "$now" == "$value" ]] || [[ "$negate" -eq 1 && -n "$now" && "$now" != "$value" ]]; then
            return 0
        fi
        sleep 2
    done
    return 1
}

# Click the notifier's tray icon and wait up to 60 s for System Settings to show the Update
# settings page in the test user's session; then save a screenshot: open_update_settings <name>.
# Returns 1 if the page doesn't open.
open_update_settings() {
    local out start
    out="$(vm_ssh "$(notifier_script "" activate)" 2>&1)" || true
    if [[ "$(service_value "$out" activated)" != yes ]]; then
        info "Could not click the notifier's tray icon (${out//$'\n'/; })"
        return 1
    fi
    start=$SECONDS
    while ((SECONDS - start < 60)); do
        if vm_ssh pgrep -u "$TEST_USER" -f "systemsettings.*$SETTINGS_MODULE" >/dev/null 2>&1; then
            # Let the page load and read the state before it's used.
            vm_qmp "wait:8" "shot:$RESULTS/$1.png" || true
            return 0
        fi
        sleep 2
    done
    vm_ssh "ps -u $TEST_USER -o pid,args; journalctl -b --no-pager | grep -i -E 'systemsettings|kcm_orielos' | tail -n 40" \
        >"$RESULTS/settings.txt" 2>&1 || true
    return 1
}

# Close System Settings and open the same page on its own with kcmshell6, in the test user's
# session, then save a screenshot: open_update_window <name>. The keyboard steps use this window,
# where the page is alone and no other control takes the keys; in System Settings, a letter no
# shortcut claims goes to the sidebar's search field. Returns 1 if the window doesn't start.
open_update_window() {
    local start
    vm_ssh "pkill -u $TEST_USER -f 'systemsettings.*$SETTINGS_MODULE'; pkill -u $TEST_USER -x kcmshell6; sleep 2
        systemd-run --user -M $TEST_USER@ --collect --quiet kcmshell6 $SETTINGS_MODULE" >/dev/null 2>&1 || true
    start=$SECONDS
    while ((SECONDS - start < 60)); do
        if vm_ssh pgrep -u "$TEST_USER" -x kcmshell6 >/dev/null 2>&1; then
            vm_qmp "wait:8" "shot:$RESULTS/$1.png" || true
            return 0
        fi
        sleep 2
    done
    return 1
}

# Answer polkit's password prompt as the test user, after a screenshot of it: answer_password <name>
answer_password() {
    vm_qmp "wait:4" "shot:$RESULTS/$1.png" "type:$TEST_PASSWORD" "keys:ret" || true
}

step_update_settings() {
    local out labels checked days
    info "Step 12: use Settings → Update: check for updates, pause and resume, change channel and go back"
    # Changing the channel and going back need an administrator's password, so the test user gets one.
    if ! vm_ssh "printf '%s:%s\n' $TEST_USER '$TEST_PASSWORD' | chpasswd" >/dev/null 2>&1; then
        fail "Could not set $TEST_USER's password for polkit's prompt"
        return 1
    fi
    # After the restart, the session starts the notifier a while after SSH answers.
    if ! wait_for_notifier; then
        fail "The update notifier did not start after the restart within 120 s (see notifier.txt)"
        return 1
    fi
    out="$(vm_ssh "$(notifier_script "(only list the menu)")" 2>&1)" || true
    labels="$(service_value "$out" labels)"
    labels="${labels//_/}"
    if [[ "$labels" == *"Open update settings"* && "$labels" != *Pause* && "$labels" != *channel* &&
        "$labels" != *"Go back"* && "$labels" != *"Check for updates"* ]]; then
        pass "The notifier's menu only opens the update settings and restarts ($labels)"
    else
        fail "The notifier's menu still has more than restarting and opening the settings: ${labels:-nothing}"
    fi

    checked="$(state_value .checkedAt)"
    if open_update_settings settings-page; then
        pass "Clicking the notifier's tray icon opens Settings → Update ($SETTINGS_MODULE in System Settings; see settings-page.png)"
    else
        fail "Clicking the notifier's tray icon didn't open Settings → Update within 60 s (see settings.txt)"
        return 1
    fi
    if ! open_update_window settings-window; then
        fail "kcmshell6 $SETTINGS_MODULE didn't start in $TEST_USER's session within 60 s"
        return 1
    fi

    vm_qmp "keys:alt+u" || true
    if wait_for_state .checkedAt != "$checked" 180; then
        vm_qmp "wait:3" "shot:$RESULTS/settings-checked.png" || true
        pass "Check for updates on the page runs a check: $(state_value .result), \"$(state_value .message)\" (see settings-checked.png)"
    else
        vm_qmp "shot:$RESULTS/settings-checked.png" || true
        fail "Check for updates on the page didn't run a check within 180 s (see settings-checked.png)"
    fi

    vm_qmp "keys:alt+p" || true
    if wait_for_state .pausedUntil != null 60; then
        days="$(vm_ssh "echo \$(( (\$(date -d \"\$(jq -r .pausedUntil /var/lib/orielos/update/state.json)\" +%s) - \$(date +%s) + 43200) / 86400 ))" 2>/dev/null)" || true
        vm_qmp "wait:3" "shot:$RESULTS/settings-paused.png" || true
        if [[ "$days" == 7 ]]; then
            pass "Pause updates on the page pauses them for a week, until $(state_value .pausedUntil) (see settings-paused.png)"
        else
            fail "Pause updates on the page paused them for ${days:-an unknown number of} days, not 7"
        fi
    else
        vm_qmp "shot:$RESULTS/settings-paused.png" || true
        fail "Pause updates on the page didn't pause them within 60 s (see settings-paused.png)"
    fi
    vm_qmp "keys:alt+r" || true
    if wait_for_state .pausedUntil null 60; then
        pass "Resume updates on the page ends the pause"
    else
        vm_qmp "shot:$RESULTS/settings-resume.png" || true
        fail "Resume updates on the page didn't end the pause within 60 s (see settings-resume.png)"
    fi

    # The VM is on the testing channel since step 9. The first change asks for a password; polkit
    # may keep the authorisation for the second one.
    vm_qmp "keys:alt+s" || true
    answer_password channel-password
    if wait_for_state .channel stable 60; then
        vm_qmp "wait:2" "shot:$RESULTS/settings-stable.png" || true
        pass "Choosing Stable on the page asks for an administrator's password and switches the channel (see channel-password.png, settings-stable.png)"
    else
        vm_qmp "shot:$RESULTS/settings-stable.png" || true
        fail "Choosing Stable on the page didn't switch the channel within 60 s (see channel-password.png, settings-stable.png)"
    fi
    vm_qmp "keys:alt+t" || true
    if ! wait_for_state .channel testing 10; then
        answer_password channel-password-again
    fi
    if wait_for_state .channel testing 60; then
        pass "Choosing Testing on the page switches back"
    else
        vm_qmp "shot:$RESULTS/settings-testing.png" || true
        fail "Choosing Testing on the page didn't switch back within 70 s (see settings-testing.png)"
    fi

    # The question's default button is Cancel, so choose Go back by its mnemonic, then answer
    # polkit's password prompt.
    vm_qmp "keys:alt+g" "wait:3" "shot:$RESULTS/go-back-question.png" "keys:alt+b" || true
    answer_password go-back-password
    if wait_for_state .rollbackQueued true 120 && vm_ssh grep -qF "$NEW_DIGEST" /var/lib/orielos/update/rejected-digests; then
        read_status go-back
        pass "Going back on the page asks first, then for a password, queues $OLD_VERSION and rejects $NEW_VERSION (see go-back-question.png, go-back-password.png)"
    else
        read_status go-back
        fail "Going back on the page didn't queue the previous build (see go-back-question.png, go-back-password.png)"
        return 1
    fi
    sleep 5
    vm_qmp "shot:$RESULTS/go-back-ready.png" || true
    out="$(vm_ssh "$(notifier_script "(only list the menu)")" 2>&1)" || true
    labels="$(service_value "$out" labels)"
    if [[ "$(service_value "$out" status)" == *Active* && "${labels//_/}" == *"Restart to go back"* ]]; then
        pass "The notifier asks for attention and offers Restart to go back, and the page offers Restart now (see go-back-ready.png)"
    else
        fail "The notifier didn't offer Restart to go back (${out//$'\n'/; }; see go-back-ready.png)"
    fi
    vm_qmp "keys:alt+n" || true
    if ! wait_for_new_boot; then
        fail "Restart now on the page did not restart the VM within 300 s"
        return 1
    fi
    read_status went-back
    if [[ "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "Restart now on the page restarts into the previous build ($OLD_VERSION)"
    else
        fail "After Restart now, the VM runs ${BOOTED_VERSION:-unknown} (${BOOTED_DIGEST:-no digest}), not $OLD_VERSION"
    fi
    check_keepme "after going back through Settings → Update"
}

# Print the boot menu's flags from the EFI system partition in the VM, one name=value per line, or
# nothing while the file doesn't exist.
boot_flags() {
    vm_ssh /usr/libexec/orielos/boot-flags status 2>/dev/null | grep -v '=$' || true
}

# Print the boot menu's start flag, "orielos_boot_ok=<0|1>", or nothing.
boot_flag() {
    boot_flags | grep '^orielos_boot_ok=' || true
}

# Set boot menu flags in the VM, as earlier starts would have left them: set_boot_flags <name=value...>
set_boot_flags() {
    vm_ssh "$(
        cat <<SH
esp="\$(lsblk -lnpo NAME,PARTTYPE | awk 'tolower(\$2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print \$1; exit}')"
dir="\$(mktemp -d)"
mount "\$esp" "\$dir" && grub2-editenv "\$dir/EFI/fedora/orielos-boot.env" set $*
umount "\$dir"
rmdir "\$dir"
SH
    )" >/dev/null 2>&1
}

# Wait up to 120 s for this boot's desktop session to mark the boot as good. Returns 1 if it doesn't.
wait_for_good_boot() {
    local start=$SECONDS
    while ((SECONDS - start < 120)); do
        [[ "$(boot_flag)" == orielos_boot_ok=1 ]] && return 0
        sleep 3
    done
    return 1
}

# Print what the serial console showed since serial_mark, without colour codes or unprintable bytes.
serial_mark() {
    SERIAL_MARK="$(stat -c %s "$WORK/serial.log" 2>/dev/null || echo 0)"
}
serial_since() {
    tail -c +"$((SERIAL_MARK + 1))" "$WORK/serial.log" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -cd '\11\12\40-\176'
}

# Restart the VM and watch the serial console, where the firmware copies GRUB's screen, for the
# boot menu until the kernel starts: restart_watching_menu <none|enter|escape>
#   none          only watch
#   enter         in the menu, start the highlighted version
#   escape        press Esc once while GRUB waits with the menu hidden, then start the highlighted
#                 version
# Sets MENU_SHOWN to 1 if the menu appeared, keeps its text in MENU_TEXT, the versions it listed in
# MENU_ENTRIES and the highlighted one (GRUB marks it with *) in MENU_DEFAULT, and waits for the
# new boot. Returns 1 if the VM doesn't come back.
restart_watching_menu() {
    local action="$1" start text pressed=0
    MENU_SHOWN=0
    MENU_TEXT=""
    MENU_ENTRIES=""
    MENU_DEFAULT=""
    # The boot entries GRUB will read, before each restart, for when the menu isn't as expected.
    {
        printf '== before restarting to %s, running %s\n' "$action" "${BOOTED_VERSION:-unknown}"
        vm_ssh "ls -l --time-style=+%T /boot/loader/entries/; grep -H -E '^(title|version) ' /boot/loader/entries/*.conf" 2>&1
    } >>"$RESULTS/boot-entries.txt" || true
    serial_mark
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    start=$SECONDS
    while ((SECONDS - start < 180)); do
        text="$(serial_since)"
        if [[ "$text" == *"keys to select which entry is highlighted"* ]]; then
            MENU_SHOWN=1
            # Let GRUB finish drawing the menu before reading it.
            sleep 1
            text="$(serial_since)"
            MENU_TEXT="$(grep -a -E 'ostree:|UEFI Firmware' <<<"$text" | tr -s ' ' || true)"
            MENU_ENTRIES="$(grep -a -o -E 'OrielOS [0-9][0-9.]* \(ostree:[0-9]\)' <<<"$text" |
                sed -E 's/^OrielOS //; s/ \(ostree:[0-9]\)$//' | awk '!seen[$0]++' | paste -sd ' ' -)" || true
            MENU_DEFAULT="$(grep -a -o -E '\*OrielOS [0-9][0-9.]*' <<<"$text" | head -n1 | sed 's/^\*OrielOS //')" || true
            case "$action" in
                enter) vm_qmp "shot:$RESULTS/boot-menu-last-resort.png" "keys:ret" || true ;;
                escape) vm_qmp "shot:$RESULTS/boot-menu-esc.png" "keys:ret" || true ;;
                *) vm_qmp "shot:$RESULTS/boot-menu-unexpected.png" || true ;;
            esac
            break
        fi
        [[ "$text" == *"Linux version"* ]] && break
        # Once the firmware hands over to the boot loader, press Esc once; the firmware keeps the key
        # until GRUB reads it during its hidden second. A second Esc would close the menu again,
        # back to the first-stage configuration on the EFI system partition, which ends at a grub>
        # prompt.
        if [[ "$action" == escape && "$pressed" -eq 0 && "$text" == *"BdsDxe: starting"* ]]; then
            vm_qmp "keys:esc" || true
            pressed=1
        fi
        sleep 0.2
    done
    wait_for_new_boot
}

step_boot_menu() {
    local out titles names
    info "Step 13: the boot menu stays hidden after good boots and appears after a failed one"
    vm_ssh "ls -l /boot/loader; grep -H -E '^(title|version) ' /boot/loader/entries/*.conf" >"$RESULTS/boot-entries.txt" 2>&1 || true
    out="$(vm_ssh "grep -c 'BEGIN 12_orielos-menu.cfg' /boot/grub2/grub.cfg" 2>/dev/null)" || true
    titles="$(vm_ssh "grep -h '^title ' /boot/loader/entries/*.conf | sed 's/^title //' | sort" 2>/dev/null | paste -sd ';' -)" || true
    # ostree adds "(ostree:N)" to each title; after going back, N no longer follows the boot order,
    # so only the names are compared. The restarts below show which build starts.
    # The VM has two deployments, so N is one digit.
    names="${titles// (ostree:[0-9])/}"
    if [[ "$out" == 1 && "$names" == "OrielOS $OLD_VERSION;OrielOS $NEW_VERSION" ]]; then
        pass "The boot loader has OrielOS's menu settings, and the entries are $titles"
    else
        fail "The boot loader's settings or entries are wrong (12_orielos-menu.cfg found ${out:-0} times; entries: ${titles:-none})"
    fi
    if wait_for_good_boot; then
        pass "Reaching the desktop marks the boot as good ($(boot_flag) on the EFI system partition)"
    else
        fail "The desktop didn't mark the boot as good within 120 s (flag: $(boot_flag); see boot-success.txt)"
        vm_ssh "journalctl -b --no-pager -u orielos-boot-success.service; journalctl -b --no-pager --user-unit orielos-mark-boot-success.service" \
            >"$RESULTS/boot-success.txt" 2>&1 || true
        return 1
    fi

    if ! restart_watching_menu none; then
        fail "The VM did not come back after a restart"
        return 1
    fi
    read_status boot-menu-hidden
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "After a boot that reached the desktop, the boot menu stays hidden, and $OLD_VERSION, the version gone back to, starts"
    else
        fail "After a boot that reached the desktop: menu shown $MENU_SHOWN (see boot-menu-unexpected.png), then running ${BOOTED_VERSION:-unknown}, not $OLD_VERSION"
    fi

    # A start that never reaches the desktop, of a version that isn't new: the display manager
    # doesn't start. There's nothing to undo, so the next start is as usual, with no menu.
    vm_ssh systemctl set-default multi-user.target >/dev/null 2>&1 || true
    if ! restart_watching_menu none; then
        fail "The VM did not come back after a restart"
        return 1
    fi
    vm_ssh systemctl set-default graphical.target >/dev/null 2>&1 || true
    sleep 30
    if [[ "$(boot_flag)" == orielos_boot_ok=0 ]]; then
        pass "A start that doesn't reach the desktop leaves the start marked as not good"
    else
        fail "After a start without a desktop, the flag is $(boot_flag), not orielos_boot_ok=0"
    fi
    if ! restart_watching_menu none; then
        fail "The VM did not come back after a restart"
        return 1
    fi
    read_status boot-no-prompt
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "After a failed start of a version that isn't new, there's no menu or prompt, and $OLD_VERSION starts as usual"
    else
        fail "After a failed start of a version that isn't new: menu shown $MENU_SHOWN (see boot-menu-unexpected.png), then running ${BOOTED_VERSION:-unknown}"
    fi
    {
        printf '== after a failed start of a version that is not new, the boot menu showed:\n'
        printf '%s\n' "${MENU_TEXT:-nothing}"
    } >>"$RESULTS/boot-entries.txt"

    wait_for_good_boot || true
    if ! restart_watching_menu escape; then
        fail "The VM did not come back after pressing Esc at the boot menu"
        return 1
    fi
    read_status boot-menu-esc
    if [[ "$MENU_SHOWN" -eq 1 && "$MENU_DEFAULT" == "$OLD_VERSION" && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "Pressing Esc once while the menu is hidden shows it, and Enter starts the highlighted $OLD_VERSION (see boot-menu-esc.png)"
    else
        fail "Pressing Esc at boot: menu shown ${MENU_SHOWN}, highlighting ${MENU_DEFAULT:-nothing}, then running ${BOOTED_VERSION:-unknown}, not $OLD_VERSION"
    fi
}

step_undo_update() {
    local out flags deploy
    info "Step 14: an update that fails to reach the desktop twice is undone without asking"
    # Offer the new build again. With multi-user.target as the old build's default when the new one
    # is staged, the new build's /etc, merged from the old one's at the restart, has it too, so the
    # new build never reaches the desktop. The old build's own default goes back once the new one
    # is running.
    vm_ssh orielos-update forget "$NEW_DIGEST" >>"$RESULTS/service.txt" 2>&1 || true
    wait_for_good_boot || true
    out="$(service_run check)"
    read_status undo-staged
    flags="$(boot_flags | paste -sd ' ' -)"
    if [[ "$STAGED_DIGEST" == "$NEW_DIGEST" && "$flags" == *orielos_trial=1* ]]; then
        pass "Staging $NEW_VERSION again puts it on trial ($flags)"
    else
        fail "Staging $NEW_VERSION again: staged ${STAGED_DIGEST:-nothing}, flags ${flags:-none} (check result $(service_value "$out" result))"
        return 1
    fi
    vm_ssh systemctl set-default multi-user.target >/dev/null 2>&1 || true

    if ! restart_watching_menu none; then
        fail "The VM did not come back after restarting into $NEW_VERSION"
        return 1
    fi
    read_status undo-first
    deploy="$(vm_ssh "bootc status --format=json | jq -r '.status.rollback.ostree | \"/sysroot/ostree/deploy/\\(.stateroot)/deploy/\\(.checksum).\\(.deploySerial)\"'" 2>/dev/null)" || true
    if [[ "$BOOTED_DIGEST" != "$NEW_DIGEST" || "$deploy" != /sysroot/ostree/deploy/* ]] ||
        ! vm_ssh "mount -o remount,rw /sysroot && ln -sfn /usr/lib/systemd/system/graphical.target $deploy/etc/systemd/system/default.target" >/dev/null 2>&1; then
        fail "Could not set up the failing update: running ${BOOTED_VERSION:-unknown}, previous deployment ${deploy:-unknown}"
        return 1
    fi

    if ! restart_watching_menu none; then
        fail "The VM did not come back after the update's first failed start"
        return 1
    fi
    read_status undo-second
    flags="$(boot_flags | paste -sd ' ' -)"
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$NEW_DIGEST" && "$flags" == *orielos_fails=1* ]]; then
        pass "After the update's first failed start, it starts once more, with no menu ($flags)"
    else
        fail "After the update's first failed start: menu shown $MENU_SHOWN, running ${BOOTED_VERSION:-unknown}, flags ${flags:-none}"
        return 1
    fi

    if ! restart_watching_menu none; then
        fail "The VM did not come back after the update's second failed start"
        return 1
    fi
    read_status undone
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "After the update's second failed start, $OLD_VERSION starts by itself, with no menu or prompt"
    else
        fail "After the update's second failed start: menu shown $MENU_SHOWN, running ${BOOTED_VERSION:-unknown}, not $OLD_VERSION (see boot-entries.txt)"
        return 1
    fi
    out="$(vm_ssh "jq -r '.result + \" \" + (.rollbackQueued | tostring)' /var/lib/orielos/update/state.json; grep -c '$NEW_DIGEST' /var/lib/orielos/update/rejected-digests" 2>/dev/null | paste -sd ' ' -)" || true
    if [[ "$out" == "went-back false 1" ]]; then
        pass "OrielOS keeps $OLD_VERSION as the default and rejects $NEW_VERSION (state: $out)"
    else
        fail "After undoing the update, the state, queue and rejection are '$out', not 'went-back false 1'"
    fi
    if wait_for_notifier && wait_for_good_boot; then
        sleep 5
        vm_qmp "shot:$RESULTS/update-undone.png" || true
        out="$(service_value "$(vm_ssh "$(notifier_script)" 2>/dev/null)" tooltip)" || true
        if [[ "$out" == *"went back to the previous version"* ]]; then
            pass "The desktop starts and the notifier tells the user the update was undone (tooltip: $out; see update-undone.png)"
        else
            fail "After undoing the update, the notifier's tooltip says '${out:-nothing}' (see update-undone.png)"
        fi
    else
        fail "After undoing the update, the desktop or the notifier didn't start (see notifier.txt)"
    fi
    if ! restart_watching_menu none; then
        fail "The VM did not come back after a restart"
        return 1
    fi
    read_status undone-next
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "$OLD_VERSION stays the version that starts, with no menu"
    else
        fail "After undoing the update, the next start ran ${BOOTED_VERSION:-unknown} (menu shown $MENU_SHOWN)"
    fi
}

step_last_resort_and_removal() {
    local out entries
    info "Step 15: the boot menu as the last resort, and removing the previous build"
    # The flags as they are when the build OrielOS kept also fails to reach the desktop.
    wait_for_good_boot || true
    set_boot_flags orielos_boot_ok=0 orielos_trial=kept orielos_fails=0
    if ! restart_watching_menu enter; then
        fail "The VM did not come back after the last-resort boot menu"
        return 1
    fi
    read_status last-resort
    if [[ "$MENU_SHOWN" -eq 1 && "$MENU_DEFAULT" == "$OLD_VERSION" && "$BOOTED_DIGEST" == "$OLD_DIGEST" &&
        " $MENU_ENTRIES " == *" $NEW_VERSION "* ]]; then
        pass "When the kept version fails to start too, the boot menu appears, lists $MENU_ENTRIES and highlights $OLD_VERSION (see boot-menu-last-resort.png)"
        show_output "$MENU_TEXT"
    else
        fail "The last-resort boot menu: shown $MENU_SHOWN, listing ${MENU_ENTRIES:-nothing}, highlighting ${MENU_DEFAULT:-nothing}, then running ${BOOTED_VERSION:-unknown}"
    fi

    # 15 days after the running build first started, the check removes the previous one.
    vm_ssh "sed -i \"s/^since=.*/since=\$(date -u -d '15 days ago' +%Y-%m-%dT%H:%M:%SZ)/\" /var/lib/orielos/update/running" >/dev/null 2>&1 || true
    out="$(service_run check)"
    read_status removed
    entries="$(vm_ssh "ls /boot/loader/entries/ | wc -l" 2>/dev/null)" || true
    if [[ "$(status_field rollback imageDigest)" == "" && "$entries" == 1 ]] &&
        [[ "$(vm_ssh "jq -r '.previous' /var/lib/orielos/update/state.json" 2>/dev/null)" == null ]]; then
        pass "15 days after $OLD_VERSION first started, the check removes the previous build (one boot entry left; going back no longer offered)"
    else
        fail "Removing the previous build after 15 days: rollback $(status_field rollback version), $entries boot entries (check result $(service_value "$out" result))"
    fi
}

step_remove_previous() {
    local out entries removal
    info "Step 16: install the update once more, then remove the previous version from Settings → Update"
    vm_ssh orielos-update forget "$NEW_DIGEST" >>"$RESULTS/service.txt" 2>&1 || true
    out="$(service_run check)"
    read_status remove-staged
    if [[ "$STAGED_DIGEST" != "$NEW_DIGEST" ]]; then
        fail "Staging $NEW_VERSION once more staged ${STAGED_DIGEST:-nothing} (check result $(service_value "$out" result))"
        return 1
    fi
    if ! restart_vm; then
        fail "The VM did not come back after restarting into $NEW_VERSION"
        return 1
    fi
    read_status remove-updated
    if [[ "$BOOTED_DIGEST" != "$NEW_DIGEST" ]] || ! wait_for_notifier || ! wait_for_good_boot; then
        fail "After restarting into $NEW_VERSION, it isn't running or its desktop didn't start (running ${BOOTED_VERSION:-unknown})"
        return 1
    fi
    removal="$(state_value .previous.removedAfter)"
    if ! open_update_settings settings-previous; then
        fail "Clicking the notifier's tray icon didn't open Settings → Update within 60 s (see settings.txt)"
        return 1
    fi
    if [[ "$(state_value .previous.version)" == "$OLD_VERSION" && "$removal" == 20* ]]; then
        pass "Settings → Update offers going back to $OLD_VERSION, kept until $removal (see settings-previous.png)"
    else
        fail "The state names no previous build to show: previous $(state_value .previous)"
    fi
    if ! open_update_window settings-previous-window; then
        fail "kcmshell6 $SETTINGS_MODULE didn't start in $TEST_USER's session within 60 s"
        return 1
    fi

    # Cancel has the focus in the question, so choose Remove by its mnemonic.
    vm_qmp "keys:alt+m" "wait:3" "shot:$RESULTS/remove-question.png" "keys:alt+e" || true
    answer_password remove-password
    if wait_for_state .previous null 180; then
        vm_qmp "wait:3" "shot:$RESULTS/settings-removed.png" || true
        read_status removed-from-settings
        entries="$(vm_ssh "ls /boot/loader/entries/ | wc -l" 2>/dev/null)" || true
        if [[ -z "$(status_field rollback imageDigest)" && "$entries" == 1 ]]; then
            pass "Removing the previous version on the page asks first, then for a password, and removes $OLD_VERSION; going back is no longer offered (see remove-question.png, remove-password.png, settings-removed.png)"
        else
            fail "After removing the previous version on the page: rollback $(status_field rollback version), $entries boot entries"
        fi
    else
        vm_qmp "shot:$RESULTS/settings-removed.png" || true
        fail "Removing the previous version on the page didn't remove it within 180 s (see remove-question.png, remove-password.png, settings-removed.png)"
    fi
}

step_stage_again() {
    local out rc=0
    info "Step 7: stage the rolled-back build again"
    out="$(vm_ssh orielos-update stage "$REMOTE_ARCHIVE" 2>&1)" || rc=$?
    printf '%s\n' "$out" >"$RESULTS/stage-again.txt"
    read_status final
    if [[ "$rc" -eq 3 && -z "$STAGED_DIGEST" ]]; then
        pass "Staging the rolled-back build again is refused with exit status 3"
        show_output "$out"
    else
        fail "Staging the rolled-back build again exited with status $rc, not 3 (staged: ${STAGED_DIGEST:-none})"
        show_output "$out"
    fi
}

main() {
    local original=("$@") details run_id tag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --old | --new | --timeout | --memory | --cpus | --results)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --old) OLD="$2" ;;
                    --new) NEW="$2" ;;
                    --timeout) TIMEOUT="$2" ;;
                    --memory) MEMORY="$2" ;;
                    --cpus) CPUS="$2" ;;
                    --results) RESULTS="$2" ;;
                esac
                shift 2
                ;;
            --keep)
                KEEP=1
                shift
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "unknown option: $1"
                ;;
        esac
    done
    [[ -n "$OLD" ]] || die "--old is required (see --help)"
    [[ -n "$NEW" ]] || die "--new is required (see --help)"
    [[ -f "$NEW" && -r "$NEW" ]] || die "cannot read $NEW"
    [[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -gt 0 ]] || die "--timeout needs a number of seconds"
    [[ "$MEMORY" =~ ^[0-9]+$ ]] || die "--memory needs a number of MiB"
    [[ "$CPUS" =~ ^[0-9]+$ ]] || die "--cpus needs a number"

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host
    NEW="$(realpath "$NEW")"
    SSH_WAIT="$TIMEOUT"

    tag="$(basename "$NEW" .ociarchive)"
    run_id="$(printf 'update-%s-%s' "${tag#orielos-}" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id; results in $RESULTS"
    details="$(archive_info "$NEW")" || die "$NEW is not an OCI archive from tools/build-image.sh"
    NEW_DIGEST="${details%% *}"
    NEW_VERSION="${details#* }"

    if step_boot_old && step_user_data && step_copy && step_stage && step_update_boot &&
        step_rollback && step_stage_again && step_service_source && step_service_channel &&
        step_service_notify && step_service_restart && step_update_settings && step_boot_menu && step_undo_update &&
        step_last_resort_and_removal && step_remove_previous; then
        :
    else
        fail "The test stopped early; the remaining steps did not run"
    fi
    stop_pid "$WORK/qemu.pid"
    full_log >"$RESULTS/serial.log"

    if [[ "$FAILED" -eq 0 ]]; then
        say "$C_GREEN" PASS "All $PASSED checks passed"
        return 0
    fi
    say "$C_RED" FAIL "$FAILED of $((PASSED + FAILED)) checks failed"
    return 1
}

main "$@"
