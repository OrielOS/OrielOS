# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Set up this PC: the tour after an account's first sign-in (first-sign-in opens it once), and
# again from Start. Its choices go through Settings' own models: the taskbar's, the update
# channel's and the Store's apps.

find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets)
find_package(KF6 6.0 REQUIRED COMPONENTS DBusAddons Config KIO Service JobWidgets)

# The graphics card, read from sysfs, unit-tested; the app compiles the same files into its QML
# module.
add_library(OrielOSTourCard STATIC graphicscard.cpp graphicscard.h)
target_include_directories(OrielOSTourCard PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSTourCard PRIVATE TRANSLATION_DOMAIN="orielos-tour")
target_link_libraries(OrielOSTourCard PUBLIC Qt6::Core Qt6::Qml KF6::I18n)

# Light or dark, unit-tested the same way.
add_library(OrielOSTourAppearance STATIC appearance.cpp appearance.h)
target_include_directories(OrielOSTourAppearance PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSTourAppearance PRIVATE TRANSLATION_DOMAIN="orielos-tour")
target_link_libraries(OrielOSTourAppearance PUBLIC Qt6::Core Qt6::Qml KF6::ConfigCore KF6::I18n)

add_executable(orielos-tour main.cpp)
qt_add_qml_module(orielos-tour
    URI org.orielos.tour
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES
        appearance.cpp appearance.h
        graphicscard.cpp graphicscard.h
        launcher.cpp launcher.h
)
target_compile_definitions(orielos-tour PRIVATE TRANSLATION_DOMAIN="orielos-tour")
target_link_libraries(orielos-tour PRIVATE
    OrielOS::Common
    OrielOSTaskbarplugin
    OrielOSUpdateSettingsplugin
    OrielOSAccessoriesplugin
    Qt6::Widgets
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::ConfigCore
    KF6::CoreAddons
    KF6::DBusAddons
    KF6::I18n
    KF6::I18nQml
    KF6::KIOGui
    KF6::Service
    KF6::JobWidgets
)

install(TARGETS orielos-tour ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES org.orielos.Tour.desktop DESTINATION ${KDE_INSTALL_APPDIR})

if(BUILD_TESTING)
    add_subdirectory(autotests)
    add_test(NAME tour-selftest COMMAND orielos-tour --self-test)
    set_tests_properties(tour-selftest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" PASS_REGULAR_EXPRESSION "self-test passed")
endif()
