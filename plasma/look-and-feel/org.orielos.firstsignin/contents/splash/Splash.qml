/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// The welcome screen at a new account's first sign-in: OrielOS's usual one (WelcomeSplash.qml,
// installed from plasma/look-and-feel/splash), saying that the desktop is being set up while
// Plasma prepares the new account. New accounts start with it chosen (/etc/skel/.config/ksplashrc);
// first-sign-in then hands later sign-ins back to the usual screen.

import QtQuick

WelcomeSplash {
    message: i18ndc("orielos-first-run", "@info:status shown while a new account's desktop is set up at its first sign-in", "Setting up your desktop")
}
