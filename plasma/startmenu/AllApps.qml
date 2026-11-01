// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// Every app, as a list under letter headings, a grid, or by category, as Windows' View menu
// chooses. Clicking a letter heading shows every letter, as Windows does, to jump straight to that
// part of the list.
ColumnLayout {
    id: allApps

    required property MenuState menu

    readonly property Item backButton: backButton
    readonly property Item viewButton: viewButton
    // The view the keyboard moves in, for the view chosen: a ListView or a GridView.
    readonly property var view: allApps.menu.allAppsView === "grid" ? grid : (allApps.menu.allAppsView === "category" ? categories.keyboardView : list)
    readonly property bool mirrored: Application.layoutDirection === Qt.RightToLeft
    // Whether the letters to jump to show over the list.
    property bool choosingLetter: false
    // The first row of each letter's apps, by letter, while the letters show.
    property var firstRows: ({})

    function showLetters() {
        const rows = {};
        for (let row = 0; row < list.count; ++row) {
            const letter = String(allApps.menu.allAppsData(row, "group") ?? "").charAt(0).toUpperCase();
            if (letter.length > 0 && !(letter in rows)) {
                rows[letter] = row;
            }
        }
        allApps.firstRows = rows;
        allApps.choosingLetter = true;
    }

    // Back to the start of the view, as each time All apps opens.
    function reset() {
        allApps.choosingLetter = false;
        categories.reset();
    }

    function chooseView() {
        const current = allApps.menu.allAppsView;
        const entry = (id, text) => ({
            text: text,
            icon: current === id ? "checkmark" : "",
            handler: () => {
                allApps.menu.setAllAppsView(id);
                allApps.reset();
            },
        });
        allApps.menu.contextMenu.show([
            entry("category", KI18n.i18nc("@action:inmenu All apps grouped by category", "Category")),
            entry("grid", KI18n.i18nc("@action:inmenu All apps as a grid of icons", "Grid")),
            entry("list", KI18n.i18nc("@action:inmenu All apps as a list by letter", "List")),
        ], viewButton, 0, viewButton.height, viewButton.activeFocus);
    }

    function jumpTo(letter: string) {
        const row = allApps.firstRows[letter];
        allApps.choosingLetter = false;
        if (row !== undefined) {
            list.currentIndex = row;
            list.positionViewAtIndex(row, ListView.Beginning);
            list.forceActiveFocus();
        }
    }

    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            font.weight: Font.DemiBold
            text: KI18n.i18nc("@title Every app", "All apps")
            textFormat: Text.PlainText
        }

        PillButton {
            id: viewButton

            dropDown: true
            text: {
                switch (allApps.menu.allAppsView) {
                case "category":
                    return KI18n.i18nc("@action:button %1 is how All apps lists the apps", "View: %1", KI18n.i18nc("@action:inmenu All apps grouped by category", "Category"));
                case "grid":
                    return KI18n.i18nc("@action:button %1 is how All apps lists the apps", "View: %1", KI18n.i18nc("@action:inmenu All apps as a grid of icons", "Grid"));
                }
                return KI18n.i18nc("@action:button %1 is how All apps lists the apps", "View: %1", KI18n.i18nc("@action:inmenu All apps as a list by letter", "List"));
            }

            onClicked: allApps.chooseView()
            Keys.onTabPressed: allApps.menu.cycleFocus(true)
            Keys.onBacktabPressed: allApps.menu.cycleFocus(false)
        }

        PillButton {
            id: backButton

            back: true
            text: KI18n.i18nc("@action:button Go back to the pinned apps", "Back")

            onClicked: allApps.menu.showHome()
            Keys.onTabPressed: allApps.menu.cycleFocus(true)
            Keys.onBacktabPressed: allApps.menu.cycleFocus(false)
        }
    }

    PC3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: allApps.menu.allAppsView === "list" && !allApps.choosingLetter

        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

        ListView {
            id: list

            clip: true
            model: allApps.menu.allAppsModel
            keyNavigationEnabled: false
            currentIndex: 0

            Accessible.name: KI18n.i18nc("@title Every app", "All apps")
            Accessible.role: Accessible.List

            // The model's group is the name's first letter in upper case, transliterated where the
            // language needs it, or "#" for a digit and "&" for a symbol, as in Kickoff.
            section.property: "group"
            section.criteria: ViewSection.FirstCharacter
            // The header lays out its own children, so the click area sits beside it, not in it.
            section.delegate: Item {
                id: sectionItem

                required property string section

                width: list.width
                height: header.implicitHeight

                PlasmaExtras.ListSectionHeader {
                    id: header

                    width: parent.width
                    text: sectionItem.section.toUpperCase()
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    Accessible.role: Accessible.Button
                    Accessible.name: KI18n.i18nc("@action:button", "Jump to a letter")
                    onClicked: allApps.showLetters()
                }
            }

            function openMenuForCurrent() {
                const current = list.currentItem;
                if (current && list.currentIndex >= 0) {
                    allApps.menu.openAppMenu(list.currentIndex, current, current.width / 2, current.height / 2, true);
                }
            }

            delegate: ListRow {
                id: row

                required property int index
                required property var model

                width: list.width
                label: String(row.model.display ?? "")
                iconSource: row.model.decoration ?? ""
                subtitle: row.model.isNewlyInstalled ? KI18n.i18nc("@info:status An app installed in the last few days", "Recently added") : ""
                current: ListView.isCurrentItem && list.activeFocus

                onClicked: allApps.menu.launchApp(row.index)
                onContextMenuRequested: (x, y) => allApps.menu.openAppMenu(row.index, row, x, y, false)
            }

            Keys.onTabPressed: allApps.menu.cycleFocus(true)
            Keys.onBacktabPressed: allApps.menu.cycleFocus(false)
            Keys.onPressed: event => {
                if (allApps.choosingLetter && event.key === Qt.Key_Escape) {
                    allApps.choosingLetter = false;
                    event.accepted = true;
                    return;
                }
                if (allApps.menu.isContextMenuKey(event)) {
                    list.openMenuForCurrent();
                    event.accepted = true;
                    return;
                }
                switch (event.key) {
                case Qt.Key_Up:
                    if (list.currentIndex > 0) {
                        list.decrementCurrentIndex();
                    } else {
                        allApps.menu.focusSearch();
                    }
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    list.incrementCurrentIndex();
                    event.accepted = true;
                    break;
                case Qt.Key_PageUp:
                    list.currentIndex = Math.max(0, list.currentIndex - 10);
                    event.accepted = true;
                    break;
                case Qt.Key_PageDown:
                    list.currentIndex = Math.min(list.count - 1, list.currentIndex + 10);
                    event.accepted = true;
                    break;
                case Qt.Key_Home:
                    list.currentIndex = 0;
                    event.accepted = true;
                    break;
                case Qt.Key_End:
                    list.currentIndex = list.count - 1;
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    if (list.currentIndex >= 0) {
                        allApps.menu.launchApp(list.currentIndex);
                    }
                    event.accepted = true;
                    break;
                }
            }
        }
    }

    PC3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: allApps.menu.allAppsView === "grid"

        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

        GridView {
            id: grid

            readonly property int columns: allApps.menu.pinnedColumns

            clip: true
            model: allApps.menu.allAppsModel
            // Pinned's tile: room for a 38 px icon and two lines of the app's name.
            cellWidth: Math.floor(width / columns)
            cellHeight: 84 + Kirigami.Units.smallSpacing
            keyNavigationEnabled: false
            currentIndex: 0

            Accessible.name: KI18n.i18nc("@title Every app", "All apps")
            Accessible.role: Accessible.List

            delegate: AppTile {
                id: tile

                required property int index
                required property var model

                width: grid.cellWidth
                height: grid.cellHeight
                label: String(tile.model.display ?? "")
                iconSource: tile.model.decoration ?? ""
                current: GridView.isCurrentItem && grid.activeFocus

                onClicked: allApps.menu.launchApp(tile.index)
                onContextMenuRequested: (x, y) => allApps.menu.openAppMenu(tile.index, tile, x, y, false)
            }

            Keys.onTabPressed: allApps.menu.cycleFocus(true)
            Keys.onBacktabPressed: allApps.menu.cycleFocus(false)
            Keys.onPressed: event => {
                const index = grid.currentIndex;
                if (allApps.menu.isContextMenuKey(event)) {
                    if (grid.currentItem) {
                        allApps.menu.openAppMenu(index, grid.currentItem, grid.currentItem.width / 2, grid.currentItem.height / 2, true);
                    }
                    event.accepted = true;
                    return;
                }
                const count = grid.count;
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
                        allApps.menu.focusSearch();
                    }
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    grid.currentIndex = Math.min(count - 1, index + grid.columns);
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    if (index >= 0) {
                        allApps.menu.launchApp(index);
                    }
                    event.accepted = true;
                    break;
                }
            }
        }
    }

    CategoryView {
        id: categories

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: allApps.menu.allAppsView === "category"
        menu: allApps.menu
    }

    // The letters, over the list: those with apps can be clicked.
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: allApps.choosingLetter
        color: Kirigami.Theme.backgroundColor
        radius: 8

        Grid {
            anchors.centerIn: parent
            columns: 6
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: ["&", "#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]

                delegate: PC3.ToolButton {
                    required property string modelData

                    width: 44
                    height: 44
                    text: modelData
                    enabled: modelData in allApps.firstRows
                    font.pixelSize: 16
                    onClicked: allApps.jumpTo(modelData)
                }
            }
        }
    }
}
