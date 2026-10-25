// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// Every app, alphabetically, under letter headings.
ColumnLayout {
    id: allApps

    required property MenuState menu

    readonly property Item backButton: backButton
    readonly property ListView view: list
    readonly property bool mirrored: Application.layoutDirection === Qt.RightToLeft

    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            text: KI18n.i18nc("@title Every app", "All apps")
            textFormat: Text.PlainText
        }

        PC3.ToolButton {
            id: backButton

            text: KI18n.i18nc("@action:button Go back to the pinned apps", "Back")
            icon.name: allApps.mirrored ? "go-next" : "go-previous"
            Accessible.name: text
            Accessible.role: Accessible.Button

            onClicked: allApps.menu.showHome()
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            Keys.onTabPressed: allApps.menu.cycleFocus(true)
            Keys.onBacktabPressed: allApps.menu.cycleFocus(false)
        }
    }

    PC3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

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
            section.delegate: PlasmaExtras.ListSectionHeader {
                required property string section

                width: list.width
                text: section.toUpperCase()
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
}
