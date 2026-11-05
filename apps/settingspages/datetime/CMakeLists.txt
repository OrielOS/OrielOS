# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Date & time, under Time & language in Settings: the clock, network time, setting the time zone
# automatically and Sync now, through systemd-timedated, chrony and OrielOS's time helpers.
qt_add_qml_module(OrielOSDateTime STATIC
    URI org.orielos.datetime
    VERSION 1.0
    QML_FILES DateTimePage.qml
    SOURCES datetimesettings.cpp datetimesettings.h
)
target_include_directories(OrielOSDateTime PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSDateTime PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSDateTime PUBLIC Qt6::Core Qt6::DBus Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_datetime SOURCES kcmdatetime.cpp)
target_link_libraries(kcm_orielos_datetime PRIVATE
    OrielOSDateTimeplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
