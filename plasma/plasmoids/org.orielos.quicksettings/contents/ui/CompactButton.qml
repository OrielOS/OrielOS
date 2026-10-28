// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Quick Settings on the taskbar: the network, volume and battery icons in one rounded button.
// Clicking opens the panel; the wheel changes the volume.
MouseArea {
    id: button

    required property var quickSettings

    // The open panel lights the button through the shell's popup; hovering lights it here.
    Layout.minimumWidth: row.implicitWidth + 24
    Layout.preferredWidth: row.implicitWidth + 24
    Layout.fillHeight: true
    hoverEnabled: true
    activeFocusOnTab: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    Accessible.role: Accessible.Button
    Accessible.name: button.quickSettings.toolTipMainText
    Accessible.description: button.quickSettings.toolTipSubText

    property bool wasExpanded: false
    property real wheelSum: 0

    onPressed: mouse => {
        button.wasExpanded = button.quickSettings.expanded;
    }
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            if (button.quickSettings.hasSink) {
                button.quickSettings.sink.muted = !button.quickSettings.sink.muted;
            }
            return;
        }
        button.quickSettings.expanded = !button.wasExpanded;
    }
    onWheel: wheel => {
        button.wheelSum += wheel.angleDelta.y;
        const steps = Math.trunc(button.wheelSum / 120);
        if (steps !== 0) {
            button.quickSettings.changeVolume(steps);
            button.wheelSum -= steps * 120;
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            button.quickSettings.expanded = !button.quickSettings.expanded;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Kirigami.Theme.textColor
        opacity: button.pressed ? 0.14 : (button.containsMouse || button.activeFocus ? 0.08 : 0)
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: 10

        Kirigami.Icon {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            source: button.quickSettings.networkIcon
        }

        Kirigami.Icon {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            source: button.quickSettings.volumeIcon
        }

        Kirigami.Icon {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: button.quickSettings.hasBattery
            source: button.quickSettings.batteryIcon
        }
    }
}
