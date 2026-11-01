// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Adds Sill's Search and Task View buttons right after Start on taskbars made before they existed.
// A taskbar that already has them, or has no Start menu, is left as it is. Plasma runs this once
// per user; it also runs right after layout.js for a new user, whose taskbar already has both.

function log(message) {
    print("orielos-buttons-1: " + message);
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
    var start = widgets.filter(function (w) { return w.type === "org.orielos.startmenu"; })[0];
    if (!start) {
        return;
    }
    var added = [];
    ["org.orielos.search", "org.orielos.taskview"].forEach(function (type) {
        if (!widgets.some(function (w) { return w.type === type; })) {
            added.push(panel.addWidget(type));
        }
    });
    if (added.length === 0) {
        log("the taskbar already has Search and Task View");
        return;
    }
    var ordered = [];
    widgets.forEach(function (w) {
        ordered.push(w);
        if (w === start) {
            ordered = ordered.concat(added);
        }
    });
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", ordered.map(function (w) { return w.id; }).join(";"));
    panel.reloadConfig();
    log("added " + added.map(function (w) { return w.type; }).join(" and ") + " after Start");
});
