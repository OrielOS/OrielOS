// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// For accounts whose welcome screen was set to Breeze's when an OrielOS look-and-feel was applied:
// moves it to OrielOS's welcome screen. A welcome screen the user chose themselves is left alone.
// Earlier OrielOS versions have no welcome screen in their look-and-feel packages and fall back to
// Breeze's for the same setting. Plasma runs this once per user.

function log(message) {
    print("orielos-splash-1: " + message);
}

var splash = ConfigFile("ksplashrc", "KSplash");
var theme = splash.readEntry("Theme");
if (theme === "org.kde.breeze.desktop") {
    splash.writeEntry("Theme", "org.orielos.desktop");
    log("the welcome screen is OrielOS's");
} else {
    log("the welcome screen keeps " + (theme === "" ? "the default" : theme));
}
