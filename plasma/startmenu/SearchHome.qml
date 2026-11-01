// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// What search shows before anything is typed, as Windows' does: the last few searches, which run
// again when chosen, and the most used apps.
ColumnLayout {
    id: home

    required property MenuState menu

    readonly property ListView recentView: recent
    readonly property GridView topAppsView: topApps
    // How many of the most used apps show, in one row.
    readonly property int topAppsShown: topApps.shown
    readonly property Item clearButton: clearButton

    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true
        visible: recent.count > 0

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            font.weight: Font.DemiBold
            text: KI18n.i18nc("@title Recent searches", "Recent")
            textFormat: Text.PlainText
        }

        PillButton {
            id: clearButton

            text: KI18n.i18nc("@action:button Forget the recent searches", "Clear")

            onClicked: {
                home.menu.clearSearches();
                home.menu.focusSearch();
            }
            Keys.onTabPressed: home.menu.cycleFocus(true)
            Keys.onBacktabPressed: home.menu.cycleFocus(false)
        }
    }

    ListView {
        id: recent

        // Sill's list rows, 44 px apart.
        readonly property int rowHeight: 44

        Layout.fillWidth: true
        Layout.preferredHeight: count * rowHeight
        visible: count > 0
        interactive: false
        model: home.menu.recentSearches
        keyNavigationEnabled: false
        currentIndex: 0

        Accessible.name: KI18n.i18nc("@title Recent searches", "Recent")
        Accessible.role: Accessible.List

        function openMenu(index: int, item: Item, x: real, y: real, fromKeyboard: bool) {
            const text = String(home.menu.recentSearches[index] ?? "");
            home.menu.contextMenu.show([
                {
                    text: KI18n.i18nc("@action:inmenu Forget one recent search", "Remove from history"),
                    icon: "edit-delete-remove",
                    handler: () => home.menu.forgetSearch(text),
                },
            ], item, x, y, fromKeyboard);
        }

        delegate: ListRow {
            id: row

            required property int index
            required property string modelData

            width: recent.width
            height: recent.rowHeight
            label: row.modelData
            iconSource: "document-open-recent"
            current: ListView.isCurrentItem && recent.activeFocus

            onClicked: home.menu.searchAgain(row.modelData)
            onContextMenuRequested: (x, y) => recent.openMenu(row.index, row, x, y, false)
        }

        Keys.onTabPressed: home.menu.cycleFocus(true)
        Keys.onBacktabPressed: home.menu.cycleFocus(false)
        Keys.onPressed: event => {
            const index = recent.currentIndex;
            if (home.menu.isContextMenuKey(event)) {
                if (recent.currentItem) {
                    recent.openMenu(index, recent.currentItem, recent.currentItem.width / 2, recent.currentItem.height / 2, true);
                }
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Up:
                if (index > 0) {
                    recent.currentIndex = index - 1;
                } else {
                    home.menu.focusSearch();
                }
                event.accepted = true;
                break;
            case Qt.Key_Down:
                if (index + 1 < recent.count) {
                    recent.currentIndex = index + 1;
                } else if (topApps.shown > 0) {
                    topApps.currentIndex = 0;
                    topApps.forceActiveFocus(Qt.TabFocusReason);
                }
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (index >= 0) {
                    home.menu.searchAgain(String(home.menu.recentSearches[index] ?? ""));
                }
                event.accepted = true;
                break;
            }
        }
    }

    PlasmaExtras.Heading {
        Layout.fillWidth: true
        visible: topApps.shown > 0
        level: 4
        font.weight: Font.DemiBold
        text: KI18n.i18nc("@title The most used apps", "Top apps")
        textFormat: Text.PlainText
    }

    GridView {
        id: topApps

        readonly property int columns: home.menu.pinnedColumns
        // One row of the most used apps; the model knows more.
        readonly property int shown: Math.min(count, columns)

        Layout.fillWidth: true
        // Pinned's tile: room for a 38 px icon and two lines of the app's name.
        Layout.preferredHeight: 84 + Kirigami.Units.smallSpacing
        visible: shown > 0
        clip: true
        interactive: false
        model: home.menu.topAppsModel
        cellWidth: Math.floor(width / columns)
        cellHeight: Layout.preferredHeight
        keyNavigationEnabled: false
        currentIndex: 0

        Accessible.name: KI18n.i18nc("@title The most used apps", "Top apps")
        Accessible.role: Accessible.List

        delegate: AppTile {
            id: tile

            required property int index
            required property var model

            width: topApps.cellWidth
            height: topApps.cellHeight
            visible: tile.index < topApps.columns
            label: String(tile.model.display ?? "")
            iconSource: tile.model.decoration ?? ""
            current: GridView.isCurrentItem && topApps.activeFocus

            onClicked: home.menu.launchTopApp(tile.index)
            onContextMenuRequested: (x, y) => home.menu.openTopAppMenu(tile.index, tile, x, y, false)
        }

        Keys.onTabPressed: home.menu.cycleFocus(true)
        Keys.onBacktabPressed: home.menu.cycleFocus(false)
        Keys.onPressed: event => {
            const index = topApps.currentIndex;
            if (home.menu.isContextMenuKey(event)) {
                if (topApps.currentItem) {
                    home.menu.openTopAppMenu(index, topApps.currentItem, topApps.currentItem.width / 2, topApps.currentItem.height / 2, true);
                }
                event.accepted = true;
                return;
            }
            const mirrored = topApps.effectiveLayoutDirection === Qt.RightToLeft;
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right: {
                const step = (event.key === Qt.Key_Right) !== mirrored ? 1 : -1;
                topApps.currentIndex = Math.max(0, Math.min(topApps.shown - 1, index + step));
                event.accepted = true;
                break;
            }
            case Qt.Key_Up:
                if (recent.count > 0) {
                    recent.currentIndex = recent.count - 1;
                    recent.forceActiveFocus(Qt.BacktabFocusReason);
                } else {
                    home.menu.focusSearch();
                }
                event.accepted = true;
                break;
            case Qt.Key_Down:
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (index >= 0) {
                    home.menu.launchTopApp(index);
                }
                event.accepted = true;
                break;
            }
        }
    }

    // Nothing searched or used yet.
    PC3.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit * 4
        visible: recent.count === 0 && topApps.shown === 0
        text: KI18n.i18nc("@info:status", "Type to search for apps, settings and files.")
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.75
    }

    Item {
        Layout.fillHeight: true
    }
}
