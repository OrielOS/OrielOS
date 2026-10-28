// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The taskbar's Task View button, after Search: shows every open window and the desktops, as
// Win+Tab does (KWin's Overview). Sill: a 44 px button with two overlapping windows and a rounded
// highlight when hovered or pressed. Keep this in step with org.orielos.search, its twin.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    readonly property string command: "dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/kwin org.kde.kglobalaccel.Component.invokeShortcut string:Overview"

    preferredRepresentation: fullRepresentation
    toolTipMainText: Plasmoid.title
    toolTipSubText: ""

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        id: button

        implicitWidth: 44
        implicitHeight: 40
        Layout.minimumWidth: 44
        Layout.minimumHeight: 40
        Layout.fillHeight: true
        Layout.preferredWidth: 44
        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Plasmoid.title

        onClicked: runner.connectSource(root.command)
        Keys.onReturnPressed: runner.connectSource(root.command)
        Keys.onSpacePressed: runner.connectSource(root.command)

        Rectangle {
            anchors.centerIn: parent
            width: 44
            height: 40
            radius: 6
            color: Kirigami.Theme.textColor
            opacity: button.pressed ? 0.14 : (button.containsMouse || button.activeFocus ? 0.08 : 0)
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: Kirigami.Units.iconSizes.smallMedium
            source: "window-duplicate"
        }
    }
}
