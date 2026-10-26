// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Puts OrielOS's Settings app in place of System Settings among an existing user's pinned apps in
// Start. Settings took over Win+I and Start's listing from System Settings, which Start no longer
// shows. Plasma runs each update script once per user and records it in plasmashellrc.
//
// A Start menu still on the default pins has none saved, and the default now holds Settings, so
// it's left alone; so is one that doesn't pin System Settings.

var START_MENU = "org.orielos.startmenu";
var OLD_ID = "systemsettings.desktop";
var NEW_ID = "org.orielos.Settings.desktop";

function log(message) {
    print("orielos-startmenu-2: " + message);
}

function pinnedIds(value) {
    if (Array.isArray(value)) {
        return value.map(function (id) { return String(id); });
    }
    var text = String(value);
    return text === "" ? [] : text.split(",");
}

panels().forEach(function (panel) {
    panel.widgets(START_MENU).forEach(function (widget) {
        widget.currentConfigGroup = ["General"];
        var pinned = pinnedIds(widget.readConfig("favorites", ""));
        var index = pinned.indexOf(OLD_ID);
        if (index < 0) {
            return;
        }
        if (pinned.indexOf(NEW_ID) >= 0) {
            pinned.splice(index, 1);
        } else {
            pinned[index] = NEW_ID;
        }
        widget.writeConfig("favorites", pinned);
        log("pinned Settings in place of System Settings on Start menu " + widget.id);
    });
});
