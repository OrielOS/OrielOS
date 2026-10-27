# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(runapptest.cpp
    TEST_NAME runapptest
    LINK_LIBRARIES OrielOSRunApp Qt6::Test
)
