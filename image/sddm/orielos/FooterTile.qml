/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// A tile in the lock screen's bottom-left corner: an account (its picture and name) or an action
// such as Switch user (an icon and a label). The current account's tile is highlighted.

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

T.AbstractButton {
    id: tile

    property string avatarSource
    property string iconName
    property bool current: false

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 10, row.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Kirigami.Units.gridUnit * 3
    leftPadding: Kirigami.Units.smallSpacing * 2
    rightPadding: Kirigami.Units.gridUnit
    focusPolicy: Qt.TabFocus
    hoverEnabled: !current
    Accessible.name: text

    background: Rectangle {
        radius: 6
        color: tile.current ? Qt.rgba(1, 1, 1, 0.12) : (tile.hovered || tile.visualFocus ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
        border.width: tile.current || tile.visualFocus ? 1 : 0
        border.color: tile.visualFocus ? "#9CC2FF" : Qt.rgba(1, 1, 1, 0.14)
    }

    contentItem: RowLayout {
        id: row
        spacing: Kirigami.Units.smallSpacing * 3

        AccountPicture {
            visible: tile.iconName === ""
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            source: tile.avatarSource
            name: tile.text
        }
        Kirigami.Icon {
            visible: tile.iconName !== ""
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            source: tile.iconName
        }
        PlasmaComponents3.Label {
            text: tile.text
            textFormat: Text.PlainText
            font.pixelSize: 13
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
