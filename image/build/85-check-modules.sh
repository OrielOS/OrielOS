#!/usr/bin/env bash
# Fails the build unless every kernel module is signed by an allowed signer (image/module-signers.txt),
# exactly one kernel is installed and the NVIDIA kernel module and driver are one version, 32-bit libraries included.
# Then installs the signer list to /usr/share/orielos for Settings' Device security page.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

signers_file=/image/module-signers.txt

# NVIDIA driver components that must all match kmod-nvidia's version-release, whatever their architecture.
components='^(nvidia-driver(-.*)?|nvidia-kmod-common|nvidia-modprobe|nvidia-persistenced|nvidia-settings|nvidia-xconfig|nvidia-libXNVCtrl|libnvidia-.*|xorg-x11-nvidia)$'
# Installed NVIDIA packages that are not driver components and have their own versions:
#   nvidia-gpu-firmware      from linux-firmware
#   nvidia-driver-selinux    SELinux policy for the driver; the pattern matches it, so it is skipped below
#   ublue-os-nvidia-addons   Universal Blue's configuration files
#   libva-nvidia-driver      the VA-API driver, versioned separately
excluded='^nvidia-driver-selinux$'
# The 32-bit libraries that Steam needs.
required_i686=(nvidia-driver-libs nvidia-driver-cuda-libs libnvidia-fbc)

errors=()
fail() { errors+=("$1"); }

mapfile -t allowed < <(grep -v -e '^#' -e '^[[:space:]]*$' "$signers_file")
[[ "${#allowed[@]}" -gt 0 ]] || {
    printf 'error: no signers in %s\n' "$signers_file" >&2
    exit 1
}

# Exactly one kernel, and the one the NVIDIA modules were built for.
mapfile -t kernels < <(ls /usr/lib/modules)
if [[ "${#kernels[@]}" -ne 1 ]]; then
    fail "expected exactly one kernel in /usr/lib/modules, found ${#kernels[@]}: ${kernels[*]:-none}"
fi
kver="${kernels[0]:-}"
mapfile -t kernel_pkgs < <(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
if [[ "${#kernel_pkgs[@]}" -ne 1 || "${kernel_pkgs[0]}" != "$kver" ]]; then
    fail "installed kernel packages (${kernel_pkgs[*]}) do not match /usr/lib/modules/$kver"
fi
nvidia_kernel="$(modinfo -k "$kver" -F vermagic nvidia | awk '{print $1}')"
if [[ "$nvidia_kernel" != "$kver" ]]; then
    fail "the NVIDIA modules were built for kernel ${nvidia_kernel:-unknown}, but the installed kernel is $kver"
fi

# Every module has an allowed signer.
declare -A counts=()
offenders=()
while IFS=$'\t' read -r path signer; do
    ok=0
    for s in "${allowed[@]}"; do
        if [[ "$signer" == "$s" ]]; then ok=1; fi
    done
    if [[ "$ok" -eq 1 ]]; then
        counts["$signer"]=$((${counts["$signer"]:-0} + 1))
    else
        offenders+=("$path (signer: ${signer:-none})")
    fi
    total=$((${total:-0} + 1))
done < <(find "/usr/lib/modules/$kver" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \) -print0 |
    xargs -0 -r -n 500 modinfo |
    awk '
        function flush() { if (path != "") printf "%s\t%s\n", path, signer; path = ""; signer = "" }
        /^filename:/ { flush(); sub(/^filename:[[:space:]]*/, ""); path = $0; next }
        /^signer:/ { sub(/^signer:[[:space:]]*/, ""); signer = $0 }
        END { flush() }')
if [[ "${#offenders[@]}" -gt 0 ]]; then
    fail "${#offenders[@]} kernel modules are not signed by an allowed signer (allowed: ${allowed[*]}):"
    for o in "${offenders[@]}"; do fail "    $o"; done
fi
if [[ "${total:-0}" -eq 0 ]]; then fail "no kernel modules found in /usr/lib/modules/$kver"; fi

# Every NVIDIA driver component has kmod-nvidia's version-release.
driver="$(rpm -q --qf '%{VERSION}-%{RELEASE}' kmod-nvidia)"
mapfile -t pkgs < <(rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' | sort)
found=0
for line in "${pkgs[@]}"; do
    read -r name version arch <<<"$line"
    [[ "$name" =~ $components && ! "$name" =~ $excluded ]] || continue
    found=$((found + 1))
    if [[ "$version" != "$driver" ]]; then
        fail "$name.$arch is $version, but kmod-nvidia is $driver"
    fi
done
if [[ "$found" -eq 0 ]]; then fail "no NVIDIA driver packages are installed"; fi

for name in "${required_i686[@]}"; do
    if ! rpm -q "$name.i686" >/dev/null 2>&1; then fail "$name.i686 is not installed"; fi
done

if [[ "${#errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${errors[@]}" >&2
    exit 1
fi

# Settings' Device security page checks the running system's modules against the same list.
install -D -m 0644 "$signers_file" /usr/share/orielos/module-signers.txt

printf 'kernel:         %s\n' "$kver"
printf 'kmod-nvidia:    %s\n' "$driver"
printf 'nvidia-driver:  %s (%s packages)\n' "$driver" "$found"
printf 'modules:        %s\n' "$total"
for s in "${allowed[@]}"; do
    printf '  %-26s %s\n' "$s" "${counts["$s"]:-0}"
done
