# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The test builds PowerSettings itself; the QML module's plugin can't be linked.
ecm_add_test(powersettingstest.cpp ../powersettings.cpp
    TEST_NAME powersettingstest
    LINK_LIBRARIES Qt6::Qml Qt6::Test KF6::I18n
)
target_include_directories(powersettingstest PRIVATE ..)
target_compile_definitions(powersettingstest PRIVATE TRANSLATION_DOMAIN="orielos-first-run")
