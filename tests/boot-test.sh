#!/usr/bin/env bash
# Installs the OrielOS image to a disk file, boots it headless under QEMU/KVM with Secure Boot
# and a software TPM, and checks that it reaches the login screen. Prints PASS/FAIL per check.
#
# Usage: tests/boot-test.sh [--image REF] [--archive FILE] [--timeout SECONDS] [--memory MIB]
#                           [--cpus N] [--results DIR] [--keep] [--help]
#   --image REF         image to test (default localhost/orielos:latest)
#   --archive FILE      load this OCI archive (from tools/build-image.sh) into Podman first and
#                       test it as localhost/orielos-archive:<file name>, unless --image is given
#   --timeout SECONDS   time to wait for the login screen after power-on (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, screenshot.png and summary.txt go
#                       (default tests/results/<run id>)
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is <image tag>-<UTC time>.
# Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
BASE_ARGS=()
OVMF_CODE=""
OVMF_VARS=""
BOOT_START=0
SDDM_SECONDS=""
PASSED=0
FAILED=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_BLUE=$'\033[34m'
    C_YELLOW=$'\033[33m'
    C_OFF=$'\033[0m'
else
    C_GREEN=""
    C_RED=""
    C_BLUE=""
    C_YELLOW=""
    C_OFF=""
fi

die() {
    printf 'error: %s\n' "$1" >&2
    if [[ -n "$SUMMARY" ]]; then printf 'FAIL  %s\n' "$1" >>"$SUMMARY"; fi
    exit 1
}

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Print one result line and add it to summary.txt: say <colour> <label> <text>
say() {
    printf '%s%s%s  %s\n' "$1" "$2" "$C_OFF" "$3"
    if [[ -n "$SUMMARY" ]]; then printf '%s  %s\n' "$2" "$3" >>"$SUMMARY"; fi
    return 0
}

pass() {
    PASSED=$((PASSED + 1))
    say "$C_GREEN" PASS "$1"
}
fail() {
    FAILED=$((FAILED + 1))
    say "$C_RED" FAIL "$1"
}
warn() { say "$C_YELLOW" WARN "$1"; }
info() { say "$C_BLUE" INFO "$1"; }

# Stop a daemon whose pid is in a file.
stop_pid() {
    local file="$1" pid="" _
    if [[ -r "$file" ]]; then pid="$(cat "$file")"; fi
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        kill -9 "$pid" 2>/dev/null || true
    fi
    return 0
}

vm_running() {
    local pid=""
    if [[ -r "$WORK/qemu.pid" ]]; then pid="$(cat "$WORK/qemu.pid")"; fi
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

cleanup() {
    local rc=$?
    trap - EXIT
    if [[ -n "$WORK" ]]; then
        stop_pid "$WORK/qemu.pid"
        stop_pid "$WORK/swtpm.pid"
        if [[ "$KEEP" -eq 1 ]]; then
            printf 'Kept the disk: %s\n' "$WORK/disk.raw"
            print_boot_command
        else
            rm -f "$WORK/disk.raw"
            rm -rf "$WORK"
        fi
    fi
    exit "$rc"
}

# Print how to start the TPM and boot the kept disk again with a window.
print_boot_command() {
    if [[ "${#BASE_ARGS[@]}" -eq 0 ]]; then return 0; fi
    printf 'To boot it again, start the TPM:\n  swtpm socket --tpm2 --tpmstate dir=%q --ctrl type=unixio,path=%q --daemon\n' \
        "$WORK/tpm" "$WORK/swtpm.sock"
    printf 'then run:\n '
    printf ' %q' qemu-system-x86_64 "${BASE_ARGS[@]}" -display gtk
    printf '\n'
}

# Print the serial log without colour codes or unprintable bytes.
clean_log() {
    if [[ -r "$WORK/serial.log" ]]; then
        sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$WORK/serial.log" | tr -cd '\11\12\40-\176'
    fi
}

grep_log() {
    clean_log | grep -E "$@" || true
}

load_archive() {
    local id
    [[ -r "$ARCHIVE" ]] || die "cannot read $ARCHIVE"
    info "Loading $ARCHIVE as $IMAGE"
    # skopeo creates only the requested tag; podman pull also tags the archive's own name.
    if command -v skopeo >/dev/null 2>&1; then
        skopeo copy --quiet "oci-archive:$ARCHIVE" "containers-storage:$IMAGE" ||
            die "could not load $ARCHIVE"
    else
        id="$(podman pull --quiet "oci-archive:$ARCHIVE")" || die "could not load $ARCHIVE"
        podman tag "$id" "$IMAGE"
    fi
}

find_firmware() {
    local pairs=(
        "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd:/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
        "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd:/usr/share/edk2/ovmf/OVMF_VARS.secboot.fd"
    )
    local pair code vars
    for pair in "${pairs[@]}"; do
        code="${pair%%:*}"
        vars="${pair##*:}"
        if [[ -r "$code" && -r "$vars" ]]; then
            OVMF_CODE="$code"
            OVMF_VARS="$vars"
            return 0
        fi
    done
    die "no Secure Boot capable OVMF firmware found (sudo apt install ovmf; Fedora: sudo dnf install edk2-ovmf)"
}

install_image() {
    local start=$SECONDS
    info "Installing $IMAGE to a 30 GiB disk (this takes a few minutes)"
    truncate -s 30G "$WORK/disk.raw"
    podman run --rm --privileged --pid=host --security-opt label=disable \
        -v /var/lib/containers:/var/lib/containers -v /dev:/dev -v "$WORK:/output" \
        "$IMAGE" bootc install to-disk --via-loopback --generic-image --wipe \
        --karg console=tty0 --karg console=ttyS0,115200 \
        /output/disk.raw >"$RESULTS/install.log" 2>&1 ||
        die "the installation failed; see $RESULTS/install.log"
    info "Installed in $((SECONDS - start)) s"
}

start_vm() {
    local _
    cp "$OVMF_VARS" "$WORK/vars.fd"
    mkdir -p "$WORK/tpm"
    swtpm socket --tpm2 --tpmstate "dir=$WORK/tpm" --ctrl "type=unixio,path=$WORK/swtpm.sock" \
        --pid "file=$WORK/swtpm.pid" --daemon
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -S "$WORK/swtpm.sock" ]] && break
        sleep 0.5
    done
    [[ -S "$WORK/swtpm.sock" ]] || die "swtpm did not start"
    BASE_ARGS=(
        -accel kvm -machine "q35,smm=on" -cpu host -m "$MEMORY" -smp "$CPUS"
        -global "driver=cfi.pflash01,property=secure,value=on"
        -drive "if=pflash,format=raw,unit=0,file=$OVMF_CODE,readonly=on"
        -drive "if=pflash,format=raw,unit=1,file=$WORK/vars.fd"
        -chardev "socket,id=chrtpm,path=$WORK/swtpm.sock"
        -tpmdev "emulator,id=tpm0,chardev=chrtpm" -device "tpm-crb,tpmdev=tpm0"
        -drive "file=$WORK/disk.raw,format=raw,if=virtio"
        -device virtio-vga
        -netdev "user,id=n0" -device "virtio-net-pci,netdev=n0"
    )
    qemu-system-x86_64 "${BASE_ARGS[@]}" -display none \
        -serial "file:$WORK/serial.log" -qmp "unix:$WORK/qmp.sock,server=on,wait=off" \
        -daemonize -pidfile "$WORK/qemu.pid"
    BOOT_START=$SECONDS
}

# Wait for the login screen and record when SDDM started. Returns 1 on timeout.
wait_for_login() {
    local text
    info "Booting; waiting up to $TIMEOUT s for the login screen"
    while ((SECONDS - BOOT_START < TIMEOUT)); do
        text="$(clean_log)"
        if [[ -z "$SDDM_SECONDS" && "$text" == *"Started sddm.service"* ]]; then
            SDDM_SECONDS=$((SECONDS - BOOT_START))
        fi
        if [[ "$text" == *"Started sddm.service"* && "$text" == *"Reached target graphical.target"* ]]; then
            info "Waiting 15 s for the greeter to draw"
            sleep 15
            return 0
        fi
        if ! vm_running; then
            info "The VM stopped before the login screen appeared"
            return 1
        fi
        sleep 2
    done
    info "Timed out after $TIMEOUT s"
    return 1
}

# Over QMP: check the VM is running, press a key so the login form shows, take a PPM and a PNG
# screendump, then quit QEMU. Prints "status=<run state>".
take_screenshots() {
    python3 -I - "$WORK/qmp.sock" "$WORK/screen.ppm" "$RESULTS/screenshot.png" <<'PY'
import json, socket, sys, time

sock = socket.socket(socket.AF_UNIX)
sock.settimeout(60)
sock.connect(sys.argv[1])
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


f.readline()
cmd("qmp_capabilities")
print("status=" + str(cmd("query-status").get("return", {}).get("status")))
cmd("send-key", {"keys": [{"type": "qcode", "data": "shift"}]})
time.sleep(3)
cmd("screendump", {"filename": sys.argv[2], "format": "ppm"})
cmd("screendump", {"filename": sys.argv[3], "format": "png"})
f.write(json.dumps({"execute": "quit"}) + "\n")
f.flush()
PY
}

# Print the number of distinct pixel values in a binary P6 PPM file.
count_colours() {
    python3 -I - "$1" <<'PY'
import sys

data = open(sys.argv[1], "rb").read()
pos = 0
tokens = []
while len(tokens) < 4:
    while data[pos:pos + 1].isspace():
        pos += 1
    if data[pos:pos + 1] == b"#":
        while data[pos:pos + 1] != b"\n":
            pos += 1
        continue
    start = pos
    while not data[pos:pos + 1].isspace():
        pos += 1
    tokens.append(data[start:pos])
pos += 1
if tokens[0] != b"P6":
    sys.exit("not a P6 PPM file")
pixels = data[pos:]
print(len({pixels[i:i + 3] for i in range(0, len(pixels) - 2, 3)}))
PY
}

run_checks() {
    local status="$1" colours="$2" cmdline btrfs after failed unit shown="not reached"

    if [[ -n "$(grep_log 'secureboot: Secure boot enabled')" ]]; then
        pass "Secure Boot was on"
    else
        fail "Secure Boot was not on (no 'secureboot: Secure boot enabled' line)"
    fi

    cmdline="$(grep_log 'Kernel command line:' | head -n1)"
    if [[ "$cmdline" =~ (^|[[:space:]])rootflags=compress=zstd:1([[:space:]]|$) ]]; then
        pass "The kernel command line has rootflags=compress=zstd:1"
    else
        fail "The kernel command line lacks rootflags=compress=zstd:1 (${cmdline:-no command line found})"
    fi

    btrfs="$(grep_log 'BTRFS.*(device [^)]*).*zstd' | head -n1)"
    if [[ -n "$btrfs" ]]; then
        pass "The root filesystem is Btrfs with zstd compression ($btrfs)"
    else
        fail "No Btrfs zstd compression line in the kernel log"
    fi

    if [[ -n "$(grep_log 'Reached target graphical\.target')" ]]; then
        pass "graphical.target was reached"
    else
        fail "graphical.target was not reached"
    fi

    after="$(clean_log | sed -n '/Started sddm\.service/,$p' |
        grep -E 'Stopp(ed|ing) sddm\.service|Failed to start sddm\.service|sddm\.service: (Failed|Main process exited)' || true)"
    if [[ -z "$(grep_log 'Started sddm\.service')" ]]; then
        fail "SDDM did not start"
    elif [[ -n "$after" ]]; then
        fail "SDDM stopped or failed after starting ($(head -n1 <<<"$after"))"
    elif [[ "$status" != "running" ]]; then
        fail "SDDM started but the VM was not running (state: ${status:-unknown})"
    elif [[ ! "$colours" =~ ^[0-9]+$ || "$colours" -le 1 ]]; then
        fail "SDDM started but the screen is blank (${colours:-no screenshot} distinct colours)"
    else
        pass "SDDM is running ($colours distinct colours on screen)"
    fi

    if [[ -z "$(grep_log 'Started NetworkManager\.service')" ]]; then
        fail "NetworkManager did not start"
    elif [[ -n "$(grep_log 'Failed to start NetworkManager\.service|NetworkManager\.service: Failed')" ]]; then
        fail "NetworkManager failed"
    else
        pass "NetworkManager is running"
    fi

    failed="$(grep_log 'FAILED' | sed -n 's/.*Failed to start \([^ ]*\).*/\1/p' | sort -u)"
    while IFS= read -r unit; do
        [[ -n "$unit" && "$unit" != sddm.service && "$unit" != NetworkManager.service ]] || continue
        warn "$unit failed to start"
    done <<<"$failed"
    if [[ -n "$SDDM_SECONDS" ]]; then shown="about $SDDM_SECONDS s"; fi
    info "Time from power-on to SDDM: $shown"
}

main() {
    local original=("$@") run_id tag cmd status="" colours="" timed_out=0
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
    for cmd in podman qemu-system-x86_64 swtpm python3; do
        command -v "$cmd" >/dev/null 2>&1 || die "$cmd is not installed (tools/check-env.sh shows what is missing)"
    done
    [[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm is not usable (tools/check-env.sh shows how to fix it)"
    find_firmware

    # An archive gets its own tag unless --image was given, so builds keep their tags.
    if [[ -n "$ARCHIVE" && "$IMAGE_SET" -eq 0 ]]; then
        tag="${ARCHIVE##*/}"
        IMAGE="localhost/orielos-archive:${tag%.ociarchive}"
    fi
    tag="latest"
    if [[ "${IMAGE##*/}" == *:* ]]; then tag="${IMAGE##*:}"; fi
    run_id="$(printf '%s-%s' "$tag" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id; results in $RESULTS"
    if [[ -n "$ARCHIVE" ]]; then load_archive; fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"

    install_image
    start_vm
    wait_for_login || timed_out=1
    if vm_running; then
        status="$(take_screenshots | sed -n 's/^status=//p')" || true
        if [[ -r "$WORK/screen.ppm" ]]; then colours="$(count_colours "$WORK/screen.ppm")" || true; fi
        stop_pid "$WORK/qemu.pid"
    fi
    clean_log >"$RESULTS/serial.log"

    run_checks "$status" "$colours"
    if [[ "$FAILED" -eq 0 && "$timed_out" -eq 0 ]]; then
        say "$C_GREEN" PASS "All $PASSED checks passed"
        return 0
    fi
    say "$C_RED" FAIL "$FAILED of $((PASSED + FAILED)) checks failed"
    return 1
}

main "$@"
