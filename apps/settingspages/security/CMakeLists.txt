# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Device security, under Privacy & security in Settings: the self-test for games with anti-cheat.
qt_add_qml_module(OrielOSSecurity STATIC
    URI org.orielos.security
    VERSION 1.0
    QML_FILES SecurityPage.qml
    SOURCES securitychecks.cpp securitychecks.h devicesecurity.cpp devicesecurity.h
)
target_include_directories(OrielOSSecurity PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSSecurity PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSSecurity PUBLIC Qt6::Core Qt6::Concurrent Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_security SOURCES kcmsecurity.cpp)
target_link_libraries(kcm_orielos_security PRIVATE
    OrielOSSecurityplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
