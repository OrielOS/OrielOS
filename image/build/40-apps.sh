#!/usr/bin/env bash
# Installs the runtime libraries OrielOS's own apps need, and the tools orielos-update uses.
# Plasma and bootc already pull most of them in; listing them here keeps them installed if the
# desktop package set changes.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

dnf -y install --setopt=install_weak_deps=False \
    qt6-qtbase-gui qt6-qtdeclarative kf6-kirigami kf6-ki18n kf6-kcoreaddons

# orielos-update reads update archives with tar and bootc's status with jq.
dnf -y install --setopt=install_weak_deps=False tar jq

dnf clean all
