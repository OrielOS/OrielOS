# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(pagecataloguetest.cpp
    TEST_NAME pagecataloguetest
    LINK_LIBRARIES OrielOSSettingsCatalogue Qt6::Test
)

ecm_add_test(settingssearchtest.cpp
    TEST_NAME settingssearchtest
    LINK_LIBRARIES OrielOSSettingsCatalogue Qt6::Test
)

# Loads the built runner as Start and KRunner do. QT_PLUGIN_PATH adds the build's plugin folder,
# so OrielOS's own settings modules are found next to the system's.
ecm_add_test(settingsrunnertest.cpp
    TEST_NAME settingsrunnertest
    LINK_LIBRARIES KF6::Runner Qt6::Gui Qt6::Test
)
krunner_configure_test(settingsrunnertest krunner_orielos_settings)
add_dependencies(settingsrunnertest kcm_orielos_update kcm_orielos_accent kcm_orielos_accessories)
set_tests_properties(settingsrunnertest PROPERTIES
    ENVIRONMENT "QT_PLUGIN_PATH=$<TARGET_FILE_DIR:krunner_orielos_settings>/../..;QT_QPA_PLATFORM=offscreen"
)
