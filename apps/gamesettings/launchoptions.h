// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>

namespace OrielOSGames {

// A game's switches in Game Settings, each one part of its launch options:
//   dlssUpgrade     PROTON_DLSS_UPGRADE=1   newer DLSS files, on NVIDIA cards
//   waylandHdr      PROTON_ENABLE_WAYLAND=1 Wine's Wayland driver, for HDR
//   gamescope       gamescope -f --         Valve's gamescope, for scaling and frame limits
//   fpsOverlay      MANGOHUD=1              the FPS overlay, shown with Windows + G
//   gameMode        gamemoderun             GameMode
//   descriptorHeap  VKD3D_CONFIG=descriptor_heap   DX12 descriptor heaps on NVIDIA (may break)
struct GameOptions
{
    bool dlssUpgrade = false;
    bool waylandHdr = false;
    bool gamescope = false;
    bool fpsOverlay = false;
    bool gameMode = false;
    bool descriptorHeap = false;

    bool operator==(const GameOptions &) const = default;

    // The switches a game's launch options turn on.
    static GameOptions read(const QString &launchOptions);
    // The launch options with these switches, keeping everything else the user typed there. Each
    // switch adds exactly its part and turning it off removes exactly that.
    QString apply(const QString &launchOptions) const;
};

} // namespace OrielOSGames
