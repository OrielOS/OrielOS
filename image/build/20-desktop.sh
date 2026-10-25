#!/usr/bin/env bash
# Installs the KDE Plasma desktop listed in image/packages/desktop.txt, makes Flathub the
# only Flatpak source, starts Plasma Setup on first boot and SDDM at every boot, makes OrielOS's
# look-and-feel the default and sets the Plymouth boot splash.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

list=/packages/desktop.txt

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# One package per line; drop comments, surrounding spaces and blank lines.
mapfile -t packages < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$' || true)
[[ "${#packages[@]}" -gt 0 ]] || die "no packages found in $list"

dnf -y install --setopt=install_weak_deps=False "${packages[@]}"

# Flathub is the only source of apps. Flatpak would add Fedora's own remote on first boot;
# instead Flathub's remote file is installed where Flatpak reads its default remotes, without
# Fedora's filter, so all of Flathub is available.
systemctl disable flatpak-add-fedora-repos.service
mkdir -p /usr/share/flatpak/remotes.d
sed '/^Filter=/d' /usr/lib/fedora-third-party/conf.d/fedora-flathub.flatpakrepo \
    >/usr/share/flatpak/remotes.d/flathub.flatpakrepo

# Plasma Setup runs before SDDM until it writes /etc/plasma-setup-done, which the image must
# not contain; 90-finalise.sh checks that.
systemctl enable plasma-setup.service sddm.service
systemctl set-default graphical.target

# OrielOS's look-and-feel package (installed from plasma/ with the apps) is the default for every
# user; its layout script sets up the taskbar for each new user. /etc/xdg comes before Fedora's
# kde-settings profile on XDG_CONFIG_DIRS, so this overrides Fedora's look-and-feel.
# 90-finalise.sh checks that the package is installed.
kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage org.orielos.desktop
# Plasma's Day-Night Cycle switches between these two when it's turned on.
kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key DefaultLightLookAndFeel org.orielos.desktop
kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key DefaultDarkLookAndFeel org.orielos.desktop.dark

# 90-finalise.sh rebuilds the initramfs with the theme in it.
plymouth-set-default-theme bgrt

dnf clean all
