// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// The search results, under headings for their kind. The keyboard focus usually stays in the
// search field, which moves the highlighted result.
Item {
    id: results

    required property MenuState menu

    readonly property ListView view: list
    // Whether the highlight was moved by hand. Until it is, it stays on the first result while
    // more results arrive.
    property bool moved: false

    function resetCurrent() {
        results.moved = false;
        list.currentIndex = list.count > 0 ? 0 : -1;
        list.positionViewAtBeginning();
    }

    function moveCurrent(step: int) {
        if (list.count === 0) {
            return;
        }
        results.moved = true;
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + step));
    }

    function triggerCurrent() {
        if (list.count > 0) {
            results.menu.launchResult(Math.max(0, list.currentIndex));
        }
    }

    function openCurrentMenu() {
        const current = list.currentItem as ListRow;
        if (current && current.entry) {
            results.menu.openResultMenu(list.currentIndex, String(current.entry.favoriteId ?? ""), current.entry.actionList,
                                        current, current.width / 2, current.height / 2, true);
        }
    }

    PC3.ScrollView {
        anchors.fill: parent

        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

        ListView {
            id: list

            clip: true
            model: results.menu.resultsModel
            keyNavigationEnabled: false
            highlightMoveDuration: 0

            Accessible.name: KI18n.i18nc("@title", "Search results")
            Accessible.role: Accessible.List

            onCountChanged: {
                if (!results.moved || list.currentIndex < 0) {
                    list.currentIndex = list.count > 0 ? 0 : -1;
                }
            }

            section.property: "group"
            section.delegate: PlasmaExtras.ListSectionHeader {
                required property string section

                width: list.width
                text: section
            }

            delegate: ListRow {
                id: row

                required property int index
                required property var model

                width: list.width
                label: String(row.model.display ?? "")
                iconSource: row.model.decoration ?? ""
                subtitle: String(row.model.description ?? "")
                entry: row.model
                current: ListView.isCurrentItem

                onHoveredChanged: {
                    if (row.hovered) {
                        results.moved = true;
                        list.currentIndex = row.index;
                    }
                }
                onClicked: results.menu.launchResult(row.index)
                onContextMenuRequested: (x, y) => results.menu.openResultMenu(row.index, String(row.model.favoriteId ?? ""), row.model.actionList, row, x, y, false)
            }

            Keys.onPressed: event => {
                if (results.menu.isContextMenuKey(event)) {
                    results.openCurrentMenu();
                    event.accepted = true;
                    return;
                }
                switch (event.key) {
                case Qt.Key_Up:
                    if (list.currentIndex > 0) {
                        results.moveCurrent(-1);
                    } else {
                        results.menu.focusSearch();
                    }
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    results.moveCurrent(1);
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    results.triggerCurrent();
                    event.accepted = true;
                    break;
                }
            }
        }
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: list.count === 0 && !results.menu.runnerModel.querying
        iconName: "edit-none"
        text: KI18n.i18nc("@info:status %1 is what was searched for", "No results for “%1”", results.menu.query)
    }
}
