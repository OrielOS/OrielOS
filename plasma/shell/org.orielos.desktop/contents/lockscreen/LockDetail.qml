/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// The detailed status above the bottom of the idle lock screen, as in Sill's lock screen: the next
// item in the calendar within a week, such as "Tomorrow 09:30 · Dentist". The items come from
// Plasma's calendar plugins (public holidays for the regions the user picked, and the events of any
// calendar that provides a plugin), the ones named in the lock screen's `detailedStatusCalendars`
// setting. With nothing coming up, it hides.

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.calendar as PlasmaCalendar

Rectangle {
    id: detail

    property color textColor: "#FFFFFF"
    property var calendars: []
    // How far ahead to look, in days.
    property int daysAhead: 7

    // The next item as "When · What", or "" when there's nothing coming up.
    property string text: ""

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 40
    radius: height / 2
    color: Qt.rgba(12 / 255, 21 / 255, 48 / 255, 0.55)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)
    visible: text !== ""

    Accessible.role: Accessible.StaticText
    Accessible.name: text

    function describe(event) {
        const start = event.startDateTime;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const day = new Date(start);
        day.setHours(0, 0, 0, 0);
        const days = Math.round((day - today) / 86400000);
        let when;
        if (days === 0) {
            when = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status the calendar item is today", "Today");
        } else if (days === 1) {
            when = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status the calendar item is tomorrow", "Tomorrow");
        } else {
            when = Qt.locale().dayName(day.getDay(), Locale.LongFormat);
        }
        if (!event.isAllDay) {
            when += " " + start.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        }
        return i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status when, then what: Tomorrow 09:30 · Dentist", "%1 · %2", when, event.title);
    }

    function refresh() {
        const now = new Date();
        let next = null;
        for (let offset = 0; offset <= daysAhead; ++offset) {
            const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
            const events = calendar.daysModel.eventsForDate(date);
            for (const event of events) {
                if (event.isMinor || (!event.isAllDay && event.startDateTime < now)) {
                    continue;
                }
                if (!next || event.startDateTime < next.startDateTime) {
                    next = event;
                }
            }
            if (next) {
                break;
            }
        }
        detail.text = next ? describe(next) : "";
    }

    PlasmaCalendar.EventPluginsManager {
        id: plugins
        enabledPlugins: detail.calendars
    }

    PlasmaCalendar.Calendar {
        id: calendar
        days: 7
        weeks: 6
        today: new Date()
        displayedDate: new Date()
        Component.onCompleted: daysModel.setPluginsManager(plugins)
    }

    Connections {
        target: calendar.daysModel
        function onAgendaUpdated() {
            Qt.callLater(detail.refresh);
        }
    }

    // The next item changes as time passes even when the calendars don't.
    Timer {
        interval: 60000
        running: detail.calendars.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: detail.refresh()
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 12

        Kirigami.Icon {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            source: "view-calendar-symbolic"
            isMask: true
            color: "#9CC2FF"
        }
        PlasmaComponents3.Label {
            text: detail.text
            textFormat: Text.PlainText
            color: detail.textColor
            font.pixelSize: 13
        }
    }
}
