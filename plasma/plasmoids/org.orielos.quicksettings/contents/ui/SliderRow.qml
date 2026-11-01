// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A Quick Settings slider: an icon, then Sill's thin track, filled in the highlight colour up to a
// white handle ringed in it. Clicking the icon does `iconClicked` (muting, for volume).
RowLayout {
    id: row

    property string iconName
    property string accessibleName
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property real value: 0

    signal moved(real value)
    signal iconClicked()

    spacing: 12

    MouseArea {
        id: iconButton

        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: row.accessibleName
        onClicked: row.iconClicked()

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Kirigami.Theme.textColor
            opacity: iconButton.containsMouse ? 0.08 : 0
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: row.iconName
        }
    }

    T.Slider {
        id: slider

        Layout.fillWidth: true
        implicitHeight: 28
        focusPolicy: Qt.TabFocus
        Accessible.name: row.accessibleName

        onMoved: row.moved(slider.value)

        // Follows the setting, except while it's being dragged.
        Binding {
            slider.value: row.value
            when: !slider.pressed
            restoreMode: Binding.RestoreNone
        }

        background: Item {
            x: slider.leftPadding
            width: slider.availableWidth
            height: slider.height

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Kirigami.Theme.textColor
                opacity: 0.25
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: slider.visualPosition * parent.width
                height: 4
                radius: 2
                color: Kirigami.Theme.highlightColor
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + (slider.availableHeight - height) / 2
            width: 20
            height: 20
            radius: 10
            color: "white"
            border.width: slider.pressed || slider.visualFocus ? 6 : 5
            border.color: Kirigami.Theme.highlightColor
        }
    }
}
