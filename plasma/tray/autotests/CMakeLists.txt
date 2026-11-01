# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(traylogictest.cpp
    TEST_NAME traylogictest
    LINK_LIBRARIES orielostraylogic Qt6::Test
)
