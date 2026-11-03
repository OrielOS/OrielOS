# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(graphicscardtest.cpp
    TEST_NAME graphicscardtest
    LINK_LIBRARIES OrielOSTourCard Qt6::Test
)

ecm_add_test(appearancetest.cpp
    TEST_NAME appearancetest
    LINK_LIBRARIES OrielOSTourAppearance Qt6::Test
)
