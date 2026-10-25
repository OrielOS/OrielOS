// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The desktop layout for a new user: the desktop, and one taskbar along the bottom of the screen
// laid out like Windows 11. Plasma runs this once, when the user has no
// plasma-org.kde.plasma.desktop-appletsrc yet. Keep the widget order in step with
// plasma/updates/, which moves existing users' panels to it.

// The desktop, as in Breeze's layout.
var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
}

var panel = new Panel;
panel.location = "bottom";
// Windows 11's taskbar is 48 px high at 100 % scale, across the whole width, and does not float.
panel.height = 48;
panel.lengthMode = "fill";
panel.floating = false;

// Two flexible spacers centre the widgets between them on the panel: the Start button and the
// pinned apps.
panel.addWidget("org.kde.plasma.panelspacer");

var start = panel.addWidget("org.kde.plasma.kickoff");
start.currentConfigGroup = ["General"];
start.writeConfig("icon", "orielos-start");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.mozilla.firefox.desktop",
    "applications:org.kde.discover.desktop",
]);
// Only as wide as its icons, so the spacers can centre it.
tasks.writeConfig("fill", false);

panel.addWidget("org.kde.plasma.panelspacer");

// The system tray holds the notifications, network, sound and other status icons.
panel.addWidget("org.kde.plasma.systemtray");

var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
// 2 puts the date under the time.
clock.writeConfig("dateDisplayFormat", 2);

// The sliver at the far right that shows the desktop.
panel.addWidget("org.kde.plasma.showdesktop");
