// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

// Recommended's More page: the longer list of new apps and recent files, with a way back.
ColumnLayout {
    id: more

    required property MenuState menu

    readonly property Item backButton: backButton
    readonly property GridView view: list.view

    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            font.weight: Font.DemiBold
            text: KI18n.i18nc("@title Recently installed apps and recently opened files", "Recommended")
            textFormat: Text.PlainText
        }

        PillButton {
            id: backButton

            back: true
            text: KI18n.i18nc("@action:button Go back to the pinned apps", "Back")

            onClicked: more.menu.showHome()
            Keys.onTabPressed: more.menu.cycleFocus(true)
            Keys.onBacktabPressed: more.menu.cycleFocus(false)
        }
    }

    RecommendedList {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true
        menu: more.menu
        scrollable: true

        onExitedTop: backButton.forceActiveFocus(Qt.BacktabFocusReason)
    }
}
