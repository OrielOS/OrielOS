# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Settings, orielos-settings: a Qt Widgets window that hosts Plasma's settings modules, QML and Qt
# Widgets, and OrielOS's own, under categories in the order Windows Settings uses.

find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets)
find_package(KF6 6.0 REQUIRED COMPONENTS KCMUtils WidgetsAddons DBusAddons WindowSystem CoreAddons Runner KIO)

# The categories, pages and search, finding the modules, and the search Start and KRunner use,
# apart from the window, so the runner and the unit tests can use them. Position-independent,
# since the runner is a plugin.
add_library(OrielOSSettingsCatalogue STATIC
    pagecatalogue.cpp pagecatalogue.h
    modules.cpp modules.h
    settingssearch.cpp settingssearch.h
)
set_target_properties(OrielOSSettingsCatalogue PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(OrielOSSettingsCatalogue PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSSettingsCatalogue PRIVATE TRANSLATION_DOMAIN="orielos-settings")
target_link_libraries(OrielOSSettingsCatalogue PUBLIC Qt6::Core KF6::I18n KF6::CoreAddons)

add_executable(orielos-settings main.cpp settingswindow.cpp settingswindow.h)
target_compile_definitions(orielos-settings PRIVATE
    TRANSLATION_DOMAIN="orielos-settings"
    ORIELOS_VERSION_STRING="${PROJECT_VERSION}"
)
target_link_libraries(orielos-settings PRIVATE
    OrielOSSettingsCatalogue
    Qt6::Widgets
    Qt6::Qml
    KF6::I18n
    KF6::CoreAddons
    KF6::KCMUtils
    KF6::WidgetsAddons
    KF6::DBusAddons
    KF6::WindowSystem
)

install(TARGETS orielos-settings ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# kglobalaccel reads Win+I from the copy in its own folder; Start lists the other.
install(FILES org.orielos.Settings.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES org.orielos.Settings.desktop DESTINATION ${KDE_INSTALL_DATADIR}/kglobalaccel)

add_subdirectory(runner)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
