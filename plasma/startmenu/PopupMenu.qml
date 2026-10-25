// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PC3

// A menu whose entries are built each time it opens, from a list of plain objects:
//   { text, icon, enabled, handler }   an item that calls handler() when chosen
//   { title: true, text }              a heading
//   { separator: true }                a separator
// The context menus' entries depend on the item they open for, so they can't be declared.
PC3.Menu {
    id: root

    property bool openedFromKeyboard: false
    property var createdObjects: []

    // Highlights the first item that can be chosen, so Enter chooses it straight away.
    function highlightFirst() {
        for (let i = 0; i < root.count; ++i) {
            const item = root.itemAt(i);
            if (item instanceof PC3.MenuItem && item.enabled) {
                root.currentIndex = i;
                // Enter is handled by the focused item.
                item.forceActiveFocus(Qt.TabFocusReason);
                return;
            }
        }
    }

    function clearEntries() {
        while (root.count > 0) {
            root.takeItem(0);
        }
        for (const object of root.createdObjects) {
            object.destroy();
        }
        root.createdObjects = [];
    }

    function addEntry(entry) {
        let object = null;
        if (entry.separator) {
            object = separatorComponent.createObject(root);
        } else {
            object = itemComponent.createObject(root, {
                text: entry.text ?? "",
                iconName: entry.icon ?? "",
                enabled: !entry.title && (entry.enabled ?? true),
                heading: entry.title ?? false,
                handler: entry.handler ?? null,
            });
        }
        if (object) {
            root.createdObjects.push(object);
            root.addItem(object);
        }
    }

    // Replaces the entries; false when there are none to show.
    function setEntries(entries): bool {
        root.close();
        root.clearEntries();
        for (const entry of entries) {
            root.addEntry(entry);
        }
        return root.count > 0;
    }

    function openAt(parentItem: Item, x: real, y: real, fromKeyboard: bool) {
        root.openedFromKeyboard = fromKeyboard;
        root.popup(parentItem, x, y);
        if (fromKeyboard) {
            root.highlightFirst();
        }
    }

    // Opens the menu at (x, y) in parentItem's coordinates.
    function show(entries, parentItem: Item, x: real, y: real, fromKeyboard: bool) {
        if (root.setEntries(entries)) {
            root.openAt(parentItem, x, y, fromKeyboard);
        }
    }

    // Opens the menu above parentItem, as for a button at the bottom of the popup.
    function showAbove(entries, parentItem: Item, fromKeyboard: bool) {
        if (!root.setEntries(entries)) {
            return;
        }
        // The menu lays itself out only once it shows, so add up its items' heights.
        let height = root.topPadding + root.bottomPadding;
        for (const object of root.createdObjects) {
            height += (object as Item).implicitHeight;
        }
        root.openAt(parentItem, 0, -height, fromKeyboard);
    }

    onOpened: {
        if (root.openedFromKeyboard) {
            root.highlightFirst();
        }
    }

    Component {
        id: itemComponent

        PC3.MenuItem {
            id: menuItem

            property string iconName: ""
            property bool heading: false
            property var handler: null

            icon.name: iconName
            font.bold: heading

            onTriggered: {
                if (menuItem.handler) {
                    menuItem.handler();
                }
            }
            Keys.onReturnPressed: menuItem.click()
            Keys.onEnterPressed: menuItem.click()
        }
    }

    Component {
        id: separatorComponent

        PC3.MenuSeparator {}
    }
}
