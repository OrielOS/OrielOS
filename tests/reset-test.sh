#!/usr/bin/env bash
# Tests Reset this PC. Installs a build to a disk file and boots it headless under QEMU/KVM with
# Secure Boot and a software TPM, with two more disks: one standing in for another operating
# system's drive, filled with random bytes, and one holding the update source, an OCI directory
# with the same build as the stable channel. The VM also gets a stand-in for Windows' boot files on
# the EFI system partition. By default the home folders are then moved to a Btrfs subvolume of
# their own, mounted from /etc/fstab, as the installer lays them out; --layout bootc keeps them in
# /var, as "bootc install" does. Over SSH through a vsock device, the test:
#   1. gets a reset ready and cancels it, and checks that nothing changed;
#   2. resets keeping files: the account, its password and its file stay, a system setting and a
#      file in /var don't, first-run setup doesn't come back, the old system is removed once the
#      sign-in screen is up, and the kernel arguments are the same as before;
#   3. resets removing everything: first-run setup starts, no account or home folder is left, and
#      the old system is removed.
# After each reset, Windows' boot files must be unchanged, and when the VM is off the other drive
# must match its checksum byte for byte. Prints PASS/FAIL per check.
#
# Usage: tests/reset-test.sh --archive FILE [--layout installer|bootc] [--timeout SECONDS]
#                            [--memory MIB] [--cpus N] [--results DIR] [--keep] [--help]
#   --archive FILE      the build to install and reset to: an OCI archive from tools/build-image.sh
#   --layout NAME       installer (default): home folders on a Btrfs subvolume of their own;
#                       bootc: home folders in /var
#   --timeout SECONDS   time to wait for SSH after power-on and after each restart (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, the state files and summary.txt go
#                       (default tests/results/<run id>)
#   --keep              keep the disks and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is
# reset-<build's tag>-<UTC time>. Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
IMAGE=""
ARCHIVE=""
LAYOUT=installer
TIMEOUT=600
MEMORY=6144
CPUS=4
RESULTS=""
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
SUMMARY=""
BOOT_ID=""
KEEP_FILE=""
KEEP_TEXT=""
# The drive standing in for another operating system's, and its checksum before the test.
OTHER_DISK=""
OTHER_SUM=""
# The disk with the update source, mounted at SOURCE_MOUNT in the VM.
SOURCE_DISK=""
SOURCE_MOUNT="/mnt/orielos-test-source"
# The stand-in for Windows' boot files on the EFI system partition, and its checksum.
WINDOWS_FILE="EFI/Microsoft/Boot/bootmgfw.efi"
WINDOWS_SUM=""
# The kernel command line before any reset, without the arguments only one start has.
KARGS_BEFORE=""
ESP_TYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Restart the VM from inside, and wait for SSH to come back as a new boot.
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

# One field of the reset's state file in the VM: reset_state <jq filter>
reset_state() {
    vm_ssh "jq -r '$1' /var/lib/orielos/reset/state.json 2>/dev/null" 2>/dev/null || true
}

# The stateroots in the VM, space-separated.
stateroots() {
    vm_ssh 'ls /sysroot/ostree/deploy' 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

# The kernel command line without the arguments only one start or one build has.
machine_cmdline() {
    vm_ssh "tr ' ' '\n' </proc/cmdline | grep -v -e '^BOOT_IMAGE=' -e '^ostree=' -e '^orielos.build=' | sort | tr '\n' ' '" 2>/dev/null || true
}

# The checksum of the stand-in for Windows' boot files, read from the EFI system partition.
windows_sum() {
    vm_ssh "set -e
        esp=\$(lsblk -lnpo NAME,PARTTYPE /dev/vda | awk 'tolower(\$2) == \"$ESP_TYPE\" {print \$1; exit}')
        dir=\$(mktemp -d)
        mount -o ro \"\$esp\" \"\$dir\"
        sha256sum \"\$dir/$WINDOWS_FILE\" | cut -d' ' -f1
        umount \"\$dir\"
        rmdir \"\$dir\"" 2>/dev/null || true
}

check_windows_files() {
    local now
    now="$(windows_sum)"
    if [[ -n "$now" && "$now" == "$WINDOWS_SUM" ]]; then
        pass "Windows' boot files are unchanged $1"
    else
        fail "Windows' boot files changed $1 (sha256 ${now:-missing}, was $WINDOWS_SUM)"
    fi
}

mount_source() {
    vm_ssh "mkdir -p $SOURCE_MOUNT && { mountpoint -q $SOURCE_MOUNT || mount /dev/vdc $SOURCE_MOUNT; }" >/dev/null 2>&1
}

# Get a reset ready in the VM and wait until it is: prepare_reset <keep|erase>. Returns 1 if it
# fails. Notes whether the download's progress was seen.
prepare_reset() {
    local mode="$1" phase="" start=$SECONDS saw_progress=0 downloaded
    mount_source || {
        fail "The update source disk could not be mounted"
        return 1
    }
    if ! vm_ssh "orielos-reset start $mode" >"$RESULTS/start-$mode.txt" 2>&1; then
        fail "orielos-reset start $mode failed: $(head -n1 "$RESULTS/start-$mode.txt")"
        return 1
    fi
    while ((SECONDS - start < 1800)); do
        phase="$(reset_state .phase)"
        downloaded="$(reset_state .downloaded)"
        if [[ "$phase" == downloading && "$downloaded" =~ ^[0-9]+$ && "$downloaded" -gt 0 ]]; then saw_progress=1; fi
        [[ "$phase" == ready || "$phase" == failed ]] && break
        sleep 1
    done
    vm_ssh 'cat /var/lib/orielos/reset/state.json /var/lib/orielos/reset/prepare.log' >"$RESULTS/prepare-$mode.txt" 2>&1 || true
    if [[ "$phase" != ready ]]; then
        fail "The reset ($mode) got ready: it ended as ${phase:-nothing} ($(reset_state .message))"
        return 1
    fi
    pass "The reset ($mode) got ready in $((SECONDS - start)) s"
    if [[ "$saw_progress" -eq 1 ]]; then
        pass "The download's progress was shown while getting the reset ($mode) ready"
    else
        warn "The download's progress wasn't seen (the copy from the local source may have been too quick)"
    fi
}

step_install() {
    local out
    info "Step 1: install the build, with another drive and Windows' boot files beside it"
    setup_ssh
    install_image
    OTHER_DISK="$WORK/other.raw"
    head -c $((64 * 1024 * 1024)) /dev/urandom >"$OTHER_DISK"
    OTHER_SUM="$(sha256sum "$OTHER_DISK" | cut -d' ' -f1)"
    SOURCE_DISK="$WORK/source.raw"
    truncate -s 16G "$SOURCE_DISK"
    VM_EXTRA_ARGS=(-drive "file=$OTHER_DISK,format=raw,if=virtio" -drive "file=$SOURCE_DISK,format=raw,if=virtio")
    start_vm
    if ! wait_for_ssh; then
        fail "The build boots: SSH over vsock did not answer"
        return 1
    fi
    BOOT_ID="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    finish_setup
    KEEP_FILE="/var/home/$TEST_USER/keepme.txt"
    KEEP_TEXT="$(head -c 24 /dev/urandom | base64)"
    if [[ "$FINISH_OK" -ne 1 ]]; then
        fail "Setup could not be finished"
        return 1
    fi
    if ! out="$(vm_ssh "set -e
        printf '%s:%s\n' $TEST_USER orielos-test-pass | chpasswd
        printf '%s\n' '$KEEP_TEXT' >$KEEP_FILE
        chown $TEST_USER: $KEEP_FILE
        printf 'changed\n' >/etc/orielos-test-setting
        mkdir -p /var/lib/orielos-test && printf 'state\n' >/var/lib/orielos-test/state
        esp=\$(lsblk -lnpo NAME,PARTTYPE /dev/vda | awk 'tolower(\$2) == \"$ESP_TYPE\" {print \$1; exit}')
        dir=\$(mktemp -d)
        mount \"\$esp\" \"\$dir\"
        mkdir -p \"\$dir/\$(dirname $WINDOWS_FILE)\"
        head -c 65536 /dev/urandom >\"\$dir/$WINDOWS_FILE\"
        umount \"\$dir\"
        rmdir \"\$dir\"" 2>&1)"; then
        fail "User data, a system setting and Windows' boot files were created: ${out:-no output}"
        return 1
    fi
    WINDOWS_SUM="$(windows_sum)"
    pass "User data, a system setting and Windows' boot files were created"
}

# Move the home folders to a Btrfs subvolume of their own, mounted at /home from /etc/fstab, as the
# installer lays them out.
step_layout() {
    local out
    if [[ "$LAYOUT" != installer ]]; then
        info "Step 2: the home folders stay in /var (--layout bootc)"
        return 0
    fi
    info "Step 2: move the home folders to a Btrfs subvolume of their own, as the installer does"
    if ! out="$(vm_ssh "set -e
        command -v btrfs >/dev/null
        uuid=\$(findmnt -no UUID /sysroot)
        unshare --mount --propagation private sh -c 'mount -o remount,rw /sysroot && btrfs subvolume create /sysroot/home >/dev/null && chcon --reference=/var/home /sysroot/home && cp -a /var/home/. /sysroot/home/'
        printf 'UUID=%s /home btrfs subvol=home,compress=zstd:1 0 0\n' \"\$uuid\" >>/etc/fstab" 2>&1)"; then
        fail "The home folders were moved to a subvolume: ${out:-no output}"
        return 1
    fi
    restart_vm || {
        fail "The VM came back after moving the home folders"
        return 1
    }
    if vm_ssh "findmnt -no FSROOT /var/home | grep -qx /home && test -f $KEEP_FILE" >/dev/null 2>&1; then
        pass "The home folders are on a subvolume of their own, mounted at /var/home"
    else
        fail "The home folders aren't on their own subvolume after restarting"
        return 1
    fi
}

step_source() {
    local remote="$SOURCE_MOUNT/build.ociarchive" out start=$SECONDS
    info "Step 3: put the build on the update source disk as the stable channel ($(du -h "$ARCHIVE" | cut -f1))"
    if ! vm_ssh "mkfs.ext4 -q /dev/vdc" >/dev/null 2>&1 || ! mount_source; then
        fail "The update source disk was set up"
        return 1
    fi
    vm_copy "$ARCHIVE" "$remote" || true
    if ! out="$(SSH_TIMEOUT=1800 vm_ssh "set -e
        skopeo copy --quiet oci-archive:$remote oci:$SOURCE_MOUNT/channel:stable
        rm -f $remote
        mkdir -p /etc/orielos
        printf 'source=oci:%s\n' $SOURCE_MOUNT/channel >/etc/orielos/update.conf" 2>&1)"; then
        fail "The update source was set up: ${out:-no output}"
        return 1
    fi
    KARGS_BEFORE="$(machine_cmdline)"
    pass "The update source is ready ($((SECONDS - start)) s)"
}

step_cancel() {
    local roots
    info "Step 4: get a reset ready, then cancel it"
    prepare_reset keep || return 1
    roots="$(stateroots)"
    if [[ "$roots" == *" "* ]]; then
        pass "The reset is a second system beside the running one ($roots)"
    else
        fail "The reset set up no second system (stateroots: $roots)"
    fi
    if vm_ssh "orielos-update check; jq -r .result /var/lib/orielos/update/state.json" 2>/dev/null | grep -qx reset-pending; then
        pass "Updates wait while a reset is ready"
    else
        fail "An update check went ahead while a reset was ready"
    fi
    vm_ssh orielos-reset cancel >"$RESULTS/cancel.txt" 2>&1 || true
    roots="$(stateroots)"
    if [[ "$roots" == default && "$(reset_state .phase)" == cancelled ]] && ! vm_ssh 'test -e /var/lib/orielos/reset/pending' 2>/dev/null; then
        pass "Cancelling removes the second system and lets updates go on"
    else
        fail "After cancelling, the stateroots are $roots and the state is $(reset_state .phase)"
        return 1
    fi
}

# Wait up to five minutes for the reset start to remove the old system.
wait_for_finish() {
    local start=$SECONDS
    while ((SECONDS - start < 300)); do
        [[ "$(reset_state .phase)" == "done" ]] && return 0
        sleep 2
    done
    return 1
}

step_reset_keep() {
    local new text owner
    info "Step 5: reset keeping files"
    prepare_reset keep || return 1
    new="$(vm_ssh "sed -n 's/^new=//p' /var/lib/orielos/reset/prepared" 2>/dev/null)" || true
    restart_vm || {
        fail "The VM came back after the reset (keep)"
        return 1
    }
    if vm_ssh "grep -q 'ostree=/ostree/boot.[01]/$new/' /proc/cmdline" 2>/dev/null; then
        pass "The reset start runs the new system ($new)"
    else
        fail "The reset start doesn't run the new system, $new: $(vm_ssh cat /proc/cmdline 2>/dev/null)"
        return 1
    fi
    text="$(vm_ssh cat "$KEEP_FILE" 2>/dev/null)" || true
    owner="$(vm_ssh stat -c %U "$KEEP_FILE" 2>/dev/null)" || true
    if [[ "$text" == "$KEEP_TEXT" && "$owner" == "$TEST_USER" ]]; then
        pass "The user's file stays, with its owner ($KEEP_FILE)"
    else
        fail "The user's file is ${text:-missing}, owned by ${owner:-nobody}"
    fi
    if vm_ssh "getent shadow $TEST_USER | grep -q '^$TEST_USER:\\\$' && id -nG $TEST_USER | grep -qw wheel" 2>/dev/null; then
        pass "The account, its password and its administrator group stay"
    else
        fail "The account, its password or its group didn't stay"
    fi
    if vm_ssh 'test ! -e /etc/orielos-test-setting && test ! -e /var/lib/orielos-test && test -e /etc/plasma-setup-done' 2>/dev/null; then
        pass "System settings and /var are fresh, and first-run setup doesn't come back"
    else
        fail "A system setting or /var survived the reset, or first-run setup's mark is missing"
    fi
    if wait_for_finish && [[ "$(stateroots)" == "$new" ]]; then
        pass "The old system is removed once the sign-in screen is up"
    else
        fail "The old system wasn't removed (stateroots: $(stateroots); state $(reset_state .phase))"
    fi
    if [[ "$(machine_cmdline)" == "$KARGS_BEFORE" ]]; then
        pass "The kernel arguments are the same as before the reset"
    else
        fail "The kernel arguments changed: $(machine_cmdline) (were $KARGS_BEFORE)"
    fi
    if [[ "$LAYOUT" == installer ]] && ! vm_ssh "findmnt -no FSROOT /var/home | grep -qx /home" 2>/dev/null; then
        fail "The home folders' subvolume isn't mounted after the reset"
    fi
    if vm_ssh "bootc status --format=json | jq -e '.status.booted.image.imageDigest | startswith(\"sha256:\")'" >/dev/null 2>&1; then
        pass "bootc knows the new system's build, so updates go on"
    else
        fail "bootc doesn't know the new system's build"
    fi
    check_windows_files "after resetting and keeping files"
}

step_reset_erase() {
    local new users
    info "Step 6: reset removing everything"
    prepare_reset erase || return 1
    new="$(vm_ssh "sed -n 's/^new=//p' /var/lib/orielos/reset/prepared" 2>/dev/null)" || true
    restart_vm || {
        fail "The VM came back after the reset (erase)"
        return 1
    }
    if vm_ssh "grep -q 'ostree=/ostree/boot.[01]/$new/' /proc/cmdline" 2>/dev/null; then
        pass "The reset start runs the new system ($new)"
    else
        fail "The reset start doesn't run the new system, $new"
        return 1
    fi
    users="$(vm_ssh "awk -F: '\$3 >= 1000 && \$3 < 60000' /etc/passwd" 2>/dev/null)" || true
    if [[ -z "$users" ]] && vm_ssh 'test ! -e /etc/plasma-setup-done && systemctl show -p Result --value plasma-setup.service | grep -qx success' 2>/dev/null; then
        pass "First-run setup starts, with no account left"
    else
        fail "First-run setup didn't start, or accounts are left: ${users:-none}"
    fi
    if wait_for_finish && [[ "$(stateroots)" == "$new" ]]; then
        pass "The old system is removed once first-run setup is up"
    else
        fail "The old system wasn't removed (stateroots: $(stateroots); state $(reset_state .phase))"
    fi
    if [[ -z "$(vm_ssh 'ls -A /var/home' 2>/dev/null)" ]]; then
        pass "No home folder is left"
    else
        fail "Home folders are left: $(vm_ssh 'ls -A /var/home' 2>/dev/null)"
    fi
    check_windows_files "after resetting and removing everything"
}

check_other_disk() {
    local now
    now="$(sha256sum "$OTHER_DISK" | cut -d' ' -f1)"
    if [[ "$now" == "$OTHER_SUM" ]]; then
        pass "The other drive is unchanged, byte for byte"
    else
        fail "The other drive changed (sha256 $now, was $OTHER_SUM)"
    fi
}

main() {
    local original=("$@") run_id tag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --archive | --layout | --timeout | --memory | --cpus | --results)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --archive) ARCHIVE="$2" ;;
                    --layout) LAYOUT="$2" ;;
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
    [[ -n "$ARCHIVE" ]] || die "--archive is required (see --help)"
    [[ -f "$ARCHIVE" && -r "$ARCHIVE" ]] || die "cannot read $ARCHIVE"
    [[ "$LAYOUT" == installer || "$LAYOUT" == bootc ]] || die "--layout is installer or bootc"
    [[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -gt 0 ]] || die "--timeout needs a number of seconds"
    [[ "$MEMORY" =~ ^[0-9]+$ ]] || die "--memory needs a number of MiB"
    [[ "$CPUS" =~ ^[0-9]+$ ]] || die "--cpus needs a number"

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host
    ARCHIVE="$(realpath "$ARCHIVE")"
    SSH_WAIT="$TIMEOUT"

    tag="$(basename "$ARCHIVE" .ociarchive)"
    run_id="$(printf 'reset-%s-%s' "${tag#orielos-}" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id ($LAYOUT layout); results in $RESULTS"
    IMAGE="localhost/orielos-archive:$tag"
    load_archive

    if step_install && step_layout && step_source && step_cancel && step_reset_keep && step_reset_erase; then
        :
    else
        fail "The test stopped early; the remaining steps did not run"
    fi
    stop_pid "$WORK/qemu.pid"
    full_log >"$RESULTS/serial.log"
    if [[ -n "$OTHER_DISK" ]]; then check_other_disk; fi

    if [[ "$FAILED" -eq 0 ]]; then
        say "$C_GREEN" PASS "All $PASSED checks passed"
        return 0
    fi
    say "$C_RED" FAIL "$FAILED of $((PASSED + FAILED)) checks failed"
    return 1
}

main "$@"
