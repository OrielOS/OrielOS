// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// One layout, drawn as a small screen split into its areas. Pointing at an area highlights it;
// clicking it snaps the window there.

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: tile

    // The layout's areas, as in main.qml's layouts.
    required property var areas
    // The index of this layout's first area among all of them, and the highlighted one.
    required property int firstIndex
    required property int current
    // The layout's number, shown at its top left, or 0 for none; whether its areas show theirs.
    property int number: 0
    property bool numberedAreas: false

    signal highlighted(int areaIndex)
    signal chosen(var area)

    readonly property real gap: Kirigami.Units.smallSpacing

    Repeater {
        model: tile.areas

        Rectangle {
            id: area

            required property var modelData
            required property int index
            readonly property bool highlighted: tile.current === tile.firstIndex + area.index

            x: Math.round(area.modelData.x * tile.width + tile.gap / 2)
            y: Math.round(area.modelData.y * tile.height + tile.gap / 2)
            width: Math.round(area.modelData.width * tile.width - tile.gap)
            height: Math.round(area.modelData.height * tile.height - tile.gap)
            radius: Kirigami.Units.smallSpacing
            color: area.highlighted ? Kirigami.Theme.highlightColor : Kirigami.Theme.alternateBackgroundColor
            border.width: 1
            border.color: area.highlighted ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)

            Accessible.role: Accessible.Button
            Accessible.name: area.modelData.name
            Accessible.focused: area.highlighted

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: tile.highlighted(tile.firstIndex + area.index)
                onClicked: tile.chosen(area.modelData)
            }

            Text {
                anchors.centerIn: parent
                visible: tile.numberedAreas
                text: area.index + 1
                font.weight: Font.DemiBold
                color: area.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
            }
        }
    }

    Rectangle {
        x: -Kirigami.Units.smallSpacing
        y: -Kirigami.Units.smallSpacing
        width: Kirigami.Units.gridUnit * 1.2
        height: width
        radius: width / 2
        visible: tile.number > 0
        color: Kirigami.Theme.textColor

        Text {
            anchors.centerIn: parent
            text: tile.number
            font.weight: Font.DemiBold
            color: Kirigami.Theme.backgroundColor
        }
    }
}
