// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// A pinned app: its icon with its name underneath. A folder of pins shows up to four of its apps'
// icons in a rounded square instead.
PC3.ItemDelegate {
    id: tile

    required property string label
    required property var iconSource
    // Whether the tile is the keyboard's current item.
    property bool current: false
    // A folder's apps' icons, or empty for an app.
    property var folderIcons: []
    // Whether something dragged over the tile would make or join a folder.
    property bool dropTarget: false

    // Right-click, at (x, y) in the tile's coordinates.
    signal contextMenuRequested(real x, real y)

    text: label
    highlighted: current || dropTarget
    hoverEnabled: true
    // The grid holds the keyboard focus and tracks its current tile itself.
    focusPolicy: Qt.NoFocus

    Accessible.name: label
    Accessible.role: Accessible.Button

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        // Sill: a 38 px icon over a 12 px name.
        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            visible: tile.folderIcons.length === 0
            source: tile.iconSource
            active: tile.hovered
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            visible: tile.folderIcons.length > 0
            radius: 6
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 2

                Repeater {
                    model: tile.folderIcons.slice(0, 4)

                    delegate: Kirigami.Icon {
                        required property var modelData

                        width: 15
                        height: 15
                        source: modelData
                    }
                }
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: tile.label
            textFormat: Text.PlainText
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint, button) => tile.contextMenuRequested(eventPoint.position.x, eventPoint.position.y)
    }
}
