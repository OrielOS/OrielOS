# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The administrator prompt: OrielOS's polkit authentication agent, laid out as Windows' prompt.

find_package(PolkitQt6-1 REQUIRED)
find_package(LayerShellQt 6.0 REQUIRED)

# What the prompt says about a request, unit-tested.
add_library(OrielOSPromptDetails STATIC promptdetails.cpp promptdetails.h)
target_include_directories(OrielOSPromptDetails PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSPromptDetails PUBLIC Qt6::Core)

add_executable(orielos-polkit-agent main.cpp)

qt_add_qml_module(orielos-polkit-agent
    URI org.orielos.polkitagent
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES agent.cpp agent.h
)

target_compile_definitions(orielos-polkit-agent PRIVATE
    TRANSLATION_DOMAIN="orielos-polkit-agent"
)
target_link_libraries(orielos-polkit-agent PRIVATE
    OrielOS::Common
    OrielOSPromptDetails
    PolkitQt6-1::Agent
    PolkitQt6-1::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::I18n
    KF6::I18nQml
    LayerShellQt::Interface
)

# /usr/libexec, where the agent's unit starts it (KDE's libexec folder is /usr/lib64/libexec).
install(TARGETS orielos-polkit-agent DESTINATION libexec)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
