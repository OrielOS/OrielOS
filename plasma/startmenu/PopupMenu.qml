// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.plasma.components as PC3

// A menu whose entries are built each time it opens, from a list of plain objects:
//   { text, icon, enabled, handler }   an item that calls handler() when chosen
//   ..., pin: { pinned, handler }      the same, with a pin button at its end, as for a file in a
//                                      jump list: shown while the item is hovered or highlighted, or
//                                      always once pinned; pressing it calls pin.handler()
//   { title: true, text }              a heading
//   { separator: true }                a separator
// The context menus' entries depend on the item they open for, so they can't be declared.
PC3.Menu {
    id: root

    property bool openedFromKeyboard: false
    // Whether the pointer has moved since the menu opened. A menu opened from the keyboard often
    // opens under a resting pointer, and hovering would move the highlight off the first item,
    // so until the pointer moves its items ignore it.
    property bool pointerMoved: true
    property point pointerStart: Qt.point(0, 0)
    property bool pointerStartKnown: false
    // The item that had the keyboard focus when the menu opened. It gets it back on closing.
    property Item focusOwner: null
    // True from closing until the event loop's next turn, so a button that toggles the menu can
    // tell that the press which closed the menu was on the button.
    property bool justClosed: false
    property var createdObjects: []

    // The item that had the focus when the menu opened is gone or hidden now.
    signal focusOwnerLost

    // Highlights the first item that can be chosen, so Enter chooses it straight away.
    function highlightFirst() {
        if (!root.visible || root.pointerMoved) {
            return;
        }
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

    // Called with the pointer's scene position each time it's seen over an item.
    function notePointer(position: point) {
        if (root.pointerMoved) {
            return;
        }
        if (!root.pointerStartKnown) {
            root.pointerStart = position;
            root.pointerStartKnown = true;
        } else if (Math.abs(position.x - root.pointerStart.x) > 1 || Math.abs(position.y - root.pointerStart.y) > 1) {
            root.pointerMoved = true;
        }
    }

    function returnFocus() {
        if (root.visible) {
            return;
        }
        const owner = root.focusOwner;
        if (owner && owner.visible && owner.enabled) {
            if (!owner.activeFocus) {
                owner.forceActiveFocus(Qt.PopupFocusReason);
            }
        } else {
            root.focusOwnerLost();
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
                pin: entry.pin ?? null,
            });
        }
        if (object) {
            root.createdObjects.push(object);
            root.addItem(object);
        }
    }

    // Replaces the entries; false when there are none to show.
    function setEntries(entries, parentItem: Item): bool {
        // Opening again while open keeps the item that had the focus before the first opening.
        if (!root.visible) {
            root.focusOwner = parentItem.Window.activeFocusItem;
        }
        root.close();
        root.clearEntries();
        for (const entry of entries) {
            root.addEntry(entry);
        }
        return root.count > 0;
    }

    function openAt(parentItem: Item, x: real, y: real, fromKeyboard: bool) {
        root.openedFromKeyboard = fromKeyboard;
        root.pointerMoved = !fromKeyboard;
        root.pointerStartKnown = false;
        root.popup(parentItem, x, y);
        if (fromKeyboard) {
            root.highlightFirst();
            // As it shows, the menu may still move the highlight to the item under the pointer.
            Qt.callLater(root.highlightFirst);
        }
    }

    // Opens the menu at (x, y) in parentItem's coordinates.
    function show(entries, parentItem: Item, x: real, y: real, fromKeyboard: bool) {
        if (root.setEntries(entries, parentItem)) {
            root.openAt(parentItem, x, y, fromKeyboard);
        }
    }

    // Opens the menu above parentItem, as for a button at the bottom of the popup.
    function showAbove(entries, parentItem: Item, fromKeyboard: bool) {
        if (!root.setEntries(entries, parentItem)) {
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
            Qt.callLater(root.highlightFirst);
        }
    }

    onClosed: {
        root.justClosed = true;
        Qt.callLater(() => {
            root.justClosed = false;
        });
        root.returnFocus();
        // Qt hands the focus to the window's content as the menu finishes closing.
        Qt.callLater(root.returnFocus);
    }

    Component {
        id: itemComponent

        PC3.MenuItem {
            id: menuItem

            property string iconName: ""
            property bool heading: false
            property var handler: null
            property var pin: null

            icon.name: iconName
            rightPadding: menuItem.pin ? pinButton.width + 8 : 0
            font.bold: heading
            hoverEnabled: root.pointerMoved

            onTriggered: {
                if (menuItem.handler) {
                    menuItem.handler();
                }
            }
            Keys.onReturnPressed: menuItem.click()
            Keys.onEnterPressed: menuItem.click()

            PC3.ToolButton {
                id: pinButton

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: menuItem.pin !== null && (menuItem.pin.pinned || menuItem.hovered || menuItem.highlighted)
                display: PC3.AbstractButton.IconOnly
                icon.name: menuItem.pin && menuItem.pin.pinned ? "window-unpin" : "window-pin"
                text: menuItem.pin && menuItem.pin.pinned
                    ? KI18n.i18nc("@action:button A file in a jump list", "Unpin from this list")
                    : KI18n.i18nc("@action:button A file in a jump list", "Pin to this list")
                focusPolicy: Qt.NoFocus
                PC3.ToolTip.text: pinButton.text
                PC3.ToolTip.visible: pinButton.hovered
                onClicked: {
                    menuItem.pin.handler();
                    root.close();
                }
            }

            // Sees the pointer even while the item ignores hovering.
            HoverHandler {
                id: pointerWatch

                enabled: !root.pointerMoved
                onPointChanged: {
                    if (pointerWatch.hovered) {
                        root.notePointer(pointerWatch.point.scenePosition);
                    }
                }
            }
        }
    }

    Component {
        id: separatorComponent

        PC3.MenuSeparator {}
    }
}
