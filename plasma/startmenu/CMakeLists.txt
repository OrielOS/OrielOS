# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# OrielOS's Start menu: a Plasma widget with search, pinned apps, recommendations and the
# account and power buttons. The QML is compiled into the plugin.
plasma_add_applet(org.orielos.startmenu
    QML_SOURCES
        main.qml
        StartMenu.qml
        MenuState.qml
        HomePage.qml
        PinnedGrid.qml
        RecommendedList.qml
        AllApps.qml
        SearchResults.qml
        Footer.qml
        AppTile.qml
        ListRow.qml
        PopupMenu.qml
        getstarted.js
    RESOURCES
        main.xml
    GENERATE_APPLET_CLASS
)
