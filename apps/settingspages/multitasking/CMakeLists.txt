# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Multitasking, under System in Settings: snapping windows and Alt+Tab.
qt_add_qml_module(OrielOSMultitasking STATIC
    URI org.orielos.multitasking
    VERSION 1.0
    QML_FILES MultitaskingPage.qml
    SOURCES multitaskingoptions.cpp multitaskingoptions.h
)
target_include_directories(OrielOSMultitasking PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSMultitasking PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSMultitasking PUBLIC Qt6::Core Qt6::DBus Qt6::Qml Qt6::Quick KF6::ConfigCore)

kcmutils_add_qml_kcm(kcm_orielos_multitasking SOURCES kcmmultitasking.cpp)
target_link_libraries(kcm_orielos_multitasking PRIVATE
    OrielOSMultitaskingplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
