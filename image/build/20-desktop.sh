#!/usr/bin/env bash
# Interim minimal Plasma desktop with SDDM; the full desktop is defined later.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

dnf -y install --setopt=install_weak_deps=False \
    plasma-desktop plasma-workspace plasma-workspace-wayland kwin sddm sddm-breeze sddm-kcm \
    plasma-nm plasma-pa konsole dolphin breeze-icon-theme NetworkManager-wifi \
    mesa-dri-drivers mesa-vulkan-drivers

systemctl enable sddm.service
systemctl set-default graphical.target

dnf clean all
