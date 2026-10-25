# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(updatestatetest.cpp
    TEST_NAME updatestatetest
    LINK_LIBRARIES OrielOSUpdateState Qt6::Test
)
