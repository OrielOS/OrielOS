// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One row of a list: an icon, a name and an optional second line.
PC3.ItemDelegate {
    id: row

    required property string label
    required property var iconSource
    // The theme icon shown when iconSource can't be loaded.
    property string fallbackIcon: "unknown"
    property string subtitle: ""
    // Whether the row is the keyboard's current item.
    property bool current: false

    // Right-click, at (x, y) in the row's coordinates.
    signal contextMenuRequested(real x, real y)

    text: label
    highlighted: current
    hoverEnabled: true
    // The list holds the keyboard focus and tracks its current row itself.
    focusPolicy: Qt.NoFocus

    Accessible.name: subtitle.length > 0 ? label + ", " + subtitle : label
    Accessible.role: Accessible.ListItem

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        Item {
            id: iconBox

            // A picture file, such as a Store app's icon from Flathub's catalogue, shows once it has
            // loaded. Kirigami.Icon draws nothing for a file that isn't there, not its fallback.
            readonly property bool isFile: typeof row.iconSource === "string" && row.iconSource.startsWith("file:")

            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium

            Image {
                id: picture

                anchors.fill: parent
                visible: iconBox.isFile && status === Image.Ready
                source: iconBox.isFile ? row.iconSource : ""
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Kirigami.Icon {
                anchors.fill: parent
                visible: !picture.visible
                source: iconBox.isFile ? row.fallbackIcon : row.iconSource
                fallback: row.fallbackIcon
                active: row.hovered
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PC3.Label {
                Layout.fillWidth: true
                text: row.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: row.subtitle.length > 0
                text: row.subtitle
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                opacity: 0.75
                font: Kirigami.Theme.smallFont
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint, button) => row.contextMenuRequested(eventPoint.position.x, eventPoint.position.y)
    }
}
