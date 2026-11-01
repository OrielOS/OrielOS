// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A media control in Quick Settings: a plain icon, or Sill's round play button.
MouseArea {
    id: button

    property string iconName
    property string accessibleName
    property bool round: false

    Layout.preferredWidth: round ? 40 : 28
    Layout.preferredHeight: round ? 40 : 28
    hoverEnabled: true
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.4
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName

    Keys.onSpacePressed: clicked(null)
    Keys.onReturnPressed: clicked(null)

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Kirigami.Theme.textColor
        opacity: button.round ? (button.containsMouse ? 0.20 : 0.12) : (button.containsMouse ? 0.08 : 0)
        border.width: button.activeFocus ? 2 : 0
        border.color: Kirigami.Theme.focusColor
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: 16
        height: 16
        source: button.iconName
    }
}
