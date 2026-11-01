// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami

// The pinned apps, six to a row, in pages of a few rows: the wheel and the keyboard turn the pages,
// and Sill's dots at the side show which page is showing and turn to the one clicked. Dragging a
// pin moves it; dropping it on another makes a folder, as in Windows, and a folder opens in place
// over the pins.
Item {
    id: pinned

    required property MenuState menu

    readonly property GridView view: grid
    // Sill's tile: room for a 38 px icon and two lines of the app's name.
    readonly property real tileHeight: 84 + Kirigami.Units.smallSpacing
    readonly property int rowsPerPage: menu.pinnedRows
    readonly property int pageCount: Math.max(1, Math.ceil(Math.ceil(grid.count / grid.columns) / rowsPerPage))
    property int page: 0

    // While a pin is dragged: its index, where it would land (an index to go before, or the tile
    // it would join with combine), and where the pointer is, in the grid's coordinates.
    property int dragIndex: -1
    property int dropIndex: -1
    property bool combine: false
    property point dragPoint: Qt.point(0, 0)

    // Where a drop at this point in the grid would land.
    function dragTo(point: point) {
        pinned.dragPoint = point;
        const x = point.x;
        const y = point.y + grid.contentY;
        const index = grid.indexAt(x, y);
        if (index < 0) {
            const inside = point.x >= 0 && point.x < grid.width && point.y >= 0 && point.y < grid.height;
            pinned.dropIndex = inside ? grid.count : -1;
            pinned.combine = false;
            return;
        }
        const fraction = (x - (index % grid.columns) * grid.cellWidth) / grid.cellWidth;
        const dragged = pinned.menu.pinnedEntries[pinned.dragIndex];
        pinned.combine = index !== pinned.dragIndex && fraction > 0.25 && fraction < 0.75 && !!dragged && !dragged.folder;
        pinned.dropIndex = pinned.combine ? index : (fraction >= 0.5 ? index + 1 : index);
    }

    function drop() {
        const from = pinned.dragIndex;
        const to = pinned.dropIndex;
        const combine = pinned.combine;
        pinned.dragIndex = -1;
        pinned.dropIndex = -1;
        pinned.combine = false;
        if (from < 0 || to < 0) {
            return;
        }
        if (combine) {
            pinned.menu.combinePinned(from, to);
        } else if (to !== from && to !== from + 1) {
            pinned.menu.movePinned(from, to);
        }
    }

    // Turns to a page. The grid moves itself to show its current tile too, so the page is set
    // rather than bound, and always holds the current tile.
    function showPage(newPage: int) {
        pinned.page = Math.max(0, Math.min(pinned.pageCount - 1, newPage));
        turn.to = pinned.page * pinned.rowsPerPage * pinned.tileHeight;
        turn.restart();
    }

    NumberAnimation {
        id: turn
        target: grid
        property: "contentY"
        duration: Kirigami.Units.longDuration
        easing.type: Easing.OutCubic
    }

    // Wheel steps add up until they make a page, so a touchpad doesn't race through them.
    property real wheelSum: 0

    onPageCountChanged: pinned.showPage(pinned.page)

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            pinned.wheelSum += event.angleDelta.y;
            if (Math.abs(pinned.wheelSum) >= 120) {
                pinned.showPage(pinned.page + (pinned.wheelSum < 0 ? 1 : -1));
                pinned.wheelSum = 0;
            }
        }
    }

    // Sill's page dots, beside the grid, while there's more than one page.
    Column {
        id: dots

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.smallSpacing
        visible: pinned.pageCount > 1

        Repeater {
            model: pinned.pageCount

            delegate: MouseArea {
                id: dot

                required property int index

                width: 12
                height: dot.index === pinned.page ? 18 : 10
                Accessible.role: Accessible.Button
                Accessible.name: KI18n.i18nc("@action:button %1 is a page number", "Page %1", dot.index + 1)
                onClicked: pinned.showPage(dot.index)

                Rectangle {
                    anchors.centerIn: parent
                    width: dot.index === pinned.page ? 4 : 5
                    height: dot.index === pinned.page ? 14 : 5
                    radius: width / 2
                    color: Kirigami.Theme.textColor
                    opacity: dot.index === pinned.page ? 1 : 0.45
                }
            }
        }
    }

    GridView {
        id: grid

        readonly property int columns: pinned.menu.pinnedColumns

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: dots.visible ? dots.left : parent.right
        clip: true
        interactive: false
        // An open folder lies over the pins, which then take no clicks.
        enabled: pinned.menu.openFolder.length === 0
        // The keyboard's current tile is always on the page showing.
        onCurrentIndexChanged: {
            if (grid.currentIndex >= 0) {
                pinned.showPage(Math.floor(grid.currentIndex / grid.columns / pinned.rowsPerPage));
            }
        }
        model: pinned.menu.pinnedEntries
        cellWidth: Math.floor(width / columns)
        cellHeight: pinned.tileHeight
        keyNavigationEnabled: false
        currentIndex: 0

        Accessible.name: KI18n.i18nc("@title The pinned apps", "Pinned")
        Accessible.role: Accessible.List

        function openMenuForCurrent() {
            const current = grid.currentItem;
            if (current) {
                pinned.menu.openPinnedMenu(grid.currentIndex, current, current.width / 2, current.height / 2, true);
            }
        }

        delegate: AppTile {
            id: tile

            required property int index
            required property var modelData

            width: grid.cellWidth
            height: grid.cellHeight
            label: tile.modelData.folder ? tile.modelData.name : String(pinned.menu.favoritesData(tile.modelData.row, "display") ?? "")
            iconSource: tile.modelData.folder ? "" : pinned.menu.favoritesData(tile.modelData.row, "decoration") ?? ""
            folderIcons: tile.modelData.folder
                ? tile.modelData.apps.map(app => pinned.menu.folderAppsModel.data(pinned.menu.folderAppsModel.index(app.row, 0), Qt.DecorationRole) ?? "")
                : []
            current: GridView.isCurrentItem && grid.activeFocus
            dropTarget: pinned.combine && pinned.dropIndex === tile.index
            opacity: pinned.dragIndex === tile.index ? 0.4 : 1

            onClicked: pinned.menu.launchPinned(tile.index)
            onContextMenuRequested: (x, y) => pinned.menu.openPinnedMenu(tile.index, tile, x, y, false)

            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton
                // An open folder lies over the pins.
                enabled: pinned.menu.openFolder.length === 0
                onActiveChanged: {
                    if (active) {
                        pinned.dragIndex = tile.index;
                    } else {
                        pinned.drop();
                    }
                }
                onCentroidChanged: {
                    if (active) {
                        pinned.dragTo(grid.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y));
                    }
                }
            }
        }

        Keys.onTabPressed: pinned.menu.cycleFocus(true)
        Keys.onBacktabPressed: pinned.menu.cycleFocus(false)
        Keys.onPressed: event => {
            if (pinned.menu.isContextMenuKey(event)) {
                grid.openMenuForCurrent();
                event.accepted = true;
                return;
            }
            const count = grid.count;
            const index = grid.currentIndex;
            const mirrored = grid.effectiveLayoutDirection === Qt.RightToLeft;
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right: {
                const step = (event.key === Qt.Key_Right) !== mirrored ? 1 : -1;
                grid.currentIndex = Math.max(0, Math.min(count - 1, index + step));
                event.accepted = true;
                break;
            }
            case Qt.Key_Up:
                if (index >= grid.columns) {
                    grid.currentIndex = index - grid.columns;
                } else {
                    pinned.menu.focusSearch();
                }
                event.accepted = true;
                break;
            case Qt.Key_Down:
                if (index + grid.columns < count) {
                    grid.currentIndex = index + grid.columns;
                } else if (Math.floor(index / grid.columns) < Math.floor((count - 1) / grid.columns)) {
                    // The row below is shorter than this one.
                    grid.currentIndex = count - 1;
                } else {
                    pinned.menu.focusRecommended();
                }
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (index >= 0) {
                    pinned.menu.launchPinned(index);
                }
                event.accepted = true;
                break;
            }
        }
    }

    // Where a dragged pin would go between two others.
    Rectangle {
        readonly property int column: pinned.dropIndex % grid.columns
        readonly property int row: Math.floor(pinned.dropIndex / grid.columns)

        x: grid.x + column * grid.cellWidth - width / 2
        y: grid.y + row * grid.cellHeight - grid.contentY + grid.cellHeight * 0.15
        width: 3
        height: grid.cellHeight * 0.7
        radius: width / 2
        visible: pinned.dragIndex >= 0 && pinned.dropIndex >= 0 && !pinned.combine
        color: Kirigami.Theme.highlightColor
    }

    // The dragged pin's icon, under the pointer.
    Kirigami.Icon {
        readonly property var entry: pinned.menu.pinnedEntries[pinned.dragIndex] ?? null

        x: grid.x + pinned.dragPoint.x - width / 2
        y: grid.y + pinned.dragPoint.y - height / 2
        width: 38
        height: 38
        visible: pinned.dragIndex >= 0 && !!entry
        opacity: 0.85
        source: entry && !entry.folder ? pinned.menu.favoritesData(entry.row, "decoration") ?? "" : "folder"
    }

    // With one row of pins, the folder grows over Recommended to fit its name and a row of apps.
    PinFolder {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(parent.height, Kirigami.Units.gridUnit * 2.5 + pinned.tileHeight)
        z: 1
        menu: pinned.menu
    }
}
