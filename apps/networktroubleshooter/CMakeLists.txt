# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The network troubleshooter: checks each part of the network connection in turn through
# /usr/libexec/orielos/network-check and fixes the first problem it finds. Quick Settings' menu on
# the taskbar opens it.

find_package(KF6 6.0 REQUIRED COMPONENTS DBusAddons)

# Reading network-check's results and choosing how to run a fix, unit-tested; the app compiles the
# same files into its QML module.
add_library(OrielOSNetworkCheck STATIC networkcheck.cpp networkcheck.h)
target_include_directories(OrielOSNetworkCheck PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSNetworkCheck PRIVATE TRANSLATION_DOMAIN="orielos-network-troubleshooter")
target_link_libraries(OrielOSNetworkCheck PUBLIC Qt6::Core Qt6::Qml KF6::I18n)

add_executable(orielos-network-troubleshooter main.cpp)
qt_add_qml_module(orielos-network-troubleshooter
    URI org.orielos.networktroubleshooter
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES networkcheck.cpp networkcheck.h
)
target_compile_definitions(orielos-network-troubleshooter PRIVATE TRANSLATION_DOMAIN="orielos-network-troubleshooter")
target_link_libraries(orielos-network-troubleshooter PRIVATE
    OrielOS::Common
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::DBusAddons
    KF6::I18n
    KF6::I18nQml
)

install(TARGETS orielos-network-troubleshooter ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES org.orielos.NetworkTroubleshooter.desktop DESTINATION ${KDE_INSTALL_APPDIR})

if(BUILD_TESTING)
    add_subdirectory(autotests)
    add_test(NAME networktroubleshooter-selftest COMMAND orielos-network-troubleshooter --self-test)
    set_tests_properties(networktroubleshooter-selftest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" PASS_REGULAR_EXPRESSION "self-test passed")
endif()
