# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The desktop's right-click menu, a Plasma containment actions plugin, org.orielos.desktopmenu.
# The OrielOS shell's defaults file chooses it for the desktop's right button.
find_package(Plasma REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Widgets Qml)
find_package(KF6 REQUIRED COMPONENTS KIO I18n CoreAddons)

kcoreaddons_add_plugin(orielosdesktopmenu SOURCES desktopmenu.cpp INSTALL_NAMESPACE "plasma/containmentactions")
set_target_properties(orielosdesktopmenu PROPERTIES OUTPUT_NAME org.orielos.desktopmenu)
target_compile_definitions(orielosdesktopmenu PRIVATE TRANSLATION_DOMAIN="orielos-desktopmenu")
target_link_libraries(orielosdesktopmenu PRIVATE
    Qt6::Widgets
    Qt6::Qml
    KF6::CoreAddons
    KF6::I18n
    KF6::KIOCore
    KF6::KIOGui
    Plasma::Plasma
)
