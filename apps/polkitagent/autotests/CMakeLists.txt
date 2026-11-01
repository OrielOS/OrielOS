# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(promptdetailstest.cpp
    TEST_NAME promptdetailstest
    LINK_LIBRARIES OrielOSPromptDetails Qt6::Test
)
