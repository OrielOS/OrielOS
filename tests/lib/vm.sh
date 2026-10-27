#!/usr/bin/env bash
# Shared code for the VM tests: result lines, installing the image to a disk file, booting it
# under QEMU/KVM with Secure Boot firmware and a software TPM, SSH into the VM through a vsock
# device, pressing keys, clicking and taking screenshots over QMP, finishing Plasma Setup and
# cleaning up. The VM's firmware has Universal Blue's driver-signing key in shim's MokList unless
# MOK_ENROL is 0. Sourced by tests/boot-test.sh, tests/update-test.sh,
# tests/secure-boot-key-test.sh and tests/screenshot-tour.sh.
#
# The caller sets VM_ROOT, IMAGE, MEMORY, CPUS, KEEP, WORK, RESULTS and SUMMARY (and ARCHIVE for
# load_archive) before using these functions, and installs cleanup as its EXIT trap. check_host
# takes the lock in tools/lib/lock.sh, so one build or VM test runs at a time, and removes what
# runs that were killed left behind.

# Shared state; the tests read these too.
# shellcheck disable=SC2034
{
    BASE_ARGS=()
    OVMF_CODE=""
    OVMF_VARS=""
    BOOT_START=0
    SSH_PROXY=""
    GUEST_CID=""
    SSH_WAIT=60
    SSH_OK=0
    FINISH_OK=0
    TEST_USER="orielostest"
    # 1: the VM's firmware already has Universal Blue's key in shim's MokList, like a machine
    # whose owner confirmed it on shim's blue screen. 0: the key is not enrolled.
    MOK_ENROL=1
    UBLUE_KEY="/etc/pki/akmods/certs/akmods-ublue.der"
    # Owner GUID for the MokList entry: shim's own.
    MOK_OWNER="605dab50-e046-4300-abb6-3dd810dd8b23"
    # Extra kernel arguments for the installation. The image boots with "quiet" for its splash
    # screen. The checks read systemd's status lines and kernel messages from the serial console,
    # so turn both back on there, and turn Plymouth off: while the splash runs it takes over the
    # console output, so systemd's status lines never reach the serial console.
    INSTALL_KARGS=(console=tty0 "console=ttyS0,115200" systemd.show_status=1 ignore_loglevel plymouth.enable=0)
    # The VM's screen size as <width>x<height>, or empty for the graphics card's default. With a
    # size, the VM also gets a USB tablet, so vm_qmp can click at a point on the screen.
    VM_SCREEN=""
    # Images load_archive added to Podman, which cleanup removes again.
    LOADED_IMAGES=()
    PASSED=0
    FAILED=0
}

# shellcheck source=/dev/null
source "$ROOT/tools/lib/lock.sh"

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

# Print an indented hint under the previous line, and add it to summary.txt.
hint() {
    printf '      hint: %s\n' "$1"
    if [[ -n "$SUMMARY" ]]; then printf '      hint: %s\n' "$1" >>"$SUMMARY"; fi
    return 0
}

# Fail unless the host has what the VM tests need.
check_host() {
    local cmd
    for cmd in podman qemu-system-x86_64 swtpm python3 ssh ssh-keygen flock; do
        command -v "$cmd" >/dev/null 2>&1 || die "$cmd is not installed (tools/check-env.sh shows what is missing)"
    done
    [[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm is not usable (tools/check-env.sh shows how to fix it)"
    find_firmware
    take_orielos_lock || exit 1
    remove_leftovers
}

# Remove the work folders of earlier runs that were killed before their cleanup ran. Disks kept
# with --keep are marked and left for tools/clean.sh, and so is a folder whose VM still runs (a
# VM started by hand holds no lock).
remove_leftovers() {
    local dir size pid
    [[ -d "${VM_ROOT:?}" && "$VM_ROOT" == /* ]] || return 0
    for dir in "$VM_ROOT"/*/; do
        dir="${dir%/}"
        [[ -d "$dir" && ! -L "$dir" ]] || continue
        size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
        pid=""
        if [[ -r "$dir/qemu.pid" ]]; then pid="$(cat "$dir/qemu.pid" 2>/dev/null || true)"; fi
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            info "VM folder in use by a running VM, left in place: $dir ($size)"
        elif [[ -e "$dir/kept" ]]; then
            info "Kept VM disk from an earlier run: $dir ($size); tools/clean.sh removes it"
        else
            rm -rf "${dir:?}"
            info "Removed a VM folder left by an earlier run: ${dir##*/} ($size)"
        fi
    done
}

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
            touch "$WORK/kept"
            printf 'Kept the disk: %s\n' "$WORK/disk.raw"
            print_boot_command
        else
            rm -f "$WORK/disk.raw"
            rm -rf "$WORK"
        fi
    fi
    # A kept disk boots without the image it was installed from.
    if [[ "${#LOADED_IMAGES[@]}" -gt 0 ]]; then
        podman rmi "${LOADED_IMAGES[@]}" >/dev/null 2>&1 || true
        podman image prune -f >/dev/null 2>&1 || true
    fi
    exit "$rc"
}

# Print how to start the TPM and boot the kept disk again with a window.
print_boot_command() {
    local proxy=()
    if [[ "${#BASE_ARGS[@]}" -eq 0 ]]; then return 0; fi
    printf 'To boot it again, start the TPM:\n  swtpm socket --tpm2 --tpmstate dir=%q --ctrl type=unixio,path=%q --daemon\n' \
        "$WORK/tpm" "$WORK/swtpm.sock"
    printf 'then run:\n '
    printf ' %q' qemu-system-x86_64 "${BASE_ARGS[@]}" -display gtk
    printf '\nand log in over SSH with:\n '
    mapfile -t proxy < <(proxy_options)
    printf ' %q' ssh -i "$WORK/ssh_key" -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${proxy[@]}" "root@vsock/$GUEST_CID"
    printf '\n'
}

# Print the whole serial log, every boot, without colour codes or unprintable bytes.
full_log() {
    if [[ -r "$WORK/serial.log" ]]; then
        sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$WORK/serial.log" | tr -cd '\11\12\40-\176'
    fi
}

load_archive() {
    local id
    [[ -r "$ARCHIVE" ]] || die "cannot read $ARCHIVE"
    if ! podman image exists "$IMAGE"; then LOADED_IMAGES+=("$IMAGE"); fi
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

# Find systemd-ssh-proxy, or socat where systemd is older than 256 (as on GitHub's Ubuntu 24.04
# runners), make sure the host has vsock, create a key for this run and pick a random guest CID.
# The key is handed to the VM as a systemd credential through SMBIOS.
setup_ssh() {
    local dir n
    for dir in /usr/lib/systemd /usr/libexec; do
        if [[ -x "$dir/systemd-ssh-proxy" ]]; then
            SSH_PROXY="$dir/systemd-ssh-proxy"
            break
        fi
    done
    if [[ -z "$SSH_PROXY" ]] && command -v socat >/dev/null 2>&1; then SSH_PROXY=socat; fi
    [[ -n "$SSH_PROXY" ]] ||
        die "neither systemd-ssh-proxy (systemd 256 or newer) nor socat is installed (tools/check-env.sh shows what is missing)"
    if [[ ! -e /dev/vhost-vsock ]]; then
        modprobe vhost_vsock 2>/dev/null || true
        [[ -e /dev/vhost-vsock ]] ||
            die "/dev/vhost-vsock is missing and vhost_vsock could not be loaded (tools/check-env.sh shows how to fix it)"
    fi
    ssh-keygen -q -t ed25519 -N '' -C "orielos-vm-test" -f "$WORK/ssh_key"
    n="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    GUEST_CID=$((3 + n % 4294967292))
}

# Print the ssh options for the VM, one per line, for ssh_to_vm.
ssh_options() {
    printf '%s\n' -i "$WORK/ssh_key" -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5
    proxy_options
}

# Print the ssh options that reach the VM's vsock port 22, one per line.
proxy_options() {
    if [[ "$SSH_PROXY" == socat ]]; then
        printf '%s\n' -o "ProxyCommand=socat - VSOCK-CONNECT:$GUEST_CID:22"
    else
        printf '%s\n' -o ProxyUseFdpass=yes -o "ProxyCommand=$SSH_PROXY vsock/$GUEST_CID 22"
    fi
}

# Run a command inside the VM as root over SSH through vsock: vm_ssh <command...>
# It gives up after SSH_TIMEOUT seconds (default 120).
vm_ssh() {
    local opts=()
    mapfile -t opts < <(ssh_options)
    timeout "${SSH_TIMEOUT:-120}" ssh -n "${opts[@]}" "root@vsock/$GUEST_CID" "$@"
}

# Copy a file into the VM over SSH: vm_copy <local file> <path in the VM>
vm_copy() {
    local opts=()
    mapfile -t opts < <(ssh_options)
    timeout 1800 ssh "${opts[@]}" "root@vsock/$GUEST_CID" "cat >$(printf '%q' "$2")" <"$1"
}

# Wait up to $SSH_WAIT seconds for SSH to answer. Returns 1 if it never does.
wait_for_ssh() {
    local start=$SECONDS
    info "Waiting up to $SSH_WAIT s for SSH over vsock (guest CID $GUEST_CID)"
    while ((SECONDS - start < SSH_WAIT)); do
        if vm_ssh true >/dev/null 2>&1; then
            SSH_OK=1
            info "SSH answered $((SECONDS - BOOT_START)) s after power-on"
            return 0
        fi
        vm_running || break
        sleep 2
    done
    info "SSH did not answer within $SSH_WAIT s"
    return 1
}

# Drive the VM's keyboard and screen over QMP, one step after another: vm_qmp <step...>
#   keys:<qcode>[+<qcode>...]   press keys together, for example keys:meta_l+e or keys:ret
#   type:<text>                 type letters, digits, spaces and . - _ one key at a time
#   shot:<file>                 save a screendump; PNG when the name ends in .png, PPM otherwise
#   click:<x>,<y>               click the left mouse button at that pixel (needs VM_SCREEN)
#   rclick:<x>,<y>              click the right mouse button there
#   wait:<seconds>              pause
vm_qmp() {
    python3 -I - "$WORK/qmp.sock" "${VM_SCREEN:-0x0}" "$@" <<'PY'
import json, socket, sys, time

sock = socket.socket(socket.AF_UNIX)
sock.settimeout(60)
sock.connect(sys.argv[1])
width, height = (int(n) for n in sys.argv[2].split("x"))
f = sock.makefile("rw")
NAMES = {" ": "spc", ".": "dot", "-": "minus", "_": "shift+minus"}


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


def press(combo):
    keys = [{"type": "qcode", "data": k} for k in combo.split("+")]
    cmd("send-key", {"keys": keys, "hold-time": 80})
    time.sleep(0.15)


f.readline()
cmd("qmp_capabilities")
def click(x, y, button="left"):
    move = [{"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / (width - 1))}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / (height - 1))}}]
    cmd("input-send-event", {"events": move})
    time.sleep(0.3)
    for down in (True, False):
        cmd("input-send-event", {"events": [{"type": "btn", "data": {"down": down, "button": button}}]})
        time.sleep(0.1)


for step in sys.argv[3:]:
    kind, _, value = step.partition(":")
    if kind == "click" and width:
        click(*(int(n) for n in value.split(",")))
    elif kind == "rclick" and width:
        click(*(int(n) for n in value.split(",")), button="right")
    elif kind == "keys":
        press(value)
    elif kind == "type":
        for ch in value:
            press(NAMES.get(ch) or ("shift+" + ch.lower() if ch.isupper() else ch))
    elif kind == "shot":
        fmt = "png" if value.endswith(".png") else "ppm"
        cmd("screendump", {"filename": value, "format": fmt})
    elif kind == "wait":
        time.sleep(float(value))
    else:
        sys.exit("unknown step: " + step)
PY
}

# Finish setup the way Plasma Setup does when the user clicks Finish: create the user with a
# password and its own group, add it to the groups in /etc/xdg/plasmasetuprc, copy the theme and
# display scaling chosen in the wizard to it, remove the wizard's autologin and write the done
# marker. The wizard then logs out; the tests restart instead.
finish_setup() {
    local out
    info "Finishing setup as Plasma Setup does: creating $TEST_USER and writing /etc/plasma-setup-done"
    if out="$(vm_ssh "set -e
        groups=\$(sed -n 's/^UserGroups=//p' /etc/xdg/plasmasetuprc 2>/dev/null || true)
        useradd -m -U -c 'OrielOS test' $TEST_USER
        usermod -a -G \"\${groups:-wheel}\" $TEST_USER
        printf '%s:%s\n' $TEST_USER \"\$(head -c 18 /dev/urandom | base64)\" | chpasswd
        install -d -o $TEST_USER -g $TEST_USER /home/$TEST_USER/.config
        for f in kdeglobals kwinoutputconfig.json kwinrc; do
            if [ -r /run/plasma-setup/.config/\$f ]; then
                install -m 0644 -o $TEST_USER -g $TEST_USER /run/plasma-setup/.config/\$f /home/$TEST_USER/.config/\$f
            fi
        done
        rm -f /etc/sddm.conf.d/99-plasma-setup.conf
        printf 'Plasma Setup completed at %sZ\n' \"\$(date -u +%Y-%m-%dT%H:%M:%S)\" >/etc/plasma-setup-done
        chmod 0644 /etc/plasma-setup-done" 2>&1)"; then
        FINISH_OK=1
    else
        info "Could not finish setup: ${out:-no output}"
    fi
}

install_image() {
    local start=$SECONDS karg kargs=()
    info "Installing $IMAGE to a 30 GiB disk (this takes a few minutes)"
    truncate -s 30G "$WORK/disk.raw"
    for karg in "${INSTALL_KARGS[@]}"; do kargs+=(--karg "$karg"); done
    podman run --rm --privileged --pid=host --security-opt label=disable \
        -v /var/lib/containers:/var/lib/containers -v /dev:/dev -v "$WORK:/output" \
        "$IMAGE" bootc install to-disk --via-loopback --generic-image --wipe \
        "${kargs[@]}" /output/disk.raw >"$RESULTS/install.log" 2>&1 ||
        die "the installation failed; see $RESULTS/install.log"
    info "Installed in $((SECONDS - start)) s"
}

# Add Universal Blue's key, read from the image, to shim's MokList in the VM's firmware variables,
# so the VM trusts the image's drivers from the first boot on.
enrol_mok() {
    command -v virt-fw-vars >/dev/null 2>&1 ||
        die "virt-fw-vars is not installed (sudo apt install python3-virt-firmware; Fedora: sudo dnf install python3-virt-firmware)"
    podman run --rm "$IMAGE" cat "$UBLUE_KEY" >"$WORK/ublue.der" ||
        die "could not read Universal Blue's key, $UBLUE_KEY, from $IMAGE"
    virt-fw-vars --inplace "$WORK/vars.fd" --add-mok "$MOK_OWNER" "$WORK/ublue.der" >"$WORK/virt-fw-vars.log" 2>&1 ||
        die "could not add Universal Blue's key to the VM's MokList; see $WORK/virt-fw-vars.log"
    info "Universal Blue's key is in the VM's MokList, as if it had been enrolled"
}

start_vm() {
    local _
    cp "$OVMF_VARS" "$WORK/vars.fd"
    chmod u+w "$WORK/vars.fd"
    if [[ "$MOK_ENROL" -eq 1 ]]; then enrol_mok; fi
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
        -device "virtio-vga${VM_SCREEN:+,xres=${VM_SCREEN%x*},yres=${VM_SCREEN#*x}}"
        -audiodev "none,id=snd0" -device ich9-intel-hda -device "hda-output,audiodev=snd0"
        -netdev "user,id=n0" -device "virtio-net-pci,netdev=n0"
        -device "vhost-vsock-pci,guest-cid=$GUEST_CID"
        -smbios "type=11,value=io.systemd.credential.binary:ssh.authorized_keys.root=$(base64 -w0 "$WORK/ssh_key.pub")"
    )
    if [[ -n "$VM_SCREEN" ]]; then BASE_ARGS+=(-device qemu-xhci -device usb-tablet); fi
    qemu-system-x86_64 "${BASE_ARGS[@]}" -display none \
        -serial "file:$WORK/serial.log" -qmp "unix:$WORK/qmp.sock,server=on,wait=off" \
        -daemonize -pidfile "$WORK/qemu.pid"
    BOOT_START=$SECONDS
}
