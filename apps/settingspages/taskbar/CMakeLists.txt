# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Taskbar, under Personalisation in Settings: its alignment and auto-hide.
qt_add_qml_module(OrielOSTaskbar STATIC
    URI org.orielos.taskbar
    VERSION 1.0
    QML_FILES TaskbarPage.qml
    SOURCES taskbaroptions.cpp taskbaroptions.h
)
target_include_directories(OrielOSTaskbar PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSTaskbar PUBLIC OrielOSShellSettings Qt6::Core Qt6::Qml Qt6::Quick)

kcmutils_add_qml_kcm(kcm_orielos_taskbar SOURCES kcmtaskbar.cpp)
target_link_libraries(kcm_orielos_taskbar PRIVATE
    OrielOSTaskbarplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
