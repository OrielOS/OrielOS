#!/usr/bin/env bash
# A short check of a freshly built image, for CI before it's signed and published. Installs the
# image to a disk file and boots it headless under QEMU/KVM with Secure Boot and a software TPM,
# finishes setup over SSH through a vsock device the way the boot test does (so Plasma Setup's
# wizard is skipped), restarts, and checks that the second boot reaches the sign-in screen with
# no failed units, in the mode anti-cheat needs (kernel lockdown, the IOMMU on, kexec disabled,
# the BPF LSM, no hibernation) and with only allowed module signers loaded, Universal Blue's key
# trusted. The full boot test and the update test run before a change merges; this one takes
# about ten minutes. Prints PASS/FAIL per check.
#
# Usage: tests/smoke-test.sh [--image REF] [--archive FILE] [--timeout SECONDS] [--memory MIB]
#                            [--cpus N] [--results DIR] [--keep] [--help]
#   --image REF         image to test (default localhost/orielos:latest)
#   --archive FILE      load this OCI archive into Podman first and test it as
#                       localhost/orielos-archive:<file name>, unless --image is given
#   --timeout SECONDS   time to wait for SSH and for the sign-in screen after each power-on
#                       (default 600)
#   --memory MIB        VM memory (default 4096)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, signin.png and summary.txt go
#                       (default tests/results/<run id>)
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is smoke-<image tag>-<UTC
# time>. Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
IMAGE=""
ARCHIVE=""
TIMEOUT=600
MEMORY=4096
CPUS=4
RESULTS=""
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
SUMMARY=""
BOOT_ID=""
# Where the second boot starts in the serial log, in lines.
LOG_FROM=0
# The kernel arguments anti-cheat needs; keep in step with tests/boot-test.sh.
ANTICHEAT_KARGS=(lockdown=integrity intel_iommu=on iommu.passthrough=0)

usage() {
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Print the second boot's part of the serial log.
second_boot_log() {
    full_log | tail -n +"$((LOG_FROM + 1))"
}

# Restart the VM from inside and wait for it to come back as a new boot. Returns 1 if it doesn't.
restart_vm() {
    local before="$BOOT_ID" start now=""
    LOG_FROM="$(full_log | wc -l)"
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    start=$SECONDS
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

# Wait up to $TIMEOUT s for the second boot to start SDDM and reach graphical.target. Returns 1 if
# it doesn't.
wait_for_signin() {
    local text
    while ((SECONDS - BOOT_START < TIMEOUT)); do
        text="$(second_boot_log)"
        [[ "$text" == *"Started sddm.service"* && "$text" == *"Reached target graphical.target"* ]] && return 0
        vm_running || return 1
        sleep 2
    done
    return 1
}

# Print the boot's state over SSH, one key=value per line: the kernel command line, lockdown,
# kexec, the active LSMs, whether hibernation is offered, the failed units, whether Universal
# Blue's key is trusted, and each loaded module with its signer.
probe() {
    cat <<EOF
echo "cmdline=\$(cat /proc/cmdline)"
echo "lockdown=\$(cat /sys/kernel/security/lockdown 2>&1)"
echo "kexec=\$(cat /proc/sys/kernel/kexec_load_disabled 2>&1)"
echo "lsm=\$(cat /sys/kernel/security/lsm 2>&1)"
echo "hibernate=\$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>&1)"
echo "failed=\$(systemctl --failed --no-legend --plain | awk '{print \$1}' | paste -sd ' ' -)"
echo "key=\$(mokutil --test-key $UBLUE_KEY 2>&1 | head -n1)"
while read -r m _; do
    printf 'module=%s|%s\n' "\$m" "\$(modinfo -F signer "\$m" 2>/dev/null)"
done </proc/modules
EOF
}

# Print the loaded modules whose signer isn't in image/module-signers.txt: bad_modules <probe output>
bad_modules() {
    local allowed name signer ok s
    mapfile -t allowed < <(grep -v -e '^#' -e '^[[:space:]]*$' "$ROOT/image/module-signers.txt")
    while IFS='|' read -r name signer; do
        ok=0
        for s in "${allowed[@]}"; do
            if [[ "$signer" == "$s" ]]; then ok=1; fi
        done
        if [[ "$ok" -ne 1 ]]; then printf '%s (%s)\n' "$name" "${signer:-unsigned}"; fi
    done < <(sed -n 's/^module=//p' <<<"$1")
}

value() {
    sed -n "s/^$1=//p" <<<"$2" | head -n1
}

check_boot() {
    local out cmdline missing="" arg bad failed key
    out="$(vm_ssh "$(probe)" 2>/dev/null)" || true
    printf '%s\n' "$out" >"$RESULTS/probe.txt"
    cmdline="$(value cmdline "$out")"
    for arg in "${ANTICHEAT_KARGS[@]}"; do
        if [[ " $cmdline " != *" $arg "* ]]; then missing="$missing $arg"; fi
    done
    if [[ -z "$missing" && "$(value lockdown "$out")" == *"[integrity]"* && "$(value kexec "$out")" == 1 &&
    ",$(value lsm "$out")," == *,bpf,* && "$(value hibernate "$out")" != *yes* ]]; then
        pass "The boot is anti-cheat ready (lockdown integrity, IOMMU on, kexec disabled, BPF LSM, no hibernation)"
    else
        fail "The boot isn't anti-cheat ready (missing arguments:${missing:- none}; lockdown $(value lockdown "$out"); kexec $(value kexec "$out"); LSMs $(value lsm "$out"); hibernation $(value hibernate "$out"))"
    fi
    bad="$(bad_modules "$out" | paste -sd ',' - | sed 's/,/, /g')"
    if [[ -z "$(sed -n 's/^module=//p' <<<"$out")" ]]; then
        fail "No loaded modules could be read over SSH"
    elif [[ -n "$bad" ]]; then
        fail "Modules with signers that aren't allowed are loaded: $bad"
        hint "the allowed signers are in image/module-signers.txt"
    else
        pass "Every loaded module is signed by an allowed signer ($(grep -c '^module=' <<<"$out") modules)"
    fi
    key="$(value key "$out")"
    if [[ "$key" == *"already enrolled"* ]]; then
        pass "Universal Blue's key is trusted (mokutil --test-key: $key)"
    else
        fail "Universal Blue's key is not trusted (mokutil --test-key: ${key:-no output})"
    fi
    failed="$(value failed "$out")"
    if [[ -z "$failed" ]]; then
        pass "No systemd unit failed"
    else
        fail "These units failed: $failed"
    fi
}

main() {
    local original=("$@") tag run_id
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image | --archive | --timeout | --memory | --cpus | --results)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --image) IMAGE="$2" ;;
                    --archive) ARCHIVE="$2" ;;
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
    [[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -gt 0 ]] || die "--timeout needs a number of seconds"
    [[ "$MEMORY" =~ ^[0-9]+$ ]] || die "--memory needs a number of MiB"
    [[ "$CPUS" =~ ^[0-9]+$ ]] || die "--cpus needs a number"
    if [[ -z "$IMAGE" ]]; then
        if [[ -n "$ARCHIVE" ]]; then
            IMAGE="localhost/orielos-archive:$(basename "$ARCHIVE" .ociarchive)"
        else
            IMAGE="localhost/orielos:latest"
            ARCHIVE=""
        fi
    else
        ARCHIVE=""
    fi

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host
    SSH_WAIT="$TIMEOUT"
    tag="${IMAGE##*:}"
    run_id="$(printf 'smoke-%s-%s' "$tag" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id; results in $RESULTS"
    if [[ -n "$ARCHIVE" ]]; then load_archive; fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist"
    setup_ssh
    install_image
    start_vm

    if ! wait_for_ssh; then
        fail "The first boot answers over SSH"
    else
        pass "The first boot answers over SSH, $((SECONDS - BOOT_START)) s after power-on"
        BOOT_ID="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
        finish_setup
        if [[ "$FINISH_OK" -ne 1 ]]; then
            fail "Setup could be finished over SSH"
        elif ! restart_vm; then
            fail "The VM restarts after setup"
        elif wait_for_signin; then
            vm_qmp "wait:10" "shot:$RESULTS/signin.png" || true
            pass "The second boot reaches the sign-in screen, $((SECONDS - BOOT_START)) s after the restart (see signin.png)"
            check_boot
        else
            fail "The second boot doesn't reach the sign-in screen within $TIMEOUT s (see serial.log)"
        fi
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
