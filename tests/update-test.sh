#!/usr/bin/env bash
# Tests updating and rolling back an installed OrielOS. Installs the old build to a disk file,
# boots it headless under QEMU/KVM with Secure Boot and a software TPM, finishes setup and
# creates user data over SSH through a vsock device, then stages the new build from an OCI
# archive with orielos-update, restarts into it, rolls back, restarts into the old build again
# and checks that the rolled-back build is refused. Prints PASS/FAIL per check.
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

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
        step_rollback && step_stage_again; then
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
