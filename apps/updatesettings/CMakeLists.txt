# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The Update settings page: a Plasma settings module, kcm_orielos_update, which System Settings
# shows under System and opens with "systemsettings kcm_orielos_update".

find_package(Qt6 6.8 REQUIRED COMPONENTS DBus)
find_package(KF6 6.0 REQUIRED COMPONENTS KCMUtils)

# The page and its model, as a static QML module, so qmllint checks the page and the unit tests can
# use the model without the settings module. The settings module is a shared object, so everything
# linked into it, the module's generated resource objects included, must be position-independent.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
qt_add_qml_module(OrielOSUpdateSettings STATIC
    URI org.orielos.updatesettings
    VERSION 1.0
    QML_FILES
        UpdatePage.qml
        ConfirmationDialog.qml
    SOURCES
        updatesettings.cpp updatesettings.h
        updatecommands.cpp updatecommands.h
)
target_compile_definitions(OrielOSUpdateSettings PRIVATE TRANSLATION_DOMAIN="kcm_orielos_update")
target_link_libraries(OrielOSUpdateSettings PUBLIC
    OrielOS::UpdateState
    Qt6::Core
    Qt6::DBus
    Qt6::Qml
    Qt6::Quick
    KF6::I18n
    KF6::CoreAddons
)

# The settings module. kcmutils_add_qml_kcm installs it to plasma/kcms/systemsettings, compiles
# ui/ into it and generates kcm_orielos_update.desktop, which opens it in System Settings.
kcmutils_add_qml_kcm(kcm_orielos_update SOURCES kcmupdate.cpp)
target_compile_definitions(kcm_orielos_update PRIVATE TRANSLATION_DOMAIN="kcm_orielos_update")
target_link_libraries(kcm_orielos_update PRIVATE
    OrielOSUpdateSettingsplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
    KF6::I18n
)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
