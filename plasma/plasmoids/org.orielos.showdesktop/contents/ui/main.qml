// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The show desktop sliver at the far end of the taskbar: a click shows the desktop, and a second
// click brings the windows back (KWin's Show Desktop). Sill: an 8 px strip with a faint line at
// its start, lit when hovered.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    readonly property string command: "dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/kwin org.kde.kglobalaccel.Component.invokeShortcut 'string:Show Desktop'"

    preferredRepresentation: fullRepresentation
    toolTipMainText: Plasmoid.title
    toolTipSubText: ""

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        id: sliver

        implicitWidth: 8
        Layout.minimumWidth: 8
        Layout.preferredWidth: 8
        Layout.fillHeight: true
        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Plasmoid.title

        onClicked: runner.connectSource(root.command)
        Keys.onReturnPressed: runner.connectSource(root.command)
        Keys.onSpacePressed: runner.connectSource(root.command)

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.textColor
            opacity: sliver.pressed ? 0.14 : (sliver.containsMouse || sliver.activeFocus ? 0.08 : 0)
        }

        Rectangle {
            width: 1
            height: parent.height / 2
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Kirigami.Theme.textColor
            opacity: 0.16
        }
    }
}
