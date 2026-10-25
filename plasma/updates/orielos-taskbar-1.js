// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Moves an existing user's taskbar to the Windows 11-style order of OrielOS's layout
// (plasma/look-and-feel/org.orielos.desktop): spacer, Start button, task manager, spacer,
// system tray, clock and the show-desktop sliver. Plasma runs each update script once per user
// and records it in plasmashellrc.
//
// It only changes the default bottom panel: the user's only bottom panel, holding a launcher and
// a task manager. It reuses the widgets already on the panel and adds only the missing ones, so
// nothing is duplicated; other widgets are kept, just before the system tray. Running it on a
// panel that is already in order changes nothing.

var ORDER = [
    "org.kde.plasma.panelspacer",
    "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks",
    "org.kde.plasma.panelspacer",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.showdesktop",
];
// Widgets that count as the Start button or the task manager when the panel has another kind.
var SAME_ROLE = {
    "org.kde.plasma.kickoff": ["org.kde.plasma.kicker", "org.kde.plasma.kickerdash"],
    "org.kde.plasma.icontasks": ["org.kde.plasma.taskmanager"],
};
// The launcher icons Plasma and Fedora set, which are replaced by OrielOS's.
var STOCK_ICONS = ["", "start-here", "start-here-kde", "start-here-kde-symbolic", "start-here-kde-fedora"];

function log(message) {
    print("orielos-taskbar-1: " + message);
}

function hasRole(widget, type) {
    return widget.type === type || (SAME_ROLE[type] || []).indexOf(widget.type) >= 0;
}

// The panel's widget ids in the order shown: the saved order first, then any others.
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

function update() {
    var bottom = panels().filter(function (p) { return p.location === "bottom"; });
    if (bottom.length !== 1) {
        log("left the panels alone: found " + bottom.length + " bottom panels, expected 1");
        return;
    }
    var panel = bottom[0];
    var widgets = currentOrder(panel).map(function (id) { return panel.widgetById(id); })
        .filter(function (w) { return w; });
    var isDefault = ["org.kde.plasma.kickoff", "org.kde.plasma.icontasks"].every(function (type) {
        return widgets.some(function (w) { return hasRole(w, type); });
    });
    if (!isDefault) {
        log("left panel " + panel.id + " alone: it has no launcher or no task manager");
        return;
    }

    // Fill each slot with the first unused widget of that kind, or a new one.
    var used = [];
    var slots = ORDER.map(function (type) {
        var found = widgets.filter(function (w) { return used.indexOf(w) < 0 && hasRole(w, type); })[0];
        if (!found) {
            found = panel.addWidget(type);
            log("added " + type + " to panel " + panel.id);
        }
        used.push(found);
        return found;
    });
    var others = widgets.filter(function (w) { return used.indexOf(w) < 0; });
    var trayIndex = ORDER.indexOf("org.kde.plasma.systemtray");
    var ordered = slots.slice(0, trayIndex).concat(others, slots.slice(trayIndex));
    var oldIds = widgets.map(function (w) { return w.id; }).join(";");
    var newIds = ordered.map(function (w) { return w.id; }).join(";");

    if (newIds !== oldIds) {
        panel.currentConfigGroup = ["General"];
        panel.writeConfig("AppletOrder", newIds);
        log("reordered panel " + panel.id + " from " + (oldIds || "nothing") + " to " + newIds);
    }

    var start = slots[ORDER.indexOf("org.kde.plasma.kickoff")];
    start.currentConfigGroup = ["General"];
    if (STOCK_ICONS.indexOf(String(start.readConfig("icon", ""))) >= 0) {
        start.writeConfig("icon", "orielos-start");
        log("set the Start button's icon to orielos-start");
    }

    var tasks = slots[ORDER.indexOf("org.kde.plasma.icontasks")];
    tasks.currentConfigGroup = ["General"];
    if (tasks.readConfig("fill", true) !== false) {
        tasks.writeConfig("fill", false);
        log("stopped the task manager filling the panel, so the spacers centre it");
    }

    if (newIds === oldIds) {
        log("panel " + panel.id + " already has the OrielOS widget order");
    }
    panel.reloadConfig();
}

update();
