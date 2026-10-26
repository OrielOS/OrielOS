# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Accessory apps: Solaar, Piper and OpenRGB from the Store, under Bluetooth & devices in Settings.
qt_add_qml_module(OrielOSAccessories STATIC
    URI org.orielos.accessories
    VERSION 1.0
    QML_FILES AccessoriesPage.qml
    SOURCES storeapps.cpp storeapps.h
)
target_include_directories(OrielOSAccessories PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSAccessories PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSAccessories PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_accessories SOURCES kcmaccessories.cpp)
target_link_libraries(kcm_orielos_accessories PRIVATE
    OrielOSAccessoriesplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
