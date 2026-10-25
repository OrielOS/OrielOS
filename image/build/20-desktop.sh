#!/usr/bin/env bash
# Installs the KDE Plasma desktop listed in image/packages/desktop.txt, makes Flathub the
# only Flatpak source, starts SDDM at boot and sets the Plymouth boot splash.
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

systemctl enable sddm.service
systemctl set-default graphical.target

# 90-finalise.sh rebuilds the initramfs with the theme in it.
plymouth-set-default-theme bgrt

dnf clean all
