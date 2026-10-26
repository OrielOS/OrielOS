# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# OrielOS's own settings pages, as Plasma settings modules that Settings hosts like Plasma's:
# Accessory apps (kcm_orielos_accessories), Accent colour (kcm_orielos_accent), Start
# (kcm_orielos_start) and Taskbar (kcm_orielos_taskbar). Each page and its model are a static QML
# module of their own, so qmllint checks the page and the unit tests can use the model; each
# settings module links its own. Two settings modules can't share one: Settings loads them all
# into one process, where a QML module can be registered only once. Everything linked into a
# settings module, the module's generated resource objects included, must be
# position-independent.

find_package(Qt6 6.8 REQUIRED COMPONENTS Gui DBus)
find_package(KF6 6.0 REQUIRED COMPONENTS KCMUtils Config)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_subdirectory(accessories)
add_subdirectory(accent)
# Start and Taskbar share the code that reads and changes the running desktop.
add_subdirectory(shell)
add_subdirectory(start)
add_subdirectory(taskbar)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
