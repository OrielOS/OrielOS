# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Power mode, under System in Settings: the power profiles daemon's Performance, Balanced and Power
# saver.
qt_add_qml_module(OrielOSPowerMode STATIC
    URI org.orielos.powermode
    VERSION 1.0
    QML_FILES PowerModePage.qml
    SOURCES powermode.cpp powermode.h
)
target_include_directories(OrielOSPowerMode PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSPowerMode PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSPowerMode PUBLIC Qt6::Core Qt6::DBus Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_powermode SOURCES kcmpowermode.cpp)
target_link_libraries(kcm_orielos_powermode PRIVATE
    OrielOSPowerModeplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
