#!/usr/bin/env bash
# Installs NVIDIA's open kernel modules and the matching driver, after checking that the
# modules were built for the installed kernel and that the packages are properly signed.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

rpms=/akmods-nvidia/rpms
key=/keys/RPM-GPG-KEY-negativo17

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$rpms/kmods/nvidia-vars"
cat "$rpms/kmods/nvidia-vars"

installed_kernel="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
if [[ "$KERNEL_VERSION" != "$installed_kernel" ]]; then
    die "kernel/NVIDIA version mismatch: installed kernel is $installed_kernel, NVIDIA modules were built for $KERNEL_VERSION"
fi

dnf -y install "$rpms"/ublue-os/ublue-os-nvidia-addons-*.rpm

# Verify the userspace packages against negativo17's vendored key before installing them.
rpm --import "$key"
for f in "$rpms"/nvidia/*.rpm; do
    result="$(rpm -K "$f" 2>&1 || true)"
    if [[ "$result" != *"digests signatures OK"* ]]; then
        die "signature check failed for ${f##*/}: $result"
    fi
done

dnf config-manager setopt 'fedora-nvidia.enabled=1'
dnf -y install \
    "$rpms"/nvidia/*.x86_64.rpm "$rpms"/nvidia/*.i686.rpm "$rpms"/nvidia/*.noarch.rpm \
    "$rpms/kmods/kmod-nvidia-${KERNEL_VERSION}-${NVIDIA_AKMOD_VERSION}.${DIST_ARCH}.rpm" \
    egl-wayland libva-nvidia-driver
dnf config-manager setopt 'fedora-nvidia*.enabled=0' 'nvidia-container-toolkit.enabled=0'

kmod_version="$(rpm -q --qf '%{VERSION}' kmod-nvidia)"
driver_version="$(rpm -q --qf '%{VERSION}' nvidia-driver)"
if [[ "$kmod_version" != "$driver_version" ]]; then
    die "kmod-nvidia $kmod_version does not match nvidia-driver $driver_version"
fi

# Load the modules from the initramfs instead of omitting them.
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
mkdir -p /usr/lib/bootc/kargs.d
printf '%s\n' 'kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]' \
    >/usr/lib/bootc/kargs.d/00-nvidia.toml

dnf clean all
