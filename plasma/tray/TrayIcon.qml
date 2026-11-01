// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// One icon in the tray, on the taskbar or in the hidden icons pane: lit while the pointer or the
// keyboard is on it, with its app's tooltip. A click activates it, a right-click (or the menu key,
// or Shift+F10) asks for its menu, a middle click and the wheel go to the app, and an app's icon
// can be dragged between the taskbar and the pane.
PlasmaCore.ToolTipArea {
    id: icon

    property string itemId
    property var source
    property string title
    property string subTitle
    property int iconSize: 18
    property real radius: 4
    // Space around the lit area, which lets grid cells sit apart.
    property real inset: 0
    // Lit as the keyboard's current icon, in the pane's grid.
    property bool current: false
    // The drag's data format; empty for icons that stay where they are.
    property string dragFormat
    readonly property bool dragging: mouse.drag.active

    signal activated()
    signal menuRequested(real x, real y)
    signal middleClicked()
    signal scrolled(int delta, string direction)

    mainText: icon.title
    subText: icon.subTitle
    active: !mouse.drag.active && (icon.title !== "" || icon.subTitle !== "")

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: icon.title
    Accessible.description: icon.subTitle
    Accessible.onPressAction: icon.activated()

    function handleKey(event: KeyEvent): bool {
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
        case Qt.Key_Select:
            icon.activated();
            return true;
        case Qt.Key_Menu:
            icon.menuRequested(icon.width / 2, icon.height / 2);
            return true;
        case Qt.Key_F10:
            if (event.modifiers & Qt.ShiftModifier) {
                icon.menuRequested(icon.width / 2, icon.height / 2);
                return true;
            }
            return false;
        }
        return false;
    }

    Keys.onPressed: event => event.accepted = icon.handleKey(event)

    Rectangle {
        anchors.fill: parent
        anchors.margins: icon.inset
        radius: icon.radius
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
            mouse.pressed ? 0.06 : (mouse.containsMouse || icon.current || icon.activeFocus ? 0.10 : 0))
    }

    Kirigami.Icon {
        id: glyph
        anchors.centerIn: parent
        implicitWidth: icon.iconSize
        implicitHeight: icon.iconSize
        source: icon.source
        active: mouse.containsMouse
    }

    // What the drag carries; Plasma's drag-and-drop moves the picture, not this item.
    Item {
        id: dragProxy
        anchors.fill: parent
        Drag.active: mouse.drag.active
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction
        Drag.mimeData: icon.dragFormat === "" ? ({}) : ({ [icon.dragFormat]: icon.itemId })
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        drag.target: icon.dragFormat === "" ? null : dragProxy

        // The drag shows the icon itself under the pointer.
        onEntered: {
            if (icon.dragFormat !== "") {
                glyph.grabToImage(result => dragProxy.Drag.imageSource = result.url);
            }
        }
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                icon.menuRequested(event.x, event.y);
            } else if (event.button === Qt.MiddleButton) {
                icon.middleClicked();
            } else {
                icon.activated();
            }
        }
        onWheel: wheel => {
            // A delta of 0 confuses some apps, so only the directions that moved are sent.
            if (wheel.angleDelta.y !== 0) {
                icon.scrolled(wheel.angleDelta.y, "vertical");
            }
            if (wheel.angleDelta.x !== 0) {
                icon.scrolled(wheel.angleDelta.x, "horizontal");
            }
        }
    }
}
