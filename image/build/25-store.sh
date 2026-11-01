#!/usr/bin/env bash
# Turns Discover into the Store: renames it in the menu and everywhere else its desktop entries
# show a name, removes Discover's firmware backend so Flatpak is its only source, and makes
# Firefox (installed from Flathub on first boot) the default web browser.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

# shellcheck source-path=SCRIPTDIR source=desktop-entry.sh
source "$(dirname "${BASH_SOURCE[0]}")/desktop-entry.sh"

# Every desktop entry that shows Discover's name: the app, its URL handler, the updates
# notifier (in the menu and in autostart) and the Flatpak entry.
entries=(
    /usr/share/applications/org.kde.discover.desktop
    /usr/share/applications/org.kde.discover.urlhandler.desktop
    /usr/share/applications/org.kde.discover.notifier.desktop
    /usr/share/applications/org.kde.discover.flatpak.desktop
    /etc/xdg/autostart/org.kde.discover.notifier.desktop
)
for file in "${entries[@]}"; do
    rename_entry "$file" Discover Store "App store" image/build/25-store.sh
done

# Discover's backends are plugins. Flatpak is the Store's only source: the firmware backend and
# the AppStream preview backend (for opening a single app's metadata file, new in Plasma 6.8) are in
# plasma-discover-libs, so they are deleted here, and no other backend may be left.
rm -f /usr/lib64/qt6/plugins/discover/fwupd-backend.so /usr/lib64/qt6/plugins/discover/appstream-preview-backend.so
mapfile -t backends < <(find /usr/lib64/qt6/plugins/discover /usr/lib64/qt6/plugins/discover-notifier \
    -maxdepth 1 -name '*.so' -printf '%f\n' | sort)
[[ "${backends[*]}" == "FlatpakNotifier.so flatpak-backend.so" ]] ||
    die "Discover must have only its Flatpak backend, found: ${backends[*]:-none}"

# Firefox is the default browser, for web pages and links, before any user exists. Fedora's
# shared-mime-info already maps these to Firefox; set them here so a change there cannot
# undo it. Flatpak exports Firefox's desktop file to /var/lib/flatpak/exports/share/applications.
mimeapps=/usr/share/applications/mimeapps.list
[[ -f "$mimeapps" ]] || die "$mimeapps does not exist"
grep -q '^\[Default Applications\]$' "$mimeapps" || die "$mimeapps has no [Default Applications] section"
for type in text/html x-scheme-handler/http x-scheme-handler/https; do
    sed -i "/^${type//\//\\/}=/d" "$mimeapps"
    sed -i "/^\[Default Applications\]$/a ${type}=org.mozilla.firefox.desktop" "$mimeapps"
done

# KDE apps read the browser from kdeglobals; /etc/xdg is on KDE's configuration path.
kwriteconfig6 --file /etc/xdg/kdeglobals --group General --key BrowserApplication org.mozilla.firefox.desktop
