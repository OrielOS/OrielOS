// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The clock and the bell on the taskbar: two rounded buttons side by side, both lit while the
// notification centre is open.
RowLayout {
    id: buttons

    required property var clock

    // Remembered at the press: by the click, the popup may have closed on losing focus.
    property bool wasExpanded: false

    function toggle() {
        buttons.clock.open = !buttons.wasExpanded;
    }

    Layout.fillHeight: true
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    spacing: 2

    MouseArea {
        id: time

        Layout.fillHeight: true
        Layout.preferredWidth: Math.max(timeLabel.implicitWidth, dateLabel.implicitWidth) + 20
        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: buttons.clock.toolTipMainText

        onPressed: buttons.wasExpanded = buttons.clock.open
        onClicked: buttons.toggle()
        Keys.onSpacePressed: buttons.clock.open = !buttons.clock.open

        Highlight {
            lit: buttons.clock.open
            hovered: time.containsMouse
            pressed: time.pressed
        }

        ColumnLayout {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            PC3.Label {
                id: timeLabel
                Layout.alignment: Qt.AlignRight
                text: buttons.clock.now.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                textFormat: Text.PlainText
                font.pixelSize: 12
            }

            PC3.Label {
                id: dateLabel
                Layout.alignment: Qt.AlignRight
                text: buttons.clock.now.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                textFormat: Text.PlainText
                font.pixelSize: 12
            }
        }
    }

    MouseArea {
        id: bell

        Layout.fillHeight: true
        Layout.preferredWidth: 32
        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: buttons.clock.toolTipSubText.length > 0 ? buttons.clock.toolTipSubText : i18nc("@action:button", "Notifications")

        onPressed: buttons.wasExpanded = buttons.clock.open
        onClicked: buttons.toggle()
        Keys.onSpacePressed: buttons.clock.open = !buttons.clock.open

        Highlight {
            lit: buttons.clock.open
            hovered: bell.containsMouse
            pressed: bell.pressed
        }

        Kirigami.Icon {
            id: bellIcon
            anchors.centerIn: parent
            width: 16
            height: 16
            source: buttons.clock.doNotDisturb ? "notifications-disabled" : "notifications"
        }

        // Sill's badge: the count in a highlight-coloured circle at the bell's top right.
        Rectangle {
            x: bellIcon.x + bellIcon.width - width / 2
            y: bellIcon.y - height / 2 + 2
            width: Math.max(height, badgeLabel.implicitWidth + 6)
            height: 14
            radius: height / 2
            visible: buttons.clock.unreadCount > 0 && !buttons.clock.doNotDisturb
            color: Kirigami.Theme.highlightColor

            PC3.Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: buttons.clock.unreadCount
                color: Kirigami.Theme.highlightedTextColor
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
    }
}
