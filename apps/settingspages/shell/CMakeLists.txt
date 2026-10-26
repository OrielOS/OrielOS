# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Start's and the taskbar's settings in the running desktop, read and changed through Plasma's
# desktop scripting. Plain C++, shared by the Start and Taskbar pages' QML modules.
add_library(OrielOSShellSettings STATIC shellsettings.cpp shellsettings.h)
target_include_directories(OrielOSShellSettings PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSShellSettings PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSShellSettings PUBLIC Qt6::Core Qt6::DBus KF6::I18n)
