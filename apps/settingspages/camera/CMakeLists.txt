# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Camera, under Devices in Settings: the cameras, with a live picture and brightness.
qt_add_qml_module(OrielOSCamera STATIC
    URI org.orielos.camera
    VERSION 1.0
    QML_FILES CameraPage.qml
)
target_compile_definitions(OrielOSCamera PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSCamera PUBLIC Qt6::Core Qt6::Qml Qt6::Quick)

kcmutils_add_qml_kcm(kcm_orielos_camera SOURCES kcmcamera.cpp)
target_link_libraries(kcm_orielos_camera PRIVATE
    OrielOSCameraplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
