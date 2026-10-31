# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# OrielOS's Start menu: a Plasma widget with search, pinned apps, recommendations and the
# account and power buttons. The QML is compiled into the plugin, with startapplet.cpp, the applet
# class, which adds the Win+X power user menu.
find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(KF6 REQUIRED COMPONENTS GlobalAccel KIO Service)
find_package(PlasmaQuick REQUIRED)

plasma_add_applet(org.orielos.startmenu
    QML_SOURCES
        main.qml
        StartMenu.qml
        MenuState.qml
        HomePage.qml
        PinnedGrid.qml
        RecommendedList.qml
        AllApps.qml
        CategoryView.qml
        MorePage.qml
        PillButton.qml
        SearchResults.qml
        SearchHome.qml
        Footer.qml
        AppTile.qml
        ListRow.qml
        PopupMenu.qml
        PowerUserMenu.qml
        getstarted.js
    RESOURCES
        main.xml
    CPP_SOURCES
        startapplet.cpp
)
target_compile_definitions(org.orielos.startmenu PRIVATE TRANSLATION_DOMAIN="plasma_applet_org.orielos.startmenu")
target_link_libraries(org.orielos.startmenu PRIVATE
    Qt6::DBus
    KF6::CoreAddons
    KF6::GlobalAccel
    KF6::I18n
    KF6::KIOGui
    KF6::Service
    Plasma::Plasma
    Plasma::PlasmaQuick
)
