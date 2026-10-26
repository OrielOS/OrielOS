# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Accent colour, under Personalisation in Settings.
qt_add_qml_module(OrielOSAccent STATIC
    URI org.orielos.accent
    VERSION 1.0
    QML_FILES AccentPage.qml
    SOURCES accentcolour.cpp accentcolour.h
)
target_include_directories(OrielOSAccent PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSAccent PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
# KConfigGui reads and writes colours.
target_link_libraries(OrielOSAccent PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick KF6::I18n KF6::ConfigCore KF6::ConfigGui)

kcmutils_add_qml_kcm(kcm_orielos_accent SOURCES kcmaccent.cpp)
target_link_libraries(kcm_orielos_accent PRIVATE
    OrielOSAccentplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
