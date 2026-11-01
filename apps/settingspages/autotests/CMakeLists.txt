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
# The anti-cheat self-test against a copy of a VM's files, recorded from the boot test.
ecm_add_test(securitycheckstest.cpp
    TEST_NAME securitycheckstest
    LINK_LIBRARIES OrielOSSecurity Qt6::Test
)

ecm_add_test(powermodetest.cpp
    TEST_NAME powermodetest
    LINK_LIBRARIES OrielOSPowerMode Qt6::Test
)

ecm_add_test(signinoptionstest.cpp
    TEST_NAME signinoptionstest
    LINK_LIBRARIES OrielOSSignIn Qt6::Test
)

ecm_add_test(multitaskingoptionstest.cpp
    TEST_NAME multitaskingoptionstest
    LINK_LIBRARIES OrielOSMultitasking Qt6::Test
)

ecm_add_test(pointerstyletest.cpp
    TEST_NAME pointerstyletest
    LINK_LIBRARIES OrielOSPointer Qt6::Test
)

ecm_add_test(storageusagetest.cpp
    TEST_NAME storageusagetest
    LINK_LIBRARIES OrielOSStorage Qt6::Test
)

ecm_add_test(dndscheduletest.cpp
    TEST_NAME dndscheduletest
    LINK_LIBRARIES OrielOSDoNotDisturb Qt6::Test
)

ecm_add_test(desktopbackgroundtest.cpp
    TEST_NAME desktopbackgroundtest
    LINK_LIBRARIES OrielOSBackground Qt6::Qml Qt6::Test
)
set_tests_properties(desktopbackgroundtest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

ecm_add_test(recentactivitytest.cpp
    TEST_NAME recentactivitytest
    LINK_LIBRARIES OrielOSRecentActivity Qt6::Test
)
set_tests_properties(recentactivitytest PROPERTIES ENVIRONMENT "LANGUAGE=en_GB;LC_ALL=en_GB.UTF-8")

# The font library needs a GUI application for Qt's font database.
ecm_add_test(fontlibrarytest.cpp
    TEST_NAME fontlibrarytest
    LINK_LIBRARIES OrielOSFonts Qt6::Test
)
set_tests_properties(fontlibrarytest PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

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
add_dependencies(pagesloadtest kcm_orielos_accessories kcm_orielos_accent kcm_orielos_start kcm_orielos_taskbar kcm_orielos_security kcm_orielos_powermode kcm_orielos_signin kcm_orielos_multitasking kcm_orielos_pointer kcm_orielos_storage kcm_orielos_fonts kcm_orielos_donotdisturb kcm_orielos_background kcm_orielos_recentactivity)
set_tests_properties(pagesloadtest PROPERTIES
    ENVIRONMENT "QT_PLUGIN_PATH=$<TARGET_FILE_DIR:kcm_orielos_accent>/../../..;QT_QPA_PLATFORM=offscreen"
)
