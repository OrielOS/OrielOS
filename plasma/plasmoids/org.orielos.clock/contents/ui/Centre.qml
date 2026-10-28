// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// The notification centre: Sill's notifications card over the calendar card, 12 px apart, with
// the same gap to the taskbar under them and to the screen's edge beside them, left clear.
Item {
    id: centre

    required property var clock
    property int gap: 12

    width: 382 + centre.gap
    height: cards.implicitHeight + centre.gap

    ColumnLayout {
        id: cards

        width: 382
        spacing: centre.gap

        NotificationsCard {
            Layout.fillWidth: true
            clock: centre.clock
        }

        CalendarCard {
            Layout.fillWidth: true
            clock: centre.clock
        }
    }
}
