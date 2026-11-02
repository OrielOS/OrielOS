# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# FPS overlay, under Gaming in Settings: OrielOS's Game Bar, a frame-rate overlay that Windows + G
# shows over a game.
qt_add_qml_module(OrielOSFpsOverlay STATIC
    URI org.orielos.fpsoverlay
    VERSION 1.0
    QML_FILES FpsOverlayPage.qml
    SOURCES fpsoverlay.cpp fpsoverlay.h
)
target_include_directories(OrielOSFpsOverlay PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSFpsOverlay PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSFpsOverlay PUBLIC Qt6::Core Qt6::Qml Qt6::Quick KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_fpsoverlay SOURCES kcmfpsoverlay.cpp)
target_link_libraries(kcm_orielos_fpsoverlay PRIVATE
    OrielOSFpsOverlayplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
