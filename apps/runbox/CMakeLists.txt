# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Windows + R: the Run box, which opens a program, folder, document or website typed into it.

find_package(KF6 6.0 REQUIRED COMPONENTS Config DBusAddons KIO)

# What it does with what was typed, unit-tested.
add_library(OrielOSRunTarget STATIC runtarget.cpp runtarget.h)
target_include_directories(OrielOSRunTarget PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSRunTarget PUBLIC Qt6::Core)

add_executable(orielos-run main.cpp)

qt_add_qml_module(orielos-run
    URI org.orielos.runbox
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES runbox.cpp runbox.h
)

target_compile_definitions(orielos-run PRIVATE
    TRANSLATION_DOMAIN="orielos-run"
)
target_link_libraries(orielos-run PRIVATE
    OrielOS::Common
    OrielOSRunTarget
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::ConfigCore
    KF6::CoreAddons
    KF6::DBusAddons
    KF6::I18n
    KF6::I18nQml
    KF6::KIOGui
)

install(TARGETS orielos-run ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# Its desktop entry gives it Windows + R; kglobalaccel reads that from its own folder. NoDisplay
# keeps it out of Start.
install(FILES org.orielos.Run.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES org.orielos.Run.desktop DESTINATION ${KDE_INSTALL_DATADIR}/kglobalaccel)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
