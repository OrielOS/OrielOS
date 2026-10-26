# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(updatesettingstest.cpp
    TEST_NAME updatesettingstest
    LINK_LIBRARIES OrielOSUpdateSettings Qt6::Test
)

# Loads the built settings module the way System Settings does, from the build's plugin folder.
ecm_add_test(kcmloadtest.cpp
    TEST_NAME kcmloadtest
    LINK_LIBRARIES KF6::KCMUtilsQuick KF6::CoreAddons Qt6::Quick Qt6::Test
)
add_dependencies(kcmloadtest kcm_orielos_update)
set_tests_properties(kcmloadtest PROPERTIES
    ENVIRONMENT "QT_PLUGIN_PATH=$<TARGET_FILE_DIR:kcm_orielos_update>/../../..;QT_QPA_PLATFORM=offscreen"
)
