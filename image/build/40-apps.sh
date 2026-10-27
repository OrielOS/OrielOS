#!/usr/bin/env bash
# Installs the runtime libraries OrielOS's own apps need, and the tools orielos-update uses.
# Plasma and bootc already pull most of them in; listing them here keeps them installed if the
# desktop package set changes.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

dnf -y install --setopt=install_weak_deps=False \
    qt6-qtbase-gui qt6-qtdeclarative kf6-kirigami kf6-ki18n kf6-kcoreaddons

# The update notifier's tray icon, notifications and single-instance service.
dnf -y install --setopt=install_weak_deps=False \
    kf6-kstatusnotifieritem kf6-knotifications kf6-kdbusaddons

# The Update settings page is a Plasma settings module, shown in System Settings.
dnf -y install --setopt=install_weak_deps=False kf6-kcmutils plasma-systemsettings

# orielos-update reads a channel's newest build with skopeo, and the Update settings page asks it
# to check, pause, change channel, go back or remove the previous version through pkexec.
dnf -y install --setopt=install_weak_deps=False skopeo polkit

# orielos-update reads update archives with tar and bootc's status with jq.
dnf -y install --setopt=install_weak_deps=False tar jq

dnf clean all

# Run this app (apps/runapp) opens Windows programs, before any user exists. Its desktop file comes
# from the app-builder stage later; 90-finalise.sh checks it's there.
mimeapps=/usr/share/applications/mimeapps.list
[[ -f "$mimeapps" ]] || {
    echo "error: $mimeapps does not exist" >&2
    exit 1
}
grep -q '^\[Default Applications\]$' "$mimeapps" || {
    echo "error: $mimeapps has no [Default Applications] section" >&2
    exit 1
}
for type in application/x-ms-dos-executable application/x-msdownload application/vnd.microsoft.portable-executable \
    application/x-msi application/x-dosexec; do
    sed -i "/^${type//\//\\/}=/d" "$mimeapps"
    sed -i "/^\[Default Applications\]$/a ${type}=org.orielos.RunApp.desktop" "$mimeapps"
done
