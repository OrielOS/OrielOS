// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Brings taskbars made before them the behaviours layout.js now gives new ones, as in Windows:
// clicking an app with several windows shows their thumbnails, resting on a thumbnail shows only
// that window (peek), Win+A opens Quick Settings, Win+B the hidden tray icons, and right-clicking
// empty taskbar space
// offers System Monitor and Taskbar settings (org.orielos.panelmenu). Settings the user changed
// from Plasma's defaults, a shortcut they gave the tray, and another right-click menu they chose are
// kept. Plasma runs this once per user; the right-click menu shows from the next sign-in.

function log(message) {
    print("orielos-taskbar-behaviour-1: " + message);
}

panels().forEach(function (panel) {
    panel.widgets("org.kde.plasma.icontasks").forEach(function (tasks) {
        tasks.currentConfigGroup = ["General"];
        // Plasma's defaults: cycling through the windows (0) and no peek.
        if (String(tasks.readConfig("groupedTaskVisualization", 0)) === "0") {
            tasks.writeConfig("groupedTaskVisualization", 1);
            log("clicking an app with several windows shows their thumbnails");
        }
        if (String(tasks.readConfig("highlightWindows", false)) === "false") {
            tasks.writeConfig("highlightWindows", true);
            log("resting on a thumbnail shows only that window");
        }
    });
    panel.widgets("org.orielos.quicksettings").forEach(function (quickSettings) {
        if (!quickSettings.globalShortcut) {
            quickSettings.globalShortcut = "Meta+A";
            log("gave Quick Settings Win+A");
        }
    });
    panel.widgets("org.kde.plasma.systemtray").forEach(function (tray) {
        if (!tray.globalShortcut) {
            tray.globalShortcut = "Meta+B";
            log("gave the hidden icons Win+B");
        }
    });
});

var plugins = ConfigFile("plasma-org.orielos.desktop-appletsrc", "ActionPlugins");
// Plasma keeps each kind of containment's mouse actions apart; 1 is the panels'.
var panelActions = ConfigFile(plugins, "1");
var current = panelActions.readEntry("RightButton;NoModifier");
if (current === "" || current === "org.kde.contextmenu") {
    panelActions.writeEntry("RightButton;NoModifier", "org.orielos.panelmenu");
    log("the taskbar's right button opens OrielOS's menu");
} else {
    log("the taskbar's right button keeps " + current);
}
