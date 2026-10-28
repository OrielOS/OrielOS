// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

// The page the menu opens on: the pinned apps and the recommendations.
ColumnLayout {
    id: home

    required property MenuState menu

    readonly property Item allAppsButton: allAppsButton
    readonly property GridView pinnedView: pinned.view
    readonly property GridView recommendedView: recommended.view
    readonly property Item moreButton: moreButton

    // Back to the first page of pinned apps, as each time the menu opens.
    function reset() {
        pinned.showPage(0);
    }

    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            font.weight: Font.DemiBold
            text: KI18n.i18nc("@title The pinned apps", "Pinned")
            textFormat: Text.PlainText
        }

        PillButton {
            id: allAppsButton

            text: KI18n.i18nc("@action:button Show every app", "All apps")

            onClicked: home.menu.showAllApps()
            Keys.onTabPressed: home.menu.cycleFocus(true)
            Keys.onBacktabPressed: home.menu.cycleFocus(false)
        }
    }

    PinnedGrid {
        id: pinned

        Layout.fillWidth: true
        Layout.preferredHeight: tileHeight * home.menu.pinnedRows
        menu: home.menu
    }

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
            id: moreButton

            text: KI18n.i18nc("@action:button Show more recommendations", "More")

            onClicked: home.menu.showMore()
            Keys.onTabPressed: home.menu.cycleFocus(true)
            Keys.onBacktabPressed: home.menu.cycleFocus(false)
        }
    }

    RecommendedList {
        id: recommended

        Layout.fillWidth: true
        Layout.fillHeight: true
        menu: home.menu

        onExitedTop: home.menu.focusPinned()
    }
}
