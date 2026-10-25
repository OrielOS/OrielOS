#!/usr/bin/env bash
# Checks that no build tools are installed and that the first boot will run Plasma Setup,
# rebuilds the initramfs for the installed kernel, removes build leftovers and lints the image.
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

# Plasma Setup creates the first user account on first boot. It only runs while its done marker
# is missing, and only offers to create an account when there is no regular user yet.
first_boot_errors=()
if [[ "$(systemctl is-enabled plasma-setup.service 2>&1)" != "enabled" ]]; then
    first_boot_errors+=("plasma-setup.service is not enabled")
fi
if [[ -e /etc/plasma-setup-done ]]; then
    first_boot_errors+=("/etc/plasma-setup-done exists, so Plasma Setup would never run")
fi
mapfile -t users < <(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd)
if [[ "${#users[@]}" -gt 0 ]]; then
    first_boot_errors+=("the image has regular users (${users[*]}); Plasma Setup creates the first one")
fi
if [[ "${#first_boot_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${first_boot_errors[@]}" >&2
    exit 1
fi

kver="$(ls /usr/lib/modules)"
dracut --no-hostonly --kver "$kver" --reproducible --zstd --add "ostree plymouth" -f "/usr/lib/modules/$kver/initramfs.img"

dnf clean all
rm -rf /var/cache/* /var/log/* /var/lib/dnf /tmp/* /run/dnf /run/sddm

bootc container lint
