// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Replaces Plasma's launcher on an existing user's taskbar with OrielOS's Start menu
// (plasma/startmenu), in the same place on the panel. Plasma runs each update script once per user
// and records it in plasmashellrc. This one runs before orielos-taskbar-1.js, which then puts the
// taskbar in order around the Start menu.
//
// It only changes the default bottom panel: the user's only bottom panel, holding Kickoff, Kicker
// or the application dashboard and no Start menu yet. A custom launcher icon is kept; Plasma's and
// Fedora's stock icons become the OrielOS mark. Running it on a panel that already has the Start
// menu changes nothing.

var LAUNCHERS = ["org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.kickerdash"];
var START_MENU = "org.orielos.startmenu";
// The launcher icons Plasma and Fedora set, which are replaced by OrielOS's. The same list as in
// orielos-taskbar-1.js.
var STOCK_ICONS = ["", "start-here", "start-here-kde", "start-here-kde-symbolic", "start-here-kde-fedora"];

function log(message) {
    print("orielos-startmenu-1: " + message);
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
    if (widgets.some(function (w) { return w.type === START_MENU; })) {
        log("left panel " + panel.id + " alone: it already has the Start menu");
        return;
    }
    var launcher = widgets.filter(function (w) { return LAUNCHERS.indexOf(w.type) >= 0; })[0];
    if (!launcher) {
        log("left panel " + panel.id + " alone: it has no launcher to replace");
        return;
    }

    launcher.currentConfigGroup = ["General"];
    var icon = String(launcher.readConfig("icon", ""));
    if (STOCK_ICONS.indexOf(icon) >= 0) {
        icon = "orielos-start";
    }

    var start = panel.addWidget(START_MENU);
    start.currentConfigGroup = ["General"];
    start.writeConfig("icon", icon);

    // The Start menu takes the launcher's place; Plasma would otherwise add it at the end.
    var order = widgets.map(function (w) { return w === launcher ? start.id : w.id; });
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", order.join(";"));

    var oldType = launcher.type;
    var oldId = launcher.id;
    launcher.remove();
    panel.reloadConfig();
    log("replaced " + oldType + " " + oldId + " on panel " + panel.id + " with " + START_MENU + " "
        + start.id + " (icon " + icon + "), order now " + order.join(";"));
}

update();
