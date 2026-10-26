# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The update state and its rules, which the update tray icon and the Update settings page share.

add_library(OrielOSUpdateState STATIC updatestate.cpp updatestate.h)
add_library(OrielOS::UpdateState ALIAS OrielOSUpdateState)
# The Update settings page links it into a shared object, its Plasma settings module.
set_target_properties(OrielOSUpdateState PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(OrielOSUpdateState PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSUpdateState PRIVATE TRANSLATION_DOMAIN="orielos-updates")
target_link_libraries(OrielOSUpdateState PUBLIC Qt6::Core KF6::I18n)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
