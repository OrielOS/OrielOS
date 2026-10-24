#!/usr/bin/env bash
# Rebuilds the initramfs for the installed kernel, removes build leftovers and lints the image.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

kver="$(ls /usr/lib/modules)"
dracut --no-hostonly --kver "$kver" --reproducible --zstd --add ostree -f "/usr/lib/modules/$kver/initramfs.img"

dnf clean all
rm -rf /var/cache/* /var/log/* /var/lib/dnf /tmp/* /run/dnf /run/sddm

bootc container lint
