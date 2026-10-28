// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One of Quick Settings' tiles: an icon, a name and a short status. On, it is filled with the
// highlight colour; off, it is a faint outlined square. A tile with `hasDetails` has a separate
// strip on its right with a chevron, which opens the details (Wi-Fi networks, Bluetooth devices).
T.AbstractButton {
    id: tile

    property string iconName
    property string status
    property bool hasDetails: false

    signal detailsRequested()

    checkable: false
    Accessible.checkable: true
    Accessible.checked: checked
    implicitWidth: 107
    implicitHeight: 76
    focusPolicy: Qt.TabFocus
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.description: status

    readonly property color ink: checked ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor

    background: Rectangle {
        radius: 6
        color: tile.checked
            ? Qt.lighter(Kirigami.Theme.highlightColor, tile.hovered ? 1.12 : 1.0)
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, tile.hovered ? 0.10 : 0.06)
        border.width: tile.visualFocus ? 2 : (tile.checked ? 0 : 1)
        border.color: tile.visualFocus ? Kirigami.Theme.focusColor
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
    }

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            anchors.rightMargin: tile.hasDetails ? 28 + 8 : 12
            spacing: 2

            Kirigami.Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: tile.iconName
                color: tile.ink
                isMask: true
            }

            Item {
                Layout.fillHeight: true
            }

            PC3.Label {
                Layout.fillWidth: true
                text: tile.text
                textFormat: Text.PlainText
                color: tile.ink
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: tile.status.length > 0 ? 1 : 2
                wrapMode: Text.Wrap
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: tile.status.length > 0
                text: tile.status
                textFormat: Text.PlainText
                color: tile.ink
                opacity: 0.85
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        // The details strip: a line, then the chevron.
        MouseArea {
            id: details

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 28
            visible: tile.hasDetails
            hoverEnabled: true
            Accessible.role: Accessible.Button
            Accessible.name: i18nc("@action:button %1 is a setting such as Wi-Fi", "%1 details", tile.text)
            onClicked: tile.detailsRequested()

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 5
                color: tile.ink
                opacity: details.containsMouse ? 0.12 : 0
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height
                color: tile.ink
                opacity: 0.25
            }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 12
                height: 12
                source: "go-next"
                color: tile.ink
                isMask: true
            }
        }
    }
}
