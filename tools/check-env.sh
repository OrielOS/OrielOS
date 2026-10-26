#!/usr/bin/env bash
# Checks that this machine can build the OrielOS image (rootful Podman) and
# boot-test it in QEMU/KVM. Prints PASS/FAIL per requirement with a fix hint.
#
# Usage: tools/check-env.sh [--quick] [--help]
#   --quick   skip the container checks (the first run downloads about 2 GB)
# Environment:
#   ORIELOS_BASE_IMAGE    test image (default quay.io/fedora/fedora-bootc:44)
#   ORIELOS_MIN_FREE_GB   free space needed for Podman storage (default 60)
set -Eeuo pipefail

IMAGE="${ORIELOS_BASE_IMAGE:-quay.io/fedora/fedora-bootc:44}"
MIN_FREE_GB="${ORIELOS_MIN_FREE_GB:-60}"
QUICK=0
PASSED=0
FAILED=0
IS_WSL=0
KVM_OK=0
TMP=""

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

cleanup() {
    if [[ -n "$TMP" ]]; then rm -rf "$TMP"; fi
    return 0
}
trap cleanup EXIT

pass() {
    PASSED=$((PASSED + 1))
    printf '%sPASS%s  %s\n' "$C_GREEN" "$C_OFF" "$1"
}
fail() {
    FAILED=$((FAILED + 1))
    printf '%sFAIL%s  %s\n' "$C_RED" "$C_OFF" "$1"
    if [[ -n "${2:-}" ]]; then printf '      hint: %s\n' "$2"; fi
    return 0
}
info() { printf '%sINFO%s  %s\n' "$C_BLUE" "$C_OFF" "$1"; }
skip() { printf '%sSKIP%s  %s\n' "$C_YELLOW" "$C_OFF" "$1"; }

# Run a command as root, through sudo when needed.
as_root() {
    if [[ "$EUID" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

last_line() {
    awk 'NF {l = $0} END {print l}'
}

cpu_flag() {
    grep -m1 -owE 'vmx|svm' /proc/cpuinfo 2>/dev/null || true
}

make_tmp() {
    if [[ -z "$TMP" ]]; then TMP="$(mktemp -d)"; fi
}

check_platform() {
    local pretty="unknown" cpus mem_kb mem="unknown"
    if [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ "$(uname -r)" == *[Mm]icrosoft* ]]; then
        IS_WSL=1
    fi
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        pretty="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
    fi
    cpus="$(nproc 2>/dev/null || echo '?')"
    mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    if [[ -n "$mem_kb" ]]; then
        mem="$(awk -v k="$mem_kb" 'BEGIN {printf "%.1f GiB", k / 1048576}')"
    fi
    info "Kernel: $(uname -r)"
    if [[ "$IS_WSL" -eq 1 ]]; then info "WSL2: yes"; else info "WSL2: no"; fi
    info "Distribution: $pretty"
    info "CPUs: $cpus, memory: $mem"
}

check_cpu_virt() {
    local flag
    flag="$(cpu_flag)"
    if [[ -n "$flag" ]]; then
        pass "CPU virtualisation is available ($flag)"
    else
        fail "CPU virtualisation (vmx/svm) not found" \
            "enable virtualisation (VT-x/AMD-V) in the firmware; on WSL2 nested virtualisation must be enabled (the default on Windows 11)"
    fi
}

check_kvm() {
    local mod="kvm_intel"
    if [[ "$(cpu_flag)" == "svm" ]]; then mod="kvm_amd"; fi
    if [[ -e /dev/kvm ]]; then
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
            KVM_OK=1
            pass "KVM device /dev/kvm is usable"
        else
            fail "KVM device /dev/kvm exists but is not accessible to ${USER:-this user}" \
                "sudo usermod -aG kvm \"\$USER\", then log in again"
        fi
    else
        fail "KVM device /dev/kvm is missing" \
            "sudo modprobe $mod; to load it at every boot: echo $mod | sudo tee /etc/modules-load.d/kvm.conf (needs systemd; on WSL2 set [boot] systemd=true in /etc/wsl.conf, then run 'wsl --shutdown' from Windows)"
    fi
}

check_command() {
    local cmd="$1" apt_pkg="$2" dnf_pkg="$3" version_arg="${4:-}" version=""
    if command -v "$cmd" >/dev/null 2>&1; then
        if [[ -n "$version_arg" ]]; then
            version="$("$cmd" "$version_arg" 2>/dev/null | head -n1 || true)"
        fi
        pass "$cmd is installed${version:+ ($version)}"
    else
        fail "$cmd is not installed" "sudo apt install $apt_pkg   (Fedora: sudo dnf install $dnf_pkg)"
    fi
}

check_commands() {
    check_command podman podman podman --version
    check_command qemu-system-x86_64 qemu-system-x86 qemu-system-x86-core --version
    check_command qemu-img qemu-utils qemu-img
    check_command swtpm "swtpm swtpm-tools" "swtpm swtpm-tools" --version
    check_command swtpm_setup "swtpm swtpm-tools" "swtpm swtpm-tools"
    check_command virt-fw-vars python3-virt-firmware python3-virt-firmware
    check_command losetup util-linux util-linux
    check_command ssh openssh-client openssh-clients
    # The boot test's visual check compares screenshots with Pillow (tests/lib/screens.py).
    if python3 -I -c 'import PIL' >/dev/null 2>&1; then
        pass "Pillow is installed (for the visual check)"
    else
        fail "Pillow is not installed" "sudo apt install python3-pil   (Fedora: sudo dnf install python3-pillow)"
    fi
}

check_firmware() {
    local pairs=(
        "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd:/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
        "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd:/usr/share/edk2/ovmf/OVMF_VARS.secboot.fd"
    )
    local pair code vars
    for pair in "${pairs[@]}"; do
        code="${pair%%:*}"
        vars="${pair##*:}"
        if [[ -r "$code" && -r "$vars" ]]; then
            pass "UEFI Secure Boot firmware found ($code + $vars)"
            return 0
        fi
    done
    fail "No Secure Boot capable OVMF firmware with Microsoft keys found" \
        "sudo apt install ovmf   (Fedora: sudo dnf install edk2-ovmf)"
}

check_qemu_kvm() {
    local out last rc=0
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1 || [[ "$KVM_OK" -ne 1 ]]; then
        fail "QEMU KVM acceleration check skipped because of the earlier failure" \
            "fix the qemu-system-x86_64 and /dev/kvm checks above first"
        return 0
    fi
    make_tmp
    out="$(printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"query-kvm"}' '{"execute":"quit"}' |
        timeout 30 qemu-system-x86_64 -accel kvm -machine q35 -nodefaults -display none -S -qmp stdio \
            2>"$TMP/qemu.err")" || rc=$?
    if [[ "$out" =~ \"enabled\":[[:space:]]*true ]]; then
        pass "QEMU can use KVM acceleration"
    else
        last="$(last_line <"$TMP/qemu.err")"
        fail "QEMU cannot use KVM acceleration (exit status $rc${last:+: $last})" \
            "check that /dev/kvm is usable by this user and that nested virtualisation is enabled"
    fi
}

# The boot test logs in to its VM over SSH through a vsock device.
check_vsock() {
    local dir proxy=""
    if [[ -e /dev/vhost-vsock ]]; then
        pass "vsock for test VMs is available (/dev/vhost-vsock)"
    elif modprobe -n vhost_vsock >/dev/null 2>&1; then
        pass "vsock for test VMs is available (vhost_vsock can be loaded; the boot test loads it)"
    else
        fail "vsock for test VMs is not available (/dev/vhost-vsock is missing and vhost_vsock cannot be loaded)" \
            "sudo modprobe vhost_vsock; to load it at every boot: echo vhost_vsock | sudo tee /etc/modules-load.d/vhost-vsock.conf"
    fi
    for dir in /usr/lib/systemd /usr/libexec; do
        if [[ -x "$dir/systemd-ssh-proxy" ]]; then
            proxy="$dir/systemd-ssh-proxy"
            break
        fi
    done
    if [[ -n "$proxy" ]]; then
        pass "systemd-ssh-proxy is installed ($proxy)"
    else
        fail "systemd-ssh-proxy is not installed" \
            "it comes with systemd 256 or newer (Ubuntu 24.10 or newer, Fedora 41 or newer)"
    fi
}

check_loop() {
    local dev="" rc=0
    if command -v losetup >/dev/null 2>&1; then
        dev="$(as_root losetup -f 2>/dev/null)" || rc=$?
    else
        rc=1
    fi
    if [[ "$rc" -eq 0 && "$dev" == /dev/* ]]; then
        pass "Loop devices are available (next free: $dev)"
    else
        fail "No free loop device available" \
            "loop devices are needed to install images to disk files; on WSL2 update with 'wsl --update'"
    fi
}

check_podman_rootful() {
    local rootless backend
    if ! command -v podman >/dev/null 2>&1; then
        fail "Rootful Podman cannot be checked because podman is missing" "install podman (see above)"
        return 0
    fi
    rootless="$(as_root podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true)"
    if [[ "$rootless" == "false" ]]; then
        pass "Podman runs rootful"
    else
        fail "Rootful Podman is not working" "run Podman as root (sudo podman info must succeed)"
    fi
    backend="$(as_root podman info --format '{{.Host.NetworkBackend}}' 2>/dev/null || true)"
    if [[ -n "$backend" ]]; then info "Podman network backend: $backend"; fi
    return 0
}

check_container() {
    local out rc=0 http version err hint
    if [[ "$QUICK" -eq 1 ]]; then
        skip "Container run with network (--quick)"
        return 0
    fi
    if ! command -v podman >/dev/null 2>&1; then
        skip "Container run with network (podman is missing)"
        return 0
    fi
    make_tmp
    info "The first run downloads $IMAGE (about 2 GB)"
    out="$(as_root podman run --rm "$IMAGE" cat /etc/os-release 2>"$TMP/run.err")" || rc=$?
    if [[ "$rc" -eq 0 && "$out" == *"ID=fedora"* ]]; then
        version="$(printf '%s\n' "$out" | sed -n 's/^VERSION_ID=//p' | tr -d '"')"
        pass "Container runs ($IMAGE, Fedora ${version:-unknown})"
    else
        fail "Container did not run ($IMAGE): $(last_line <"$TMP/run.err")" \
            "check 'sudo podman run --rm $IMAGE cat /etc/os-release' and your network connection"
        return 0
    fi
    rc=0
    http="$(as_root podman run --rm "$IMAGE" curl -sS -o /dev/null -w '%{http_code}' https://fedoraproject.org/ \
        2>"$TMP/net.err")" || rc=$?
    if [[ "$rc" -eq 0 && "$http" =~ ^[23][0-9][0-9]$ ]]; then
        pass "Container has network access (HTTP $http)"
    else
        err="$(cat "$TMP/net.err")"
        hint="check DNS and proxy settings, then retry"
        if [[ "$err" == *nftables* || "$err" == *nft* ]]; then
            hint="the WSL2 kernel lacks some nftables features that Podman's default firewall driver needs; switch to the iptables driver by creating /etc/containers/containers.conf.d/50-firewall.conf containing a [network] section with firewall_driver = \"iptables\", and install the iptables package"
        fi
        fail "Container has no network access: $(printf '%s\n' "$err" | last_line)" "$hint"
    fi
}

check_disk() {
    local root="" dir free total line img hint
    if command -v podman >/dev/null 2>&1; then
        root="$(as_root podman info --format '{{.Store.GraphRoot}}' 2>/dev/null || true)"
    fi
    if [[ -z "$root" ]]; then root="/var/lib/containers/storage"; fi
    dir="$root"
    while [[ ! -d "$dir" && "$dir" != "/" ]]; do dir="$(dirname "$dir")"; done
    free="$(df -P -BG "$dir" 2>/dev/null | awk 'NR == 2 {sub(/G$/, "", $4); print $4}')"
    if [[ "$free" =~ ^[0-9]+$ && "$free" -ge "$MIN_FREE_GB" ]]; then
        pass "Disk space: ${free}G free for Podman storage at $dir (need ${MIN_FREE_GB}G)"
    else
        hint="sudo podman system prune --all (removes unused images and build cache)"
        if [[ "$IS_WSL" -eq 1 ]]; then
            hint="$hint; on WSL2 freed space only returns to Windows after the virtual disk is compacted"
        fi
        fail "Disk space: ${free:-unknown}G free for Podman storage at $dir (need ${MIN_FREE_GB}G)" "$hint"
    fi
    line="$(df -P -BG / 2>/dev/null | awk 'NR == 2 {print $2 " " $4}')"
    total="${line%% *}"
    free="${line##* }"
    if [[ "$IS_WSL" -eq 1 ]]; then
        info "WSL2 virtual disk: $total, $free free"
        if mountpoint -q /mnt/c 2>/dev/null; then
            line="$(df -P -BG /mnt/c 2>/dev/null | awk 'NR == 2 {print $4}')"
            info "Windows drive C: $line free"
        fi
    else
        info "Root filesystem: $total, $free free"
    fi
    if command -v podman >/dev/null 2>&1; then
        img="$(as_root podman system df 2>/dev/null | awk '/^Images/ {print $4}' || true)"
        if [[ -n "$img" ]]; then info "Podman images use: $img"; fi
    fi
    return 0
}

main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --quick) QUICK=1 ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$arg" >&2
                usage >&2
                exit 2
                ;;
        esac
    done

    if [[ "$EUID" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            info "sudo is not installed; run this script as root"
        elif ! sudo -n true 2>/dev/null; then
            info "sudo may prompt for a password"
        fi
    fi

    check_platform
    check_cpu_virt
    check_kvm
    check_commands
    check_firmware
    check_qemu_kvm
    check_vsock
    check_loop
    check_podman_rootful
    check_container
    check_disk

    printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
    [[ "$FAILED" -eq 0 ]]
}

main "$@"
