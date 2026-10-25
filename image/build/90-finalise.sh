#!/usr/bin/env bash
# Checks that no build tools are installed, that the first boot will run Plasma Setup and install
# Firefox (and enables the latter) and that new users get the taskbar, refreshes the icon cache,
# rebuilds the initramfs for the installed kernel, removes build
# leftovers and lints the image.
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

# The preset file is not applied while the image builds, and the unit is copied in after the
# package layers, so enable it here. The stamp file that ends it must not be in the image.
systemctl enable orielos-flatpak-setup.service
if [[ "$(systemctl is-enabled orielos-flatpak-setup.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-flatpak-setup.service is not enabled\n' >&2
    exit 1
fi
if [[ -e /var/lib/orielos/flatpak-setup.done ]]; then
    printf 'error: /var/lib/orielos/flatpak-setup.done exists, so Firefox would never be installed\n' >&2
    exit 1
fi

# New users get the taskbar from OrielOS's look-and-feel package, which 20-desktop.sh makes the
# default; the package and the Start button's icon come from the app-builder stage.
lnf=org.orielos.desktop
taskbar_errors=()
if [[ "$(kreadconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage)" != "$lnf" ]]; then
    taskbar_errors+=("/etc/xdg/kdeglobals does not make $lnf the default look-and-feel")
fi
if [[ ! -f "/usr/share/plasma/look-and-feel/$lnf/contents/layouts/org.kde.plasma.desktop-layout.js" ]]; then
    taskbar_errors+=("the $lnf look-and-feel package or its layout script is not installed")
fi
if [[ ! -f /usr/share/icons/hicolor/scalable/apps/orielos-start.svg ]]; then
    taskbar_errors+=("the Start button's icon, orielos-start.svg, is not installed")
fi
if [[ "${#taskbar_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${taskbar_errors[@]}" >&2
    exit 1
fi
# The image's files all have the same timestamp, so icon loaders would trust the old icon cache
# and never find icons added after it was made, such as the Start button's.
gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor

kver="$(ls /usr/lib/modules)"
dracut --no-hostonly --kver "$kver" --reproducible --zstd --add "ostree plymouth" -f "/usr/lib/modules/$kver/initramfs.img"

dnf clean all
rm -rf /var/cache/* /var/log/* /var/lib/dnf /tmp/* /run/dnf /run/sddm

bootc container lint
