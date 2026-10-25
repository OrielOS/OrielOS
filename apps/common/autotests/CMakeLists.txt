# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(osreleasetest.cpp
    TEST_NAME osreleasetest
    LINK_LIBRARIES OrielOS::Common Qt6::Test
)
