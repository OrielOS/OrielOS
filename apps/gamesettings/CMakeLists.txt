# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Game Settings: the games in Steam from the Store, each with its compatibility tool and switches
# (DLSS upgrade, HDR, gamescope, the FPS overlay, GameMode, DX12 descriptor heaps), written into
# the game's launch options.

find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets Network)

# Reading and writing Steam's files, unit-tested.
add_library(OrielOSGames STATIC vdf.cpp vdf.h steamlibrary.cpp steamlibrary.h launchoptions.cpp launchoptions.h willitrun.cpp willitrun.h)
target_include_directories(OrielOSGames PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSGames PRIVATE TRANSLATION_DOMAIN="orielos-game-settings")
target_link_libraries(OrielOSGames PUBLIC Qt6::Core KF6::I18n)

add_executable(orielos-game-settings main.cpp)
qt_add_qml_module(orielos-game-settings
    URI org.orielos.gamesettings
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES gamesettings.cpp gamesettings.h
)
target_compile_definitions(orielos-game-settings PRIVATE TRANSLATION_DOMAIN="orielos-game-settings")
target_link_libraries(orielos-game-settings PRIVATE
    OrielOSGames
    Qt6::Widgets
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::I18n
    KF6::I18nQml
    KF6::CoreAddons
)

install(TARGETS orielos-game-settings ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES org.orielos.GameSettings.desktop DESTINATION ${KDE_INSTALL_APPDIR})
# Will it run?: AreWeAntiCheatYet's list (MIT), with its licence, and OrielOS's own verdicts.
install(FILES ${PROJECT_SOURCE_DIR}/data/anticheat-games.json ${PROJECT_SOURCE_DIR}/data/will-it-run-overrides.json
    ${PROJECT_SOURCE_DIR}/data/LICENSE-AreWeAntiCheatYet DESTINATION ${KDE_INSTALL_DATADIR}/orielos)

if(BUILD_TESTING)
    add_subdirectory(autotests)
    add_test(NAME gamesettings-selftest COMMAND orielos-game-settings --self-test)
    set_tests_properties(gamesettings-selftest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" PASS_REGULAR_EXPRESSION "self-test passed")
endif()
