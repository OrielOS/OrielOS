# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Storage, under System in Settings: what fills the disk, clean-up and Storage Sense.
qt_add_qml_module(OrielOSStorage STATIC
    URI org.orielos.storage
    VERSION 1.0
    QML_FILES StoragePage.qml
    SOURCES storageusage.cpp storageusage.h
)
target_include_directories(OrielOSStorage PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSStorage PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSStorage PUBLIC Qt6::Core Qt6::Gui Qt6::Concurrent Qt6::Qml Qt6::Quick KF6::I18n KF6::ConfigCore)

kcmutils_add_qml_kcm(kcm_orielos_storage SOURCES kcmstorage.cpp)
target_link_libraries(kcm_orielos_storage PRIVATE
    OrielOSStorageplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
