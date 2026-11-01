// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.ki18n
import org.kde.kirigami as Kirigami

// The hidden icons button: Sill's thin chevron, pointing up, and down while the pane is open,
// when it is lit like the taskbar's other open buttons. Dragging an icon over it opens the pane.
MouseArea {
    id: arrow

    property bool open: false
    property string dragFormat
    // Whether the pane was open when the button was pressed: pressing outside the pane closes it
    // before the click arrives, and the click mustn't open it again.
    property bool wasOpen: false

    signal openRequested(bool open)

    hoverEnabled: true
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: arrow.open ? KI18n.i18nc("@action:button", "Hide hidden icons") : KI18n.i18nc("@action:button", "Show hidden icons")
    Accessible.onPressAction: arrow.openRequested(!arrow.open)

    onPressed: arrow.wasOpen = arrow.open
    onClicked: arrow.openRequested(!arrow.wasOpen)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Select) {
            arrow.openRequested(!arrow.open);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Math.max(0, (parent.height - 40) / 2)
        anchors.bottomMargin: anchors.topMargin
        radius: 6
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
            arrow.open ? 0.10 : (arrow.containsMouse || arrow.activeFocus ? 0.06 : 0))
    }

    // Sill's chevron is drawn on a 24-unit grid at 16 px.
    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: 16 / 24
        rotation: arrow.open ? 180 : 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Kirigami.Theme.textColor
            strokeWidth: 1.8 * 24 / 16
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M6 14.5 L12 8.5 L18 14.5" }
        }
    }

    DropArea {
        anchors.fill: parent
        keys: [arrow.dragFormat]
        onEntered: arrow.openRequested(true)
    }
}
