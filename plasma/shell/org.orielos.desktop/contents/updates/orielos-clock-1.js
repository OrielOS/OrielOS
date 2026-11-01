// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Swaps Plasma's digital clock for OrielOS's clock and bell, in the same place, on taskbars made
// before it existed, and moves Plasma's notifications icon among the tray's hidden icons, since the
// bell shows it. Plasma runs this once per user; it also runs right after layout.js for a new user,
// whose taskbar already has the clock and bell.

function log(message) {
    print("orielos-clock-1: " + message);
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
    var old = widgets.filter(function (w) { return w.type === "org.kde.plasma.digitalclock"; })[0];
    if (!old || widgets.some(function (w) { return w.type === "org.orielos.clock"; })) {
        return;
    }
    var tray = widgets.filter(function (w) { return w.type === "org.kde.plasma.systemtray"; })[0];
    if (tray) {
        tray.currentConfigGroup = ["General"];
        var hidden = tray.readConfig("hiddenItems", []);
        if (typeof hidden === "string") {
            hidden = hidden.length > 0 ? hidden.split(",") : [];
        }
        if (hidden.indexOf("org.kde.plasma.notifications") < 0) {
            hidden.push("org.kde.plasma.notifications");
            tray.writeConfig("hiddenItems", hidden);
            tray.reloadConfig();
        }
    }
    var clock = panel.addWidget("org.orielos.clock");
    var ordered = widgets.map(function (w) { return w === old ? clock : w; });
    old.remove();
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ordered.map(function (w) { return w.id; }).join(";"));
    panel.reloadConfig();
    log("swapped the digital clock for the clock and bell");
});
