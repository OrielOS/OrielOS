#!/usr/bin/env bash
# Checks the way back to stock Fedora that docs/leaving-orielos.md describes. Installs the image to
# a disk file and boots it under QEMU/KVM as the smoke test does, finishes setup over SSH, then
# switches to Fedora Kinoite with bootc switch (downloading it from quay.io), restarts, and checks
# that Kinoite is running with OrielOS kept as the previous version; then goes back with bootc
# rollback, restarts, and checks OrielOS is running again. Needs internet access from the VM and
# takes about half an hour. Prints PASS/FAIL per check.
#
# Usage: tests/exit-path-test.sh [--image REF] [--kinoite REF] [--timeout SECONDS] [--memory MIB]
#                                [--cpus N] [--results DIR] [--keep] [--help]
#   --image REF         image to test (default localhost/orielos:latest)
#   --kinoite REF       the stock image to switch to (default quay.io/fedora-ostree-desktops/kinoite:44)
#   --timeout SECONDS   time to wait for SSH after each power-on (default 600)
#   --memory MIB        VM memory (default 4096)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log and summary.txt go (default tests/results/<run id>)
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>. Runs as root; re-executes itself through sudo
# otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
IMAGE="localhost/orielos:latest"
KINOITE="quay.io/fedora-ostree-desktops/kinoite:44"
TIMEOUT=600
MEMORY=4096
CPUS=4
RESULTS=""
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
SUMMARY=""
BOOT_ID=""
ARCHIVE=""

usage() {
    sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Restart the VM from inside and wait for it to come back as a new boot. Returns 1 if it doesn't.
restart_vm() {
    local before="$BOOT_ID" start now=""
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

# The running system's os-release VARIANT_ID and NAME, as "variant|name".
running_os() {
    # The variables expand inside the VM, not here.
    # shellcheck disable=SC2016
    vm_ssh '. /etc/os-release; printf "%s|%s\n" "${VARIANT_ID:-}" "${NAME:-}"' 2>/dev/null || true
}

main() {
    local original=("$@") tag run_id os out attempt
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image | --kinoite | --timeout | --memory | --cpus | --results)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --image) IMAGE="$2" ;;
                    --kinoite) KINOITE="$2" ;;
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
    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host
    SSH_WAIT="$TIMEOUT"
    tag="${IMAGE##*:}"
    run_id="$(printf 'exit-%s-%s' "$tag" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id; results in $RESULTS"
    podman image exists "$IMAGE" || die "image $IMAGE does not exist"
    setup_ssh
    install_image
    start_vm

    if ! wait_for_ssh; then
        fail "The first boot answers over SSH"
    else
        BOOT_ID="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
        finish_setup
        if [[ "$FINISH_OK" -ne 1 ]] || ! restart_vm; then
            fail "OrielOS is set up and restarts"
        else
            pass "OrielOS is set up and restarts"
            info "Switching to $KINOITE (a download of a few GB)"
            # A dropped download is tried again; bootc keeps the layers it already has. The download takes
            # far longer than SSH_TIMEOUT's default allows.
            for attempt in 1 2 3; do
                if out="$(SSH_TIMEOUT=2400 vm_ssh "bootc switch --quiet $KINOITE" 2>&1)"; then
                    break
                fi
                warn "bootc switch attempt $attempt didn't finish: $(tail -c 200 <<<"$out")"
            done
            if ! vm_ssh "bootc status --format=json" 2>/dev/null | grep -q 'kinoite'; then
                fail "bootc switch to Fedora Kinoite: $(tail -n1 <<<"$out")"
            elif ! restart_vm; then
                fail "The VM restarts into Fedora Kinoite"
            else
                os="$(running_os)"
                if [[ "$os" == kinoite\|* ]]; then
                    pass "Fedora Kinoite is running (${os#*|})"
                else
                    fail "Fedora Kinoite isn't running after the switch (os-release: $os)"
                fi
                if vm_ssh "bootc status --format=json" 2>/dev/null | grep -q 'orielos'; then
                    pass "OrielOS is kept as the previous version"
                else
                    fail "OrielOS isn't kept as the previous version"
                fi
                if ! out="$(vm_ssh "bootc rollback" 2>&1)" || ! restart_vm; then
                    fail "bootc rollback goes back to OrielOS: $(tail -n1 <<<"$out")"
                else
                    os="$(running_os)"
                    if [[ "$os" == *OrielOS* ]]; then
                        pass "OrielOS is running again after bootc rollback"
                    else
                        fail "OrielOS isn't running after bootc rollback (os-release: $os)"
                    fi
                fi
            fi
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
