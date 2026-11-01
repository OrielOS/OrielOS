# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The first-run setup's bottom-left corner: accessibility, volume and the keyboard layout. It runs
# only in the setup's own session (image/system/usr/lib/tmpfiles.d/orielos-setup.conf).

find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(LayerShellQt 6.0 REQUIRED)

# What it reads from WirePlumber, unit-tested; the app compiles the same files into its QML module.
add_library(OrielOSSetupCorner STATIC setupcorner.cpp setupcorner.h)
target_include_directories(OrielOSSetupCorner PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSSetupCorner PUBLIC Qt6::Core Qt6::DBus Qt6::Qml)

add_executable(orielos-setup-corner main.cpp)

qt_add_qml_module(orielos-setup-corner
    URI org.orielos.setupcorner
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES setupcorner.cpp setupcorner.h
)

target_compile_definitions(orielos-setup-corner PRIVATE
    TRANSLATION_DOMAIN="orielos-first-run"
)
target_link_libraries(orielos-setup-corner PRIVATE
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::I18n
    KF6::I18nQml
    LayerShellQt::Interface
)

install(TARGETS orielos-setup-corner DESTINATION libexec)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
