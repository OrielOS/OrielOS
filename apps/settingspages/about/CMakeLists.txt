# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# About, under System in Settings: this PC's name, with Rename this PC through systemd-hostnamed,
# and what the PC and OrielOS are.
qt_add_qml_module(OrielOSAbout STATIC
    URI org.orielos.about
    VERSION 1.0
    QML_FILES AboutPage.qml
    SOURCES aboutinfo.cpp aboutinfo.h
)
target_include_directories(OrielOSAbout PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSAbout PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSAbout PUBLIC Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_about SOURCES kcmabout.cpp)
target_link_libraries(kcm_orielos_about PRIVATE
    OrielOSAboutplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
