#!/usr/bin/env bash
# Tests enrolling Universal Blue's driver-signing key the way a user does. Installs the image to a
# disk file and boots it headless under QEMU/KVM with Secure Boot, Microsoft's keys and no key in
# shim's MokList, and checks over SSH that the first boot queued Universal Blue's key, and only
# that key. It then restarts, waits for shim's blue MOK management screen and confirms the key
# there with QMP key presses and the password orielos, taking a screenshot at each step. After the
# next boot it checks that the key is enrolled and that the drivers it signs load. Prints
# PASS/FAIL per check.
#
# Usage: tests/secure-boot-key-test.sh [--image REF] [--archive FILE] [--timeout SECONDS]
#                                      [--memory MIB] [--cpus N] [--results DIR] [--keep] [--help]
#   --image REF         image to test (default localhost/orielos:latest)
#   --archive FILE      load this OCI archive (from tools/build-image.sh) into Podman first and
#                       test it as localhost/orielos-archive:<file name>, unless --image is given
#   --timeout SECONDS   time to wait for SSH after power-on and after each restart (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, the screenshots and summary.txt go
#                       (default tests/results/<run id>)
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is
# secure-boot-<image tag>-<UTC time>. Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
IMAGE="localhost/orielos:latest"
IMAGE_SET=0
ARCHIVE=""
TIMEOUT=600
MEMORY=6144
CPUS=4
RESULTS=""
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
SUMMARY=""
BOOT_ID=""
# shim's MOK manager, step by step. Each step is "<keys>|<what the step does>"; the keys are QMP
# qcodes, sent one after the other, and a screenshot follows each step. The menus are text lists
# moved through with the arrow keys.
MOK_STEPS=(
    "spc|press a key to start MOK management"
    "down ret|choose Enroll MOK"
    "down ret|choose Continue"
    "down ret|choose Yes"
    "o r i e l o s ret|type the password orielos"
    "ret|choose Reboot"
)

usage() {
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Read the running boot's id into BOOT_ID. Returns 1 if SSH does not answer.
read_boot_id() {
    BOOT_ID="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || return 1
}

# Restart the VM over SSH and wait up to $TIMEOUT s for SSH to answer from a new boot.
#   restart_vm [skip]   with "skip", only wait for SSH to go away, because the caller drives the
#                       firmware screens and waits for the new boot itself
restart_vm() {
    local old="$BOOT_ID" start
    info "Restarting the VM"
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    BOOT_START=$SECONDS
    start=$SECONDS
    while ((SECONDS - start < 120)); do
        vm_ssh true >/dev/null 2>&1 || break
        sleep 1
    done
    if [[ "${1:-}" == "skip" ]]; then return 0; fi
    wait_for_new_boot "$old"
}

# Wait up to $TIMEOUT s for SSH to answer from a boot other than the given one.
wait_for_new_boot() {
    local old="$1"
    SSH_WAIT=$TIMEOUT
    wait_for_ssh || return 1
    read_boot_id || return 1
    [[ "$BOOT_ID" != "$old" ]]
}

# Over QMP: wait up to <seconds> for shim's blue MOK management screen, then run the MOK_STEPS,
# saving mok-1.png when the screen appears and mok-2.png and so on after each step. Prints
# "found=<seconds>" or "found=no", and "step=<n> blue=<share of blue pixels>" per screenshot.
#   drive_mok_manager <seconds>
drive_mok_manager() {
    python3 -I - "$WORK/qmp.sock" "$WORK" "$RESULTS" "$1" "${MOK_STEPS[@]}" <<'PY'
import json, socket, sys, time

qmp, work, results, limit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
steps = sys.argv[5:]
sock = socket.socket(socket.AF_UNIX)
sock.settimeout(60)
sock.connect(qmp)
f = sock.makefile("rw")


def cmd(name, args=None):
    msg = {"execute": name}
    if args:
        msg["arguments"] = args
    f.write(json.dumps(msg) + "\n")
    f.flush()
    while True:
        reply = json.loads(f.readline())
        if "return" in reply or "error" in reply:
            return reply


def blue_share():
    """Share of pixels in the last screendump that are the firmware console's blue."""
    data = open(work + "/mok.ppm", "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pixels = data[pos + 1:]
    total = blue = 0
    for i in range(0, len(pixels) - 2, 3 * 97):
        r, g, b = pixels[i], pixels[i + 1], pixels[i + 2]
        total += 1
        if b > 100 and r < 80 and g < 80:
            blue += 1
    return blue / max(total, 1)


def shot(n):
    cmd("screendump", {"filename": work + "/mok.ppm", "format": "ppm"})
    cmd("screendump", {"filename": f"{results}/mok-{n}.png", "format": "png"})
    share = blue_share()
    print(f"step={n} blue={share:.2f}", flush=True)
    return share


f.readline()
cmd("qmp_capabilities")
print("ready", flush=True)
# Wait for the guest's restart first, so the desktop still on screen is not mistaken for shim's.
sock.settimeout(limit)
while json.loads(f.readline()).get("event") != "RESET":
    pass
sock.settimeout(60)
start = time.monotonic()
found = False
while time.monotonic() - start < limit:
    cmd("screendump", {"filename": work + "/mok.ppm", "format": "ppm"})
    try:
        if blue_share() > 0.5:
            found = True
            break
    except (OSError, IndexError):
        pass
    time.sleep(0.5)
if not found:
    print("found=no")
    sys.exit()
print(f"found={int(time.monotonic() - start)}", flush=True)
time.sleep(1)
shot(1)
for n, step in enumerate(steps, start=2):
    keys = step.split("|", 1)[0].split()
    for key in keys:
        cmd("send-key", {"keys": [{"type": "qcode", "data": key}]})
        time.sleep(0.3)
    time.sleep(2)
    shot(n)
PY
}

# Remote script that prints what the checks need about the key: the state file, mokutil's view
# of the key, the queued keys, Secure Boot and whether v4l2loopback is loaded.
key_probe() {
    cat <<SH
systemctl is-active orielos-secure-boot-key.service | sed 's/^/unit=/'
sed 's/^/state./' /var/lib/orielos/secure-boot/state
mokutil --test-key $UBLUE_KEY 2>&1 | sed 's/^/test-key=/'
mokutil --sb-state 2>&1 | sed 's/^/sb-state=/'
printf 'new-keys=%s\n' "\$(mokutil --list-new 2>/dev/null | grep -c '^\[key ')"
printf 'new-ublue=%s\n' "\$(mokutil --list-new 2>/dev/null | grep -c 'Subject:.*CN=ublue kernel')"
printf 'enrolled-ublue=%s\n' "\$(mokutil --list-enrolled 2>/dev/null | grep -c 'Subject:.*CN=ublue kernel')"
lsmod | awk '\$1 == "v4l2loopback" {print "v4l2loopback=loaded"}'
SH
}

# Run key_probe in the VM, save its output to the results as <name>.txt and print it.
probe() {
    vm_ssh "$(key_probe)" 2>&1 | tee "$RESULTS/$1.txt" || true
}

field() {
    sed -n "s/^$1=//p" <<<"$2" | head -n1
}

main() {
    local original=("$@") run_id tag out steps found driver
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image | --archive | --timeout | --memory | --cpus | --results)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --image)
                        IMAGE="$2"
                        IMAGE_SET=1
                        ;;
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

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host

    if [[ -n "$ARCHIVE" && "$IMAGE_SET" -eq 0 ]]; then
        tag="${ARCHIVE##*/}"
        IMAGE="localhost/orielos-archive:${tag%.ociarchive}"
    fi
    tag="latest"
    if [[ "${IMAGE##*/}" == *:* ]]; then tag="${IMAGE##*:}"; fi
    run_id="$(printf 'secure-boot-%s-%s' "$tag" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id; results in $RESULTS"
    if [[ -n "$ARCHIVE" ]]; then load_archive; fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"

    # The firmware has Microsoft's keys and an empty MokList, like a new PC.
    MOK_ENROL=0
    setup_ssh
    install_image
    start_vm

    info "Step 1: first boot, with no key in shim's MokList"
    SSH_WAIT=$TIMEOUT
    wait_for_ssh || die "SSH did not answer on the first boot"
    read_boot_id || die "could not read the boot id"
    # The service runs before the login screen; SSH can answer a little earlier.
    for _ in $(seq 30); do
        [[ "$(vm_ssh systemctl is-active orielos-secure-boot-key.service 2>/dev/null)" == "active" ]] && break
        sleep 2
    done

    info "Step 2: the key is queued"
    out="$(probe queued)"
    if [[ "$(field unit "$out")" != "active" ]]; then
        fail "orielos-secure-boot-key.service ran (systemctl is-active: $(field unit "$out"))"
    elif [[ "$(field state.key "$out")" != "pending" ]]; then
        fail "The first boot queues Universal Blue's key (state: key=$(field state.key "$out"))"
    elif [[ "$(field new-keys "$out")" != "1" || "$(field new-ublue "$out")" != "1" ]]; then
        fail "mokutil --list-new shows Universal Blue's key and only it ($(field new-keys "$out") keys queued, $(field new-ublue "$out") of them ublue kernel)"
    else
        pass "The first boot queues Universal Blue's key, and only it (state: key=pending; mokutil --list-new: one key, CN=ublue kernel)"
    fi
    if [[ "$(field state.ca2023 "$out")" == "present" ]]; then
        pass "Microsoft UEFI CA 2023 is found in the firmware's db (state: ca2023=present)"
    else
        fail "Microsoft UEFI CA 2023 is not found in the firmware's db (state: ca2023=$(field state.ca2023 "$out"))"
    fi
    if [[ -z "$(field v4l2loopback "$out")" ]]; then
        pass "Before enrolment the kernel refuses Universal Blue's drivers (v4l2loopback is not loaded)"
    else
        fail "v4l2loopback loaded before Universal Blue's key was enrolled"
    fi

    info "Step 3: restart and confirm the key on shim's MOK management screen"
    # The QMP client starts first and waits for the guest's restart, then for the blue screen.
    drive_mok_manager 180 >"$RESULTS/mok-steps.txt" 2>&1 &
    driver=$!
    for _ in $(seq 20); do
        grep -q '^ready' "$RESULTS/mok-steps.txt" && break
        sleep 0.5
    done
    restart_vm skip
    wait "$driver" || true
    steps="$(cat "$RESULTS/mok-steps.txt")"
    found="$(field found "$steps")"
    if [[ -z "$found" || "$found" == "no" ]]; then
        fail "shim's MOK management screen appeared after the restart (no blue screen within 180 s)"
    else
        info "shim's MOK management screen appeared $found s after the VM went down"
        info "Screenshots: $RESULTS/mok-1.png to mok-$((${#MOK_STEPS[@]} + 1)).png"
    fi

    info "Step 4: after the MOK manager restarts, the key is enrolled"
    if wait_for_new_boot "$BOOT_ID"; then
        out="$(probe enrolled)"
        if [[ "$(field enrolled-ublue "$out")" -ge 1 && "$(field test-key "$out")" == *"is already enrolled"* ]]; then
            pass "Universal Blue's key is enrolled (mokutil --list-enrolled shows CN=ublue kernel)"
        else
            fail "Universal Blue's key is not enrolled ($(field test-key "$out"))"
        fi
        if [[ "$(field sb-state "$out")" == "SecureBoot enabled" ]]; then
            pass "Secure Boot is still on (mokutil --sb-state: SecureBoot enabled)"
        else
            fail "Secure Boot is not on (mokutil --sb-state: $(field sb-state "$out"))"
        fi
        if [[ "$(field state.key "$out")" == "enrolled" ]]; then
            pass "orielos-secure-boot-key.service records the key as enrolled (state: key=enrolled)"
        else
            fail "orielos-secure-boot-key.service does not record the key as enrolled (state: key=$(field state.key "$out"))"
        fi
        if [[ "$(field v4l2loopback "$out")" == "loaded" ]]; then
            pass "Universal Blue's drivers load (v4l2loopback is loaded)"
        else
            fail "v4l2loopback is not loaded after enrolment"
        fi
    else
        fail "The VM did not boot again after the MOK manager (no SSH within $TIMEOUT s)"
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
