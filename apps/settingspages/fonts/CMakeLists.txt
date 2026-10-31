# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Fonts, under Personalisation in Settings: the installed fonts, and installing more.
qt_add_qml_module(OrielOSFonts STATIC
    URI org.orielos.fonts
    VERSION 1.0
    QML_FILES FontsPage.qml
    SOURCES fontlibrary.cpp fontlibrary.h
)
target_include_directories(OrielOSFonts PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSFonts PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSFonts PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)

kcmutils_add_qml_kcm(kcm_orielos_fonts SOURCES kcmfonts.cpp)
target_link_libraries(kcm_orielos_fonts PRIVATE
    OrielOSFontsplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
