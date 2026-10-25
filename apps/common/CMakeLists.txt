# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

add_library(OrielOSCommon STATIC osrelease.cpp osrelease.h)
add_library(OrielOS::Common ALIAS OrielOSCommon)
target_include_directories(OrielOSCommon PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(OrielOSCommon PUBLIC Qt6::Core)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
