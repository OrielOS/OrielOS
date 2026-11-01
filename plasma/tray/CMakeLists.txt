# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# OrielOS's system tray: the apps' icons on the taskbar, the hidden icons button and its pane, the
# location icon and the eject menu for USB drives. A Plasma widget whose QML is compiled into the
# plugin with trayapplet.cpp, the applet class. Plasma's own tray stays on the taskbar, hidden,
# because it hosts the widgets OrielOS still needs (notification pop-ups, the clipboard), and this
# widget asks it to open the apps' menus. Which icons go where and the drives' names are in
# traylogic.cpp, which autotests/ checks; drives.cpp watches and ejects the drives.
find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(KF6 REQUIRED COMPONENTS Solid)
find_package(PlasmaQuick REQUIRED)

add_library(orielostraylogic STATIC traylogic.cpp traylogic.h drives.cpp drives.h)
set_property(TARGET orielostraylogic PROPERTY POSITION_INDEPENDENT_CODE ON)
target_include_directories(orielostraylogic PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(orielostraylogic PRIVATE TRANSLATION_DOMAIN="plasma_applet_org.orielos.tray")
target_link_libraries(orielostraylogic PUBLIC Qt6::Core Qt6::DBus KF6::I18n KF6::Solid)

plasma_add_applet(org.orielos.tray
    QML_SOURCES
        main.qml
        TrayIcon.qml
        HiddenIcons.qml
        ExpanderArrow.qml
    RESOURCES
        main.xml
    CPP_SOURCES
        trayapplet.cpp
)
target_compile_definitions(org.orielos.tray PRIVATE TRANSLATION_DOMAIN="plasma_applet_org.orielos.tray")
target_link_libraries(org.orielos.tray PRIVATE
    orielostraylogic
    Qt6::DBus
    Qt6::Quick
    KF6::CoreAddons
    KF6::I18n
    Plasma::Plasma
    Plasma::PlasmaQuick
)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
