// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// A month in Sill's calendar: the month's name with arrows to the months before and after, the
// weekdays, and six weeks of days, today in a highlight-coloured circle and the days of the
// months either side faint.
ColumnLayout {
    id: grid

    required property date month
    required property var days
    required property date today

    signal moveRequested(int step)

    spacing: 10

    RowLayout {
        Layout.fillWidth: true

        PC3.Label {
            Layout.fillWidth: true
            text: Qt.locale().standaloneMonthName(grid.month.getMonth(), Locale.LongFormat) + " " + grid.month.getFullYear()
            textFormat: Text.PlainText
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        PC3.ToolButton {
            icon.name: "go-up"
            display: PC3.AbstractButton.IconOnly
            text: i18nc("@action:button", "Previous month")
            Accessible.name: text
            onClicked: grid.moveRequested(-1)
        }

        PC3.ToolButton {
            icon.name: "go-down"
            display: PC3.AbstractButton.IconOnly
            text: i18nc("@action:button", "Next month")
            Accessible.name: text
            onClicked: grid.moveRequested(1)
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 4
        columnSpacing: 0

        // The weekdays, from the locale's first.
        Repeater {
            model: 7

            delegate: PC3.Label {
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                text: Qt.locale().dayName((Qt.locale().firstDayOfWeek + index) % 7, Locale.ShortFormat).slice(0, 2)
                textFormat: Text.PlainText
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Repeater {
            model: grid.days

            delegate: Item {
                id: day

                required property var modelData

                readonly property bool inMonth: day.modelData.getMonth() === grid.month.getMonth()
                readonly property bool isToday: day.modelData.toDateString() === grid.today.toDateString()

                Layout.fillWidth: true
                Layout.preferredHeight: 28

                Rectangle {
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    radius: 14
                    visible: day.isToday
                    color: Kirigami.Theme.highlightColor
                }

                PC3.Label {
                    anchors.centerIn: parent
                    text: day.modelData.getDate()
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    font.weight: day.isToday ? Font.Bold : Font.Normal
                    color: day.isToday ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    opacity: day.inMonth ? 1 : 0.4
                }
            }
        }
    }
}
