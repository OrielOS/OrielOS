# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Recent activity, under Privacy & security in Settings: the apps that used the camera, the
# microphone and the location in the last seven days.
qt_add_qml_module(OrielOSRecentActivity STATIC
    URI org.orielos.recentactivity
    VERSION 1.0
    QML_FILES RecentActivityPage.qml
    SOURCES recentactivity.cpp recentactivity.h
)
target_include_directories(OrielOSRecentActivity PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSRecentActivity PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSRecentActivity PUBLIC Qt6::Core Qt6::Qml Qt6::Quick KF6::I18n KF6::Service)

kcmutils_add_qml_kcm(kcm_orielos_recentactivity SOURCES kcmrecentactivity.cpp)
target_link_libraries(kcm_orielos_recentactivity PRIVATE
    OrielOSRecentActivityplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
