// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Adds Quick Settings right after the tray on taskbars made before it existed, and moves Plasma's
// network, sound, Bluetooth, battery, brightness and media icons among the tray's hidden icons,
// since Quick Settings shows them. Plasma runs this once per user; it also runs right after
// layout.js for a new user, whose taskbar already has Quick Settings.

var COVERED = [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.battery",
    "org.kde.plasma.brightness",
    "org.kde.plasma.mediacontroller",
];

function log(message) {
    print("orielos-quicksettings-1: " + message);
}

// The panel's widget ids in the order they show.
function currentOrder(panel) {
    var ids = panel.widgetIds;
    panel.currentConfigGroup = ["General"];
    var order = String(panel.readConfig("AppletOrder", "")).split(";")
        .map(function (id) { return Number(id); })
        .filter(function (id) { return ids.indexOf(id) >= 0; });
    ids.forEach(function (id) {
        if (order.indexOf(id) < 0) {
            order.push(id);
        }
    });
    return order;
}

panels().forEach(function (panel) {
    var widgets = currentOrder(panel).map(function (id) { return panel.widgetById(id); })
        .filter(function (w) { return w; });
    var tray = widgets.filter(function (w) { return w.type === "org.kde.plasma.systemtray"; })[0];
    if (!tray || widgets.some(function (w) { return w.type === "org.orielos.quicksettings"; })) {
        return;
    }
    tray.currentConfigGroup = ["General"];
    var hidden = tray.readConfig("hiddenItems", []);
    if (typeof hidden === "string") {
        hidden = hidden.length > 0 ? hidden.split(",") : [];
    }
    COVERED.forEach(function (id) {
        if (hidden.indexOf(id) < 0) {
            hidden.push(id);
        }
    });
    tray.writeConfig("hiddenItems", hidden);
    tray.reloadConfig();

    var quickSettings = panel.addWidget("org.orielos.quicksettings");
    var ordered = [];
    widgets.forEach(function (w) {
        ordered.push(w);
        if (w === tray) {
            ordered.push(quickSettings);
        }
    });
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ordered.map(function (w) { return w.id; }).join(";"));
    panel.reloadConfig();
    log("added Quick Settings after the tray");
});
