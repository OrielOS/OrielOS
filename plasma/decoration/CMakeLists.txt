# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# OrielOS's window frames, a KWin decoration plugin (KDecoration3), org.orielos.decoration.
# /etc/xdg/kwinrc makes it the default.
find_package(KDecoration3 REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(KF6 REQUIRED COMPONENTS CoreAddons Config)

add_library(orielosdecoration MODULE
    decoration.cpp
    button.cpp
    shadow.cpp
)
set_target_properties(orielosdecoration PROPERTIES OUTPUT_NAME org.orielos.decoration)
target_link_libraries(orielosdecoration PRIVATE
    Qt6::DBus
    Qt6::Gui
    KF6::ConfigCore
    KF6::CoreAddons
    KDecoration3::KDecoration
)
install(TARGETS orielosdecoration DESTINATION ${KDE_INSTALL_PLUGINDIR}/${KDECORATION_PLUGIN_DIR})
