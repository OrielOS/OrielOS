// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.plasma.extras as PlasmaExtras

// The hidden icons pane, as Sill draws it: only the apps' icons, five a row in 40 px cells 4 px
// apart, and the eject icon while a USB drive is plugged in. The arrow keys move through them.
// Dropping an app's icon here takes it off the taskbar.
FocusScope {
    id: pane

    // main.qml's root: the icons' details and what to do with them.
    required property var tray
    required property var ids
    required property var drives

    readonly property string ejectId: "org.orielos.tray.eject"
    // The popup's own padding, which the margin takes back.
    property real framePadding: 0
    readonly property int cell: 44
    // With the cells' 2 px inset, 8 px between the pane's edge and the cells, as in Sill; negative
    // when the popup's padding is wider than that.
    readonly property real margin: 6 - pane.framePadding
    readonly property int columns: Math.max(1, Math.min(5, grid.count))
    readonly property int rows: Math.max(1, Math.ceil(grid.count / 5))

    implicitWidth: pane.columns * pane.cell + 2 * pane.margin
    implicitHeight: pane.rows * pane.cell + 2 * pane.margin
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.maximumHeight: implicitHeight

    function openEjectMenu(item: Item) {
        ejectMenu.visualParent = item;
        ejectMenu.openRelative();
    }

    GridView {
        id: grid

        anchors.fill: parent
        anchors.margins: pane.margin
        cellWidth: pane.cell
        cellHeight: pane.cell
        interactive: false
        focus: true
        keyNavigationEnabled: true
        model: pane.drives.length > 0 ? pane.ids.concat([pane.ejectId]) : pane.ids

        Accessible.role: Accessible.List
        Accessible.name: KI18n.i18nc("@info:whatsthis", "Hidden icons")

        Keys.onPressed: event => event.accepted = grid.currentItem !== null && (grid.currentItem as TrayIcon).handleKey(event)

        delegate: TrayIcon {
            id: entry

            required property string modelData
            readonly property bool isEject: entry.modelData === pane.ejectId

            width: pane.cell
            height: pane.cell
            inset: 2
            iconSize: 20
            current: GridView.isCurrentItem && grid.activeFocus
            itemId: entry.modelData
            dragFormat: entry.isEject ? "" : pane.tray.dragFormat
            source: entry.isEject ? "media-eject" : pane.tray.iconOf(entry.modelData, pane.tray.revision)
            title: entry.isEject ? KI18n.i18nc("@info:tooltip", "Eject a drive") : pane.tray.titleOf(entry.modelData, pane.tray.revision)
            subTitle: entry.isEject ? pane.drives.map(drive => drive.name).join(", ") : pane.tray.subTitleOf(entry.modelData, pane.tray.revision)

            onDraggingChanged: pane.tray.paneDragging = entry.dragging
            onActivated: entry.isEject ? pane.openEjectMenu(entry) : pane.tray.activateItem(entry.modelData, entry)
            onMenuRequested: (x, y) => entry.isEject ? pane.openEjectMenu(entry) : pane.tray.openItemMenu(entry.modelData, entry, x, y)
            onMiddleClicked: if (!entry.isEject) pane.tray.middleClickItem(entry.modelData, entry)
            onScrolled: (delta, direction) => { if (!entry.isEject) pane.tray.scrollItem(entry.modelData, delta, direction) }
        }
    }

    DropArea {
        anchors.fill: parent
        keys: [pane.tray.dragFormat]
        onDropped: drop => {
            pane.tray.hideItem(drop.getDataAsString(pane.tray.dragFormat));
            drop.accept(Qt.MoveAction);
        }
    }

    PlasmaExtras.Menu {
        id: ejectMenu
        placement: PlasmaExtras.Menu.TopPosedLeftAlignedPopup
    }

    Instantiator {
        model: pane.drives
        delegate: PlasmaExtras.MenuItem {
            required property var modelData
            text: KI18n.i18nc("@action:inmenu %1 is a drive's name", "Eject %1", modelData.name)
            icon: "media-eject"
            onClicked: pane.tray.ejectDrive(modelData.udi)
        }
        onObjectAdded: (index, object) => ejectMenu.addMenuItem(object as PlasmaExtras.MenuItem)
        onObjectRemoved: (index, object) => ejectMenu.removeMenuItem(object as PlasmaExtras.MenuItem)
    }
}
