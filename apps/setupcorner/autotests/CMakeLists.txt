# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(setupcornertest.cpp
    TEST_NAME setupcornertest
    LINK_LIBRARIES OrielOSSetupCorner Qt6::Test
)
