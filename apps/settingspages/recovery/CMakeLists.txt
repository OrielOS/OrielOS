# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Recovery, under System in Settings: Reset this PC, through orielos-reset.
qt_add_qml_module(OrielOSRecovery STATIC
    URI org.orielos.recovery
    VERSION 1.0
    QML_FILES RecoveryPage.qml
    SOURCES resetpc.cpp resetpc.h
)
target_include_directories(OrielOSRecovery PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSRecovery PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSRecovery PUBLIC Qt6::Core Qt6::DBus Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_recovery SOURCES kcmrecovery.cpp)
target_link_libraries(kcm_orielos_recovery PRIVATE
    OrielOSRecoveryplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
