// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The calendar card: today's date, which folds the month away; the month with arrows to the
// months before and after; and a focus session at the bottom, which turns on Do not disturb for
// half an hour.
Card {
    id: card

    required property var clock

    property bool folded: false
    // The first of the month showing.
    property date month: new Date(card.clock.now.getFullYear(), card.clock.now.getMonth(), 1)
    readonly property int firstDay: Qt.locale().firstDayOfWeek

    function moveMonth(step: int) {
        card.month = new Date(card.month.getFullYear(), card.month.getMonth() + step, 1);
    }

    // The 42 days on the grid, starting with the locale's first weekday on or before the 1st.
    readonly property var days: {
        const lead = (card.month.getDay() - card.firstDay + 7) % 7;
        const start = new Date(card.month.getFullYear(), card.month.getMonth(), 1 - lead);
        const list = [];
        for (let i = 0; i < 42; ++i) {
            list.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        }
        return list;
    }

    implicitHeight: content.implicitHeight

    Connections {
        target: card.clock
        function onOpenChanged() {
            if (card.clock.open) {
                card.month = new Date(card.clock.now.getFullYear(), card.clock.now.getMonth(), 1);
            }
        }
    }

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // Today: Sill's heading, which folds the month away.
        MouseArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            Accessible.role: Accessible.Button
            Accessible.name: today.text
            onClicked: card.folded = !card.folded

            PC3.Label {
                id: today
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.locale().toString(card.clock.now, "dddd d MMMM")
                textFormat: Text.PlainText
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Kirigami.Icon {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                source: card.folded ? "go-up" : "go-down"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.textColor
            opacity: 0.08
        }

        MonthGrid {
            Layout.fillWidth: true
            Layout.margins: 20
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            visible: !card.folded
            month: card.month
            days: card.days
            today: card.clock.now
            onMoveRequested: step => card.moveMonth(step)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Kirigami.Theme.textColor
            opacity: 0.08
        }

        // Focus: Do not disturb for half an hour.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.leftMargin: 20
            Layout.rightMargin: 12
            spacing: 8

            Kirigami.Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: "chronometer"
            }

            PC3.Label {
                Layout.fillWidth: true
                text: card.clock.doNotDisturb ? i18nc("@info:status", "Focusing: Do not disturb is on") : i18nc("@info", "Focus for 30 min")
                textFormat: Text.PlainText
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            PC3.ToolButton {
                id: focusButton
                icon.name: card.clock.doNotDisturb ? "media-playback-stop" : "media-playback-start"
                icon.width: 12
                icon.height: 12
                text: card.clock.doNotDisturb ? i18nc("@action:button End a focus session", "Stop") : i18nc("@action:button Start a focus session", "Start")
                Accessible.name: text
                onClicked: card.clock.setDoNotDisturb(card.clock.doNotDisturb ? 0 : 30)

                background: Rectangle {
                    implicitHeight: 32
                    radius: 4
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, focusButton.hovered ? 0.14 : 0.08)
                    border.width: focusButton.visualFocus ? 2 : 0
                    border.color: Kirigami.Theme.focusColor
                }
            }
        }
    }
}
