// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Adds OrielOS's tray (org.orielos.tray) just before Plasma's on taskbars made before it existed,
// and moves Win+B to it. Plasma's tray stays, hidden by OrielOS's, for the widgets that run in it.
// Plasma runs this once per user; it also runs right after layout.js for a new user, whose
// taskbar already has OrielOS's tray.

function log(message) {
    print("orielos-tray-1: " + message);
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
    if (!tray || widgets.some(function (w) { return w.type === "org.orielos.tray"; })) {
        return;
    }
    var orielosTray = panel.addWidget("org.orielos.tray");
    var shortcut = tray.globalShortcut || "Meta+B";
    tray.globalShortcut = "";
    orielosTray.globalShortcut = shortcut;

    var ordered = [];
    widgets.forEach(function (w) {
        if (w === tray) {
            ordered.push(orielosTray);
        }
        ordered.push(w);
    });
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ordered.map(function (w) { return w.id; }).join(";"));
    panel.reloadConfig();
    log("added OrielOS's tray before Plasma's and gave it " + shortcut);
});
