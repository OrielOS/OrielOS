// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// The page the menu opens on: the pinned apps and the recommendations.
ColumnLayout {
    id: home

    required property MenuState menu

    readonly property Item allAppsButton: allAppsButton
    readonly property GridView pinnedView: pinned.view
    readonly property GridView recommendedView: recommended.view

    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            text: KI18n.i18nc("@title The pinned apps", "Pinned")
            textFormat: Text.PlainText
        }

        PC3.ToolButton {
            id: allAppsButton

            text: KI18n.i18nc("@action:button Show every app", "All apps")
            Accessible.name: text
            Accessible.role: Accessible.Button
            leftPadding: Kirigami.Units.largeSpacing
            rightPadding: Kirigami.Units.smallSpacing * 2

            // Sill's small pill button.
            background: Rectangle {
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
                               allAppsButton.hovered ? 0.14 : 0.08)
                border.width: allAppsButton.visualFocus ? 2 : 0
                border.color: Kirigami.Theme.highlightColor
            }

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    text: allAppsButton.text
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                }

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: "go-next"
                }
            }

            onClicked: home.menu.showAllApps()
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            Keys.onTabPressed: home.menu.cycleFocus(true)
            Keys.onBacktabPressed: home.menu.cycleFocus(false)
        }
    }

    PinnedGrid {
        id: pinned

        Layout.fillWidth: true
        Layout.preferredHeight: tileHeight * home.menu.pinnedRows
        menu: home.menu
    }

    PlasmaExtras.Heading {
        Layout.fillWidth: true
        level: 4
        text: KI18n.i18nc("@title Recently installed apps and recently opened files", "Recommended")
        textFormat: Text.PlainText
    }

    RecommendedList {
        id: recommended

        Layout.fillWidth: true
        Layout.fillHeight: true
        menu: home.menu
    }
}
