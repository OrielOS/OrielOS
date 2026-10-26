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
