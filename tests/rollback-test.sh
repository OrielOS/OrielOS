#!/usr/bin/env bash
# Tests that an update which can't reach the desktop is undone without asking. Installs build A to
# a disk file, boots it headless under QEMU/KVM with Secure Boot and a software TPM, finishes setup
# and logs the test user in through SDDM's autologin, so the start counts as good. Then it stages
# build B from an OCI archive with orielos-update and makes B unable to reach the desktop: A's
# default target is multi-user.target when B is staged, so B's /etc inherits it. It checks that B
# starts twice and fails, with no boot menu, that the third start is A by itself, which OrielOS
# keeps while rejecting B, and that A keeps starting after that. The boot menu is read from the
# serial console. Prints PASS/FAIL per check.
#
# Usage: tests/rollback-test.sh --old IMAGE_OR_ARCHIVE --new ARCHIVE [--timeout SECONDS]
#                               [--memory MIB] [--cpus N] [--results DIR] [--keep] [--help]
#   --old REF|FILE      build A, installed first: an image in Podman (such as
#                       localhost/orielos:44.20261025) or an OCI archive from tools/build-image.sh
#   --new FILE          build B, the update that fails: an OCI archive from tools/build-image.sh
#   --timeout SECONDS   time to wait for SSH after power-on and after each restart (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, the status files and summary.txt go
#                       (default tests/results/<run id>)
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is
# rollback-<B's tag>-<UTC time>. Runs as root; re-executes itself through sudo otherwise.
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
BOOT_ID=""
STATUS_JSON=""
BOOTED_DIGEST=""
BOOTED_VERSION=""
STAGED_DIGEST=""
SERIAL_MARK=0
MENU_SHOWN=0

usage() {
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Print the manifest digest and the version label of the build in an OCI archive, without
# importing it: "<digest> <version>".
archive_info() {
    python3 -I - "$1" <<'PY'
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

# Print the boot menu's flags from the EFI system partition in the VM, one name=value per line.
boot_flags() {
    vm_ssh /usr/libexec/orielos/boot-flags status 2>/dev/null | grep -v '=$' || true
}

# Wait up to 120 s for this boot's desktop session to mark the boot as good. Returns 1 if it doesn't.
wait_for_good_boot() {
    local start=$SECONDS
    while ((SECONDS - start < 120)); do
        boot_flags | grep -qx 'orielos_boot_ok=1' && return 0
        sleep 3
    done
    return 1
}

# Wait for the VM to come back as a new boot after a restart. Returns 1 if it doesn't.
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

# Restart the VM and watch the serial console, where the firmware copies GRUB's screen, until the
# kernel starts. Sets MENU_SHOWN to 1 if the boot menu appeared, then waits for the new boot.
# Returns 1 if the VM doesn't come back.
restart_watching_menu() {
    local start text
    MENU_SHOWN=0
    SERIAL_MARK="$(stat -c %s "$WORK/serial.log" 2>/dev/null || echo 0)"
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    start=$SECONDS
    while ((SECONDS - start < 180)); do
        text="$(tail -c +"$((SERIAL_MARK + 1))" "$WORK/serial.log" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -cd '\11\12\40-\176')"
        if [[ "$text" == *"keys to select which entry is highlighted"* ]]; then
            MENU_SHOWN=1
            vm_qmp "shot:$RESULTS/boot-menu-unexpected.png" || true
            break
        fi
        [[ "$text" == *"Linux version"* ]] && break
        sleep 0.2
    done
    wait_for_new_boot
}

step_install() {
    info "Step 1: install build A, finish setup and reach the desktop"
    if [[ -f "$OLD" ]]; then
        ARCHIVE="$OLD"
        IMAGE="localhost/orielos-archive:$(basename "$OLD" .ociarchive)"
        load_archive
    else
        IMAGE="$OLD"
    fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"
    OLD_VERSION="$(podman image inspect --format '{{index .Labels "org.opencontainers.image.version"}}' "$IMAGE")"
    info "Build A: $IMAGE, version $OLD_VERSION"
    info "Build B: $NEW, version $NEW_VERSION ($NEW_DIGEST)"
    setup_ssh
    install_image
    start_vm
    if ! wait_for_ssh; then
        fail "Build A boots: SSH over vsock did not answer"
        return 1
    fi
    BOOT_ID="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    finish_setup
    if [[ "$FINISH_OK" -ne 1 ]] || ! vm_ssh "mkdir -p /etc/sddm.conf.d
        printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' $TEST_USER >/etc/sddm.conf.d/99-rollback-test-autologin.conf" >/dev/null 2>&1; then
        fail "Setup could not be finished in build A"
        return 1
    fi
    # Setup is done, so this start goes to the sign-in screen and the autologin.
    if ! restart_watching_menu; then
        fail "Build A did not come back after setup"
        return 1
    fi
    read_status a
    OLD_DIGEST="$BOOTED_DIGEST"
    if [[ "$BOOTED_VERSION" == "$OLD_VERSION" ]] && wait_for_good_boot; then
        pass "Build A ($OLD_VERSION) starts and reaches the desktop ($(boot_flags | paste -sd ' ' -))"
    else
        fail "Build A runs ${BOOTED_VERSION:-unknown} or didn't reach the desktop (flags: $(boot_flags | paste -sd ' ' -))"
        return 1
    fi
}

step_stage() {
    local remote="/var/tmp/${NEW##*/}" out rc=0 flags
    info "Step 2: stage build B and make it unable to reach the desktop"
    vm_copy "$NEW" "$remote" || true
    out="$(SSH_TIMEOUT=1800 vm_ssh orielos-update stage "$remote" 2>&1)" || rc=$?
    printf '%s\n' "$out" >"$RESULTS/stage.txt"
    read_status staged
    flags="$(boot_flags | paste -sd ' ' -)"
    if [[ "$rc" -eq 0 && "$STAGED_DIGEST" == "$NEW_DIGEST" && "$flags" == *orielos_trial=1* ]]; then
        pass "Build B ($NEW_VERSION) is staged and on trial ($flags)"
    else
        fail "Staging build B exited with $rc and staged ${STAGED_DIGEST:-nothing} (flags: ${flags:-none}; see stage.txt)"
        return 1
    fi
    # B's /etc is merged from A's at the restart, so B gets this default too. A's own default goes
    # back on disk once B is running.
    vm_ssh systemctl set-default multi-user.target >/dev/null 2>&1 || true
}

step_fail_twice() {
    local deploy flags
    info "Step 3: build B starts twice and fails, with no boot menu"
    if ! restart_watching_menu; then
        fail "The VM did not come back after restarting into build B"
        return 1
    fi
    read_status b-first
    deploy="$(vm_ssh "bootc status --format=json | jq -r '.status.rollback.ostree | \"/sysroot/ostree/deploy/\\(.stateroot)/deploy/\\(.checksum).\\(.deploySerial)\"'" 2>/dev/null)" || true
    if [[ "$BOOTED_DIGEST" != "$NEW_DIGEST" || "$MENU_SHOWN" -ne 0 || "$deploy" != /sysroot/ostree/deploy/* ]] ||
        ! vm_ssh "mount -o remount,rw /sysroot && ln -sfn /usr/lib/systemd/system/graphical.target $deploy/etc/systemd/system/default.target" >/dev/null 2>&1; then
        fail "Build B's first start: running ${BOOTED_VERSION:-unknown}, menu shown $MENU_SHOWN, build A's deployment ${deploy:-unknown}"
        return 1
    fi
    pass "Build B starts first, with no boot menu, and doesn't reach the desktop"
    if ! restart_watching_menu; then
        fail "The VM did not come back after build B's first failed start"
        return 1
    fi
    read_status b-second
    flags="$(boot_flags | paste -sd ' ' -)"
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$NEW_DIGEST" && "$flags" == *orielos_fails=1* ]]; then
        pass "After one failed start, build B starts once more, with no boot menu ($flags)"
    else
        fail "After build B's first failed start: menu shown $MENU_SHOWN, running ${BOOTED_VERSION:-unknown}, flags ${flags:-none}"
        return 1
    fi
}

step_undone() {
    local out
    info "Step 4: the third start is build A, kept by itself"
    if ! restart_watching_menu; then
        fail "The VM did not come back after build B's second failed start"
        return 1
    fi
    read_status undone
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "After build B's second failed start, build A ($OLD_VERSION) starts by itself, with no boot menu or prompt"
    else
        fail "After build B's second failed start: menu shown $MENU_SHOWN, running ${BOOTED_VERSION:-unknown}, not $OLD_VERSION"
        return 1
    fi
    out="$(vm_ssh "jq -r '.result + \" \" + (.rollbackQueued | tostring)' /var/lib/orielos/update/state.json; grep -c '$NEW_DIGEST' /var/lib/orielos/update/rejected-digests" 2>/dev/null | paste -sd ' ' -)" || true
    if [[ "$out" == "went-back false 1" ]]; then
        pass "OrielOS keeps build A as the default and rejects build B (state: $out)"
    else
        fail "After undoing the update, the state, queue and rejection are '$out', not 'went-back false 1'"
    fi
    if wait_for_good_boot; then
        pass "Build A reaches the desktop again"
    else
        fail "Build A didn't reach the desktop after the update was undone (flags: $(boot_flags | paste -sd ' ' -))"
    fi
    if ! restart_watching_menu; then
        fail "The VM did not come back after a restart"
        return 1
    fi
    read_status after
    if [[ "$MENU_SHOWN" -eq 0 && "$BOOTED_DIGEST" == "$OLD_DIGEST" ]]; then
        pass "Build A stays the version that starts, with no boot menu"
    else
        fail "After undoing the update, the next start ran ${BOOTED_VERSION:-unknown} (menu shown $MENU_SHOWN)"
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
    run_id="$(printf 'rollback-%s-%s' "${tag#orielos-}" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
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

    if step_install && step_stage && step_fail_twice && step_undone; then
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
