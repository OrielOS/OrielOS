# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(gamestest.cpp
    TEST_NAME gamestest
    LINK_LIBRARIES OrielOSGames Qt6::Test
)
target_compile_definitions(gamestest PRIVATE ANTICHEAT_JSON="${PROJECT_SOURCE_DIR}/data/anticheat-games.json")
