// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// For desktops made before OrielOS's desktop menu: arranges the desktop's icons in columns from the
// top left, as Windows does, and gives the desktop's right button OrielOS's menu in Windows' order
// (org.orielos.desktopmenu) in place of Plasma's standard one. A desktop whose right button has
// another menu the user chose keeps it. Plasma reads the right button's menu when it starts, so it
// shows from the next sign-in. Plasma runs this once per user.

function log(message) {
    print("orielos-desktop-icons-1: " + message);
}

desktops().forEach(function (desktop) {
    desktop.currentConfigGroup = ["General"];
    desktop.writeConfig("arrangement", 1);
});

var plugins = ConfigFile("plasma-org.orielos.desktop-appletsrc", "ActionPlugins");
var desktopActions = ConfigFile(plugins, "0");
var current = desktopActions.readEntry("RightButton;NoModifier");
if (current === "" || current === "org.kde.contextmenu") {
    desktopActions.writeEntry("RightButton;NoModifier", "org.orielos.desktopmenu");
    log("the desktop's right button opens OrielOS's menu");
} else {
    log("the desktop's right button keeps " + current);
}
