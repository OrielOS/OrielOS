// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The pinned apps, six to a row. It scrolls when there are more rows than fit.
PC3.ScrollView {
    id: pinned

    required property MenuState menu

    readonly property GridView view: grid
    // Sill's tile: room for a 38 px icon and two lines of the app's name.
    readonly property real tileHeight: 84 + Kirigami.Units.smallSpacing

    PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

    GridView {
        id: grid

        readonly property int columns: pinned.menu.pinnedColumns

        clip: true
        model: pinned.menu.favoritesModel
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
            required property var model

            width: grid.cellWidth
            height: grid.cellHeight
            label: String(tile.model.display ?? "")
            iconSource: tile.model.decoration ?? ""
            current: GridView.isCurrentItem && grid.activeFocus

            onClicked: pinned.menu.launchPinned(tile.index)
            onContextMenuRequested: (x, y) => pinned.menu.openPinnedMenu(tile.index, tile, x, y, false)
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
}
