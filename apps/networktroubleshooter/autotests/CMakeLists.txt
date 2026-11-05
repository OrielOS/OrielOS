# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(networkchecktest.cpp
    TEST_NAME networkchecktest
    LINK_LIBRARIES OrielOSNetworkCheck Qt6::Test
)
