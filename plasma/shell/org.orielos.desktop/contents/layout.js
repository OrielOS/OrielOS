// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The OrielOS shell's desktop layout for a new desktop: the desktop, and one taskbar along the bottom
// of the screen laid out the way people coming from Windows expect. Plasma runs this once, when the
// user has no plasma-org.orielos.desktop-appletsrc yet; contents/updates/orielos-desktop-1.js then
// copies the pins and wallpaper of a desktop the user had before the OrielOS shell.
// plasma/CMakeLists.txt also installs this file as the look-and-feel packages' layout, so applying
// the OrielOS global theme with its desktop layout gives the same taskbar.

// The desktop, as in Breeze's layout, with the OrielOS wallpaper: Daybreak with a light colour
// scheme and Nightfall with a dark one.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
    desktopsArray[j].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktopsArray[j].writeConfig("Image", "file:///usr/share/wallpapers/OrielOS/");
    // Icons in columns from the top left, as Windows arranges them (1 is columns).
    desktopsArray[j].currentConfigGroup = ["General"];
    desktopsArray[j].writeConfig("arrangement", 1);
}

var panel = new Panel;
panel.location = "bottom";
// 48 px high at 100 % scale (the height people coming from Windows are used to), across the
// whole width, and not floating.
panel.height = 48;
panel.lengthMode = "fill";
panel.floating = false;

// Two flexible spacers centre the widgets between them on the panel: the Start button and the
// pinned apps.
panel.addWidget("org.kde.plasma.panelspacer");

// OrielOS's own Start menu (plasma/startmenu), in place of Plasma's Kickoff, with the OrielOS
// mark as its button.
var start = panel.addWidget("org.orielos.startmenu");
start.currentConfigGroup = ["General"];
start.writeConfig("icon", "orielos-start");

// Search and Task View, as Sill's taskbar has them after Start.
panel.addWidget("org.orielos.search");
panel.addWidget("org.orielos.taskview");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.mozilla.firefox.desktop",
    "applications:org.kde.discover.desktop",
]);
// Only as wide as its icons, so the spacers can centre it.
tasks.writeConfig("fill", false);
// As in Windows: clicking an app with several windows shows their thumbnails to choose from (1),
// and resting on a thumbnail shows only that window in place (peek).
tasks.writeConfig("groupedTaskVisualization", 1);
tasks.writeConfig("highlightWindows", true);

panel.addWidget("org.kde.plasma.panelspacer");

// OrielOS's tray: the hidden icons button and its pane, the apps' icons put on the taskbar, and
// the location icon; Win+B opens the hidden icons. Network, sound, Bluetooth, battery, brightness
// and media are in Quick Settings, next to it, and notifications in the clock's bell.
var orielosTray = panel.addWidget("org.orielos.tray");
orielosTray.globalShortcut = "Meta+B";
// Plasma's tray stays on the taskbar, hidden by OrielOS's: its widgets for sound, media, the
// clipboard and the notification pop-ups keep running in it, and it opens the apps' menus.
var tray = panel.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ["General"];
tray.writeConfig("hiddenItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.battery",
    "org.kde.plasma.brightness",
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.notifications",
]);
// Win+A opens Quick Settings.
var quickSettings = panel.addWidget("org.orielos.quicksettings");
quickSettings.globalShortcut = "Meta+A";

// The clock and the bell, which open the notifications and the calendar; Win+N opens them too.
var clock = panel.addWidget("org.orielos.clock");
clock.globalShortcut = "Meta+N";

// The sliver at the far right that shows the desktop.
panel.addWidget("org.orielos.showdesktop");
