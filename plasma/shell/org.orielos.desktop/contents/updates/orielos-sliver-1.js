// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Swaps Plasma's Show Desktop button for OrielOS's show desktop sliver, in the same place, on
// taskbars made before the sliver existed. Plasma runs this once per user; it also runs right after
// layout.js for a new user, whose taskbar already has the sliver.

function log(message) {
    print("orielos-sliver-1: " + message);
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
    var old = widgets.filter(function (w) { return w.type === "org.kde.plasma.showdesktop"; })[0];
    if (!old || widgets.some(function (w) { return w.type === "org.orielos.showdesktop"; })) {
        return;
    }
    var sliver = panel.addWidget("org.orielos.showdesktop");
    var ordered = widgets.map(function (w) { return w === old ? sliver : w; });
    old.remove();
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ordered.map(function (w) { return w.id; }).join(";"));
    panel.reloadConfig();
    log("swapped Show Desktop for the sliver");
});
