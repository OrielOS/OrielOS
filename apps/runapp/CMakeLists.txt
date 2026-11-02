# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Run this app: opens Windows programs (.exe and .msi), asks first, runs them through
# umu-launcher with GE-Proton in a prefix of their own and adds their Start entries.

# What it does apart from its window, unit-tested.
add_library(OrielOSRunApp STATIC runapp.cpp runapp.h)
add_library(OrielOS::RunApp ALIAS OrielOSRunApp)
target_include_directories(OrielOSRunApp PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSRunApp PRIVATE TRANSLATION_DOMAIN="orielos-run-app")
target_link_libraries(OrielOSRunApp PUBLIC Qt6::Core KF6::I18n)

add_executable(orielos-run-app main.cpp)

qt_add_qml_module(orielos-run-app
    URI org.orielos.runapp
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES runner.cpp runner.h
)

target_compile_definitions(orielos-run-app PRIVATE
    TRANSLATION_DOMAIN="orielos-run-app"
)
find_package(Qt6 6.8 REQUIRED COMPONENTS Network)
target_link_libraries(orielos-run-app PRIVATE
    OrielOS::Common
    OrielOS::RunApp
    Qt6::Gui
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::I18n
    KF6::I18nQml
    KF6::CoreAddons
)

install(TARGETS orielos-run-app ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# The image makes it the default for Windows programs (image/build/40-apps.sh); NoDisplay keeps it
# out of Start.
install(FILES org.orielos.RunApp.desktop DESTINATION ${KDE_INSTALL_APPDIR})
# The known-apps list; a newer copy is fetched from OrielOS's repository when online.
install(FILES ${PROJECT_SOURCE_DIR}/data/known-apps.json DESTINATION ${KDE_INSTALL_DATADIR}/orielos)

if(BUILD_TESTING)
    add_subdirectory(autotests)
    add_test(NAME runapp-selftest COMMAND orielos-run-app --self-test)
    set_tests_properties(runapp-selftest PROPERTIES PASS_REGULAR_EXPRESSION "orielos-run-app: self-test passed \\(")
endif()
