// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// A row in one of Quick Settings' sub-pages: an icon, a name and a status line. Clicking it
// selects it, and a selected row opens to show what it holds (buttons, a password box). A row
// that is `current` (the network in use, the output playing) is marked with the highlight colour.
T.AbstractButton {
    id: row

    property string iconName
    property string status
    property bool selected: false
    property bool current: false
    property bool busy: false
    // What a selected row shows under its name.
    default property alias expandedContent: expanded.data

    implicitWidth: 300
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    padding: 10
    leftPadding: 12
    focusPolicy: Qt.TabFocus
    Accessible.role: Accessible.ListItem
    Accessible.name: text
    Accessible.description: status
    Accessible.selected: selected

    background: Rectangle {
        radius: 6
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
            row.selected ? 0.08 : (row.hovered ? 0.06 : 0))
        border.width: row.visualFocus ? 2 : 0
        border.color: Kirigami.Theme.focusColor

        // The mark beside the row in use, as Windows marks the network it's connected to.
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 16
            radius: 1.5
            visible: row.current
            color: Kirigami.Theme.highlightColor
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Kirigami.Icon {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignTop
                source: row.iconName
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PC3.Label {
                    Layout.fillWidth: true
                    text: row.text
                    textFormat: Text.PlainText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                PC3.Label {
                    Layout.fillWidth: true
                    visible: row.status.length > 0
                    text: row.status
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }

            PC3.BusyIndicator {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                visible: row.busy
                running: row.busy
            }
        }

        ColumnLayout {
            id: expanded

            Layout.fillWidth: true
            Layout.leftMargin: 20 + 12
            visible: row.selected && children.length > 0
            spacing: 8
        }
    }
}
