# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Background, under Personalisation in Settings: the desktop's picture, the recent ones and the fit.
qt_add_qml_module(OrielOSBackground STATIC
    URI org.orielos.background
    VERSION 1.0
    QML_FILES BackgroundPage.qml
    SOURCES desktopbackground.cpp desktopbackground.h
)
target_include_directories(OrielOSBackground PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSBackground PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSBackground PUBLIC Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml Qt6::Quick)

kcmutils_add_qml_kcm(kcm_orielos_background SOURCES kcmbackground.cpp)
target_link_libraries(kcm_orielos_background PRIVATE
    OrielOSBackgroundplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
