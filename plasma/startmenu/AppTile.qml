// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// A pinned app: its icon with its name underneath.
PC3.ItemDelegate {
    id: tile

    required property string label
    required property var iconSource
    // Whether the tile is the keyboard's current item.
    property bool current: false

    // Right-click, at (x, y) in the tile's coordinates.
    signal contextMenuRequested(real x, real y)

    text: label
    highlighted: current
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
            source: tile.iconSource
            active: tile.hovered
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
