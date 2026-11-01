// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Carries a user's desktop over to the OrielOS shell. The first time the OrielOS shell starts for
// someone who used Plasma's desktop shell before (OrielOS v0.1 and earlier), it copies their Start
// pins, taskbar pins and wallpaper from Plasma's desktop file, plasma-org.kde.plasma.desktop-appletsrc,
// onto the taskbar that contents/layout.js has just made. It only reads that file, so going back to
// an earlier version finds the old desktop exactly as it was left.
//
// Plasma runs each update script once per user and records it in plasmashellrc. For a brand-new
// user there is no old file, and nothing changes.

var oldDesktop = ConfigFile("plasma-org.kde.plasma.desktop-appletsrc");
var containments = ConfigFile(oldDesktop, "Containments");
var startPins = "";
var taskbarPins = "";
var wallpaper = "";

containments.groupList.forEach(function (containmentId) {
    var containment = ConfigFile(containments, containmentId);
    var image = ConfigFile(ConfigFile(ConfigFile(containment, "Wallpaper"), "org.kde.image"), "General").readEntry("Image");
    if (image) {
        wallpaper = String(image);
    }
    var applets = ConfigFile(containment, "Applets");
    applets.groupList.forEach(function (appletId) {
        var applet = ConfigFile(applets, appletId);
        var plugin = String(applet.readEntry("plugin"));
        var general = ConfigFile(ConfigFile(applet, "Configuration"), "General");
        if (plugin === "org.orielos.startmenu" && general.readEntry("favorites")) {
            startPins = String(general.readEntry("favorites"));
        }
        if ((plugin === "org.kde.plasma.icontasks" || plugin === "org.kde.plasma.taskmanager") && general.readEntry("launchers")) {
            taskbarPins = String(general.readEntry("launchers"));
        }
    });
});

if (!startPins && !taskbarPins && !wallpaper) {
    print("orielos-desktop-1: no earlier desktop to carry over");
} else {
    panels().forEach(function (panel) {
        panel.widgets().forEach(function (widget) {
            if (widget.type === "org.orielos.startmenu" && startPins) {
                widget.currentConfigGroup = ["General"];
                widget.writeConfig("favorites", startPins.split(","));
                print("orielos-desktop-1: copied the Start pins");
            }
            if (widget.type === "org.kde.plasma.icontasks" && taskbarPins) {
                widget.currentConfigGroup = ["General"];
                widget.writeConfig("launchers", taskbarPins.split(","));
                print("orielos-desktop-1: copied the taskbar pins");
            }
        });
    });
    if (wallpaper) {
        desktops().forEach(function (desktop) {
            desktop.wallpaperPlugin = "org.kde.image";
            desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
            desktop.writeConfig("Image", wallpaper);
        });
        print("orielos-desktop-1: copied the wallpaper");
    }
}
