#!/usr/bin/env bash
# Installs the system pieces games and gaming peripherals need, while the apps themselves come
# from the Store: GameMode, umu-launcher (which the .exe dialog uses), the steam-devices udev rules
# that let Steam from the Store reach controllers, the udev rules for the Store's peripheral apps
# (Solaar, Piper through ratbagd, OpenRGB) and Fedora's default zram swap, and makes Performance
# the default power mode. Then it checks that the kernel has the ntsync and PlayStation controller
# drivers this image relies on.
# Usage: 45-gaming.sh UMU_LAUNCHER_RPM, the RPM's URL and SHA-256 as <url>@sha256:<digest>
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

pin="${1:-}"
[[ "$pin" =~ ^(https://github\.com/[A-Za-z0-9._/-]+\.rpm)@sha256:([0-9a-f]{64})$ ]] ||
    die "usage: 45-gaming.sh <https://github.com/...rpm>@sha256:<64 hex digits>"
umu_url="${BASH_REMATCH[1]}"
umu_sha256="${BASH_REMATCH[2]}"

dnf -y install --setopt=install_weak_deps=False \
    gamemode \
    steam-devices \
    solaar-udev libratbag-ratbagd openrgb-udev-rules \
    zram-generator-defaults

# Fedora doesn't package umu-launcher; its project publishes a Fedora RPM with each release. The
# download must match the pinned digest.
rpm_file="$(mktemp --suffix=.rpm)"
curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$rpm_file" "$umu_url"
printf '%s  %s\n' "$umu_sha256" "$rpm_file" | sha256sum -c --quiet - ||
    die "the umu-launcher RPM from $umu_url doesn't match its pinned SHA-256"
dnf -y install --setopt=install_weak_deps=False "$rpm_file"
rm -f "$rpm_file"

# Performance is the default power mode, on mains and on battery: tuned-ppd's performance
# profile, TuneD's throughput-performance, has no power limits, and tuned-ppd only switches to a
# battery profile for balanced. It's a default, not a lock: the mode chosen in the tray or Settings
# is saved to /etc/tuned/ppd_base_profile, which tuned-ppd reads first at every start, and /etc
# keeps it across updates. On a first start that file is empty, and tuned-ppd would take TuneD's
# recommendation (on a PC, usually balanced) before this default, so
# image/system/etc/tuned/ppd_base_profile ships "performance" as well.
sed -i 's/^default=balanced$/default=performance/' /etc/tuned/ppd.conf

# The kernel parts: ntsync, which OrielOS loads at boot, and hid-playstation for DualShock 4 and
# DualSense controllers, as modules of the installed kernel.
kver="$(ls /usr/lib/modules)"
errors=()
for module in ntsync hid-playstation; do
    modinfo -k "$kver" -F filename "$module" >/dev/null 2>&1 || errors+=("the kernel has no $module module")
done
command -v umu-run >/dev/null || errors+=("umu-launcher's umu-run is missing")
grep -qx 'default=performance' /etc/tuned/ppd.conf || errors+=("tuned-ppd's default profile in /etc/tuned/ppd.conf isn't performance")
if [[ "${#errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${errors[@]}" >&2
    exit 1
fi

dnf clean all
