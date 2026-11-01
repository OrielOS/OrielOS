# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(runtargettest.cpp
    TEST_NAME runtargettest
    LINK_LIBRARIES OrielOSRunTarget Qt6::Test
)
