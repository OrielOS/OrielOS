# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The taskbar's right-click menu, a Plasma containment actions plugin, org.orielos.panelmenu.
# The OrielOS shell's defaults file chooses it for the taskbar's right button.
find_package(Plasma REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Widgets)
find_package(KF6 REQUIRED COMPONENTS KIO I18n CoreAddons Service)

kcoreaddons_add_plugin(orielospanelmenu SOURCES panelmenu.cpp INSTALL_NAMESPACE "plasma/containmentactions")
set_target_properties(orielospanelmenu PROPERTIES OUTPUT_NAME org.orielos.panelmenu)
target_compile_definitions(orielospanelmenu PRIVATE TRANSLATION_DOMAIN="orielos-desktopmenu")
target_link_libraries(orielospanelmenu PRIVATE
    Qt6::Widgets
    KF6::CoreAddons
    KF6::I18n
    KF6::KIOGui
    KF6::Service
    Plasma::Plasma
)
