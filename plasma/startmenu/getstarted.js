// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The apps Start suggests under Recommended, as "Get started", until each is installed or the
// list is hidden: the Flathub ID each one is published under, and its name. Choosing one opens its
// Store page; nothing is installed until the user chooses Install there.
.pragma library

const apps = [
    { id: "com.valvesoftware.Steam", name: "Steam" },
    { id: "com.discordapp.Discord", name: "Discord" },
    { id: "com.spotify.Client", name: "Spotify" },
    { id: "com.obsproject.Studio", name: "OBS Studio" },
];
