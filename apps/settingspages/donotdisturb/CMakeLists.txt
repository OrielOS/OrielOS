# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Do not disturb, under System in Settings: turning it on at set times.
qt_add_qml_module(OrielOSDoNotDisturb STATIC
    URI org.orielos.donotdisturb
    VERSION 1.0
    QML_FILES DoNotDisturbPage.qml
    SOURCES dndschedule.cpp dndschedule.h
)
target_include_directories(OrielOSDoNotDisturb PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSDoNotDisturb PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSDoNotDisturb PUBLIC Qt6::Core Qt6::Qml Qt6::Quick KF6::I18n KF6::ConfigCore)

kcmutils_add_qml_kcm(kcm_orielos_donotdisturb SOURCES kcmdonotdisturb.cpp)
target_link_libraries(kcm_orielos_donotdisturb PRIVATE
    OrielOSDoNotDisturbplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
