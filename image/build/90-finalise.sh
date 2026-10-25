#!/usr/bin/env bash
# Checks that no build tools are installed, rebuilds the initramfs for the installed kernel,
# removes build leftovers and lints the image.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

# The apps are built in the app-builder stage; compilers and headers must stay out of the image.
mapfile -t build_tools < <(rpm -qa --qf '%{NAME}\n' |
    grep -E -- '-devel$|^(gcc|gcc-c\+\+|cmake|extra-cmake-modules)$' | sort -u || true)
if [[ "${#build_tools[@]}" -gt 0 ]]; then
    printf 'error: build tools must not be installed in the final image; found: %s\n' "${build_tools[*]}" >&2
    printf 'error: build software in the app-builder stage and copy only the result into the image\n' >&2
    exit 1
fi

kver="$(ls /usr/lib/modules)"
dracut --no-hostonly --kver "$kver" --reproducible --zstd --add ostree -f "/usr/lib/modules/$kver/initramfs.img"

dnf clean all
rm -rf /var/cache/* /var/log/* /var/lib/dnf /tmp/* /run/dnf /run/sddm

bootc container lint
