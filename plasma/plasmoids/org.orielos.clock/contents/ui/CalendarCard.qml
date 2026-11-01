// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// The calendar card: today's date, which folds the month away; the month with arrows to the
// months before and after; and a focus session at the bottom, which turns on Do not disturb for the
// length chosen with − and + (30 minutes at first) and counts down while it runs.
Card {
    id: card

    required property var clock

    // The time, to the second, for the focus countdown; it only ticks while a session runs and the
    // card shows.
    property double tick: Date.now()
    readonly property bool focusing: card.clock.focusEnd > 0
    readonly property string focusLeft: {
        const seconds = Math.max(0, Math.round((card.clock.focusEnd - card.tick) / 1000));
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds % 3600 / 60);
        const s = String(seconds % 60).padStart(2, "0");
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + s : m + ":" + s;
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: card.focusing && card.visible
        onTriggered: card.tick = Date.now()
    }

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

        // Focus: Do not disturb for the chosen length, with − and + to change it, and the time left
        // while it runs.
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
                text: {
                    if (card.focusing) {
                        return i18nc("@info:status %1 is the time left, such as 24:59", "Focusing · %1 left", card.focusLeft);
                    }
                    if (card.clock.doNotDisturb) {
                        return i18nc("@info:status", "Do not disturb is on");
                    }
                    return i18ncp("@info", "Focus for %1 min", "Focus for %1 min", card.clock.focusMinutes);
                }
                textFormat: Text.PlainText
                font.pixelSize: 13
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
            }

            Repeater {
                model: card.clock.doNotDisturb ? [] : [-1, 1]

                delegate: PC3.ToolButton {
                    id: stepButton

                    required property int modelData

                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    readonly property string name: modelData < 0 ? i18nc("@action:button Make the focus session shorter", "Shorter")
                                                                 : i18nc("@action:button Make the focus session longer", "Longer")
                    // Breeze's remove icon is a red cross, so the signs are drawn as text.
                    text: modelData < 0 ? "−" : "+"
                    font.pixelSize: 16
                    enabled: modelData < 0 ? card.clock.focusMinutes > 5 : card.clock.focusMinutes < 240
                    Accessible.name: name
                    PC3.ToolTip.text: name
                    PC3.ToolTip.visible: hovered
                    onClicked: card.clock.setFocusMinutes(card.clock.nextFocusLength(card.clock.focusMinutes, modelData))
                }
            }

            PC3.ToolButton {
                id: focusButton
                icon.name: card.clock.doNotDisturb ? "media-playback-stop" : "media-playback-start"
                icon.width: 12
                icon.height: 12
                text: card.clock.doNotDisturb ? i18nc("@action:button End a focus session", "Stop") : i18nc("@action:button Start a focus session", "Start")
                Accessible.name: text
                onClicked: {
                    card.tick = Date.now();
                    card.clock.setDoNotDisturb(card.clock.doNotDisturb ? 0 : card.clock.focusMinutes);
                }

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
