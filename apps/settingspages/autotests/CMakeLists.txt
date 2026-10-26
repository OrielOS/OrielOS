# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

ecm_add_test(storeappstest.cpp
    TEST_NAME storeappstest
    LINK_LIBRARIES OrielOSAccessories Qt6::Test
)

ecm_add_test(accentcolourtest.cpp
    TEST_NAME accentcolourtest
    LINK_LIBRARIES OrielOSAccent Qt6::Test
)

# Runs the desktop script against a fake of Plasma's desktop scripting, and the models against a
# fake desktop.
ecm_add_test(shellsettingstest.cpp
    TEST_NAME shellsettingstest
    LINK_LIBRARIES OrielOSStart OrielOSTaskbar Qt6::Qml Qt6::Test
)

# Loads the built settings modules the way Settings and System Settings do, from the build's
# plugin folder, and fails on any QML warning.
ecm_add_test(pagesloadtest.cpp
    TEST_NAME pagesloadtest
    LINK_LIBRARIES KF6::KCMUtilsQuick KF6::CoreAddons Qt6::Quick Qt6::Test
)
add_dependencies(pagesloadtest kcm_orielos_accessories kcm_orielos_accent kcm_orielos_start kcm_orielos_taskbar)
set_tests_properties(pagesloadtest PROPERTIES
    ENVIRONMENT "QT_PLUGIN_PATH=$<TARGET_FILE_DIR:kcm_orielos_accent>/../../..;QT_QPA_PLATFORM=offscreen"
)
