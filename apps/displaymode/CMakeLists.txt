# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Windows + P: a panel to choose how the screens are used (this computer's screen only, duplicate,
# extend or the other screens only), applied through Plasma's screen configuration.

find_package(KF6 6.0 REQUIRED COMPONENTS DBusAddons)
find_package(KF6Screen 6.0 REQUIRED)
find_package(LayerShellQt 6.0 REQUIRED)

# Where each mode puts the screens, unit-tested.
add_library(OrielOSDisplayLayout STATIC displaylayout.cpp displaylayout.h)
target_include_directories(OrielOSDisplayLayout PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSDisplayLayout PUBLIC Qt6::Core)

add_executable(orielos-display-mode main.cpp)

qt_add_qml_module(orielos-display-mode
    URI org.orielos.displaymode
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES displayswitcher.cpp displayswitcher.h
)

target_compile_definitions(orielos-display-mode PRIVATE
    TRANSLATION_DOMAIN="orielos-display-mode"
)
target_link_libraries(orielos-display-mode PRIVATE
    OrielOS::Common
    OrielOSDisplayLayout
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::I18n
    KF6::I18nQml
    KF6::CoreAddons
    KF6::DBusAddons
    KF6::Screen
    LayerShellQt::Interface
)

install(TARGETS orielos-display-mode ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# Its desktop entry gives it Windows + P; kglobalaccel reads that from its own folder. NoDisplay
# keeps it out of Start.
install(FILES org.orielos.DisplayMode.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES org.orielos.DisplayMode.desktop DESTINATION ${KDE_INSTALL_DATADIR}/kglobalaccel)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
