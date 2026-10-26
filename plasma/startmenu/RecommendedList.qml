// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// Newly installed apps, recent files and the Get started suggestions, in two columns.
Item {
    id: recommended

    required property MenuState menu

    readonly property GridView view: grid
    readonly property int columns: 2

    GridView {
        id: grid

        anchors.fill: parent
        clip: true
        interactive: false
        model: recommended.menu.recommendedItems
        cellWidth: Math.floor(width / recommended.columns)
        cellHeight: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing * 2 + Kirigami.Units.smallSpacing
        keyNavigationEnabled: false
        currentIndex: 0

        Accessible.name: KI18n.i18nc("@title Recently installed apps and recently opened files", "Recommended")
        Accessible.role: Accessible.List

        function openMenuForCurrent() {
            const current = grid.currentItem;
            if (current && grid.currentIndex >= 0) {
                recommended.menu.openRecommendedMenu(recommended.menu.recommendedItems[grid.currentIndex], current, current.width / 2, current.height / 2, true);
            }
        }

        delegate: ListRow {
            id: row

            required property int index
            required property var modelData

            width: grid.cellWidth
            height: grid.cellHeight
            label: String(row.modelData.display ?? "")
            iconSource: row.modelData.decoration ?? ""
            fallbackIcon: row.modelData.store ? "plasmadiscover" : "unknown"
            subtitle: String(row.modelData.subtitle ?? "")
            current: GridView.isCurrentItem && grid.activeFocus

            onClicked: recommended.menu.launchRecommended(row.modelData)
            onContextMenuRequested: (x, y) => recommended.menu.openRecommendedMenu(row.modelData, row, x, y, false)
        }

        Keys.onTabPressed: recommended.menu.cycleFocus(true)
        Keys.onBacktabPressed: recommended.menu.cycleFocus(false)
        Keys.onPressed: event => {
            if (recommended.menu.isContextMenuKey(event)) {
                grid.openMenuForCurrent();
                event.accepted = true;
                return;
            }
            const count = grid.count;
            const index = grid.currentIndex;
            const columns = recommended.columns;
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
                if (index >= columns) {
                    grid.currentIndex = index - columns;
                } else {
                    recommended.menu.focusPinned();
                }
                event.accepted = true;
                break;
            case Qt.Key_Down:
                if (index + columns < count) {
                    grid.currentIndex = index + columns;
                } else if (Math.floor(index / columns) < Math.floor((count - 1) / columns)) {
                    grid.currentIndex = count - 1;
                }
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (index >= 0) {
                    recommended.menu.launchRecommended(recommended.menu.recommendedItems[index]);
                }
                event.accepted = true;
                break;
            }
        }
    }

    PC3.Label {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: grid.count === 0
        text: {
            const menu = recommended.menu;
            if (!menu.showRecentlyAdded && !menu.showRecentFiles) {
                return KI18n.i18nc("@info:status", "To see new apps and recent files here, turn them on in Settings, Personalisation, Start.");
            }
            if (!menu.showRecentFiles) {
                return KI18n.i18nc("@info:status", "Apps you install will appear here.");
            }
            if (!menu.showRecentlyAdded) {
                return KI18n.i18nc("@info:status", "Files you open will appear here.");
            }
            return KI18n.i18nc("@info:status", "Apps you install and files you open will appear here.");
        }
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.75
    }
}
