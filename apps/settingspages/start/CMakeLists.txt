# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Start, under Personalisation in Settings: what Start shows under Recommended.
qt_add_qml_module(OrielOSStart STATIC
    URI org.orielos.start
    VERSION 1.0
    QML_FILES StartPage.qml
    SOURCES startoptions.cpp startoptions.h
)
target_include_directories(OrielOSStart PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSStart PUBLIC OrielOSShellSettings Qt6::Core Qt6::Qml Qt6::Quick)

kcmutils_add_qml_kcm(kcm_orielos_start SOURCES kcmstart.cpp)
target_link_libraries(kcm_orielos_start PRIVATE
    OrielOSStartplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
