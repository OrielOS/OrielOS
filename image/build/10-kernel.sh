#!/usr/bin/env bash
# Replaces the base image's kernel with the Fedora CoreOS stable kernel, locks it, and
# installs the signed common kernel modules (xone, xpadneo, OpenRazer, v4l2loopback).
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

kernel_rpms=/akmods/kernel-rpms
akmods=/akmods/rpms
plugins=(05-rpmostree.install 50-dracut.install)

dnf -y install dnf5-plugins

rpm -qa 'kernel*' | sort
mapfile -t old < <(rpm -qa --qf '%{NAME}\n' kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-tools kernel-tools-libs)
for pkg in "${old[@]}"; do rpm --erase --nodeps "$pkg"; done
rm -rf /usr/lib/modules

# Skip the rpm-ostree and dracut kernel-install plugins; the initramfs is rebuilt once at the end.
cd /usr/lib/kernel/install.d
for p in "${plugins[@]}"; do
    if [[ -e "$p" ]]; then
        mv "$p" "$p.bak"
        printf '#!/bin/sh\nexit 0\n' >"$p"
        chmod +x "$p"
    fi
done

dnf -y install \
    "$kernel_rpms"/kernel-[0-9]*.rpm \
    "$kernel_rpms"/kernel-core-*.rpm \
    "$kernel_rpms"/kernel-modules-*.rpm \
    "$akmods"/ublue-os/ublue-os-akmods-addons-*.rpm

for p in "${plugins[@]}"; do
    if [[ -e "$p.bak" ]]; then mv -f "$p.bak" "$p"; fi
done

dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

# The kernel RPMs carry no RPM signature; the modules are signed with the key from ublue-os-akmods-addons.
dnf -y install \
    "$akmods"/kmods/kmod-xone-*.rpm \
    "$akmods"/kmods/kmod-xpadneo-*.rpm \
    "$akmods"/kmods/kmod-openrazer-*.rpm \
    "$akmods"/kmods/kmod-v4l2loopback-*.rpm \
    "$akmods"/common/xone-kmod-common-*.rpm \
    "$akmods"/common/xpadneo-kmod-common-*.rpm \
    "$akmods"/common/openrazer-*.rpm \
    "$akmods"/common/v4l2loopback-*.rpm

dnf clean all
