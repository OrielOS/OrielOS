# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Installed apps, under Apps in Settings: the apps from the Store, with Uninstall, and where apps
# may come from.
qt_add_qml_module(OrielOSInstalledApps STATIC
    URI org.orielos.installedapps
    VERSION 1.0
    QML_FILES InstalledAppsPage.qml
    SOURCES installedapps.cpp installedapps.h
)
target_include_directories(OrielOSInstalledApps PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSInstalledApps PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSInstalledApps PUBLIC Qt6::Core Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_installedapps SOURCES kcminstalledapps.cpp)
target_link_libraries(kcm_orielos_installedapps PRIVATE
    OrielOSInstalledAppsplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
