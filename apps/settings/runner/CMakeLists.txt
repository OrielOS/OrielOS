# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# krunner_orielos_settings: finds settings for Start's search and KRunner, opening Settings' pages
# in Settings and other modules in System Settings.
kcoreaddons_add_plugin(krunner_orielos_settings SOURCES settingsrunner.cpp INSTALL_NAMESPACE "kf6/krunner")
target_compile_definitions(krunner_orielos_settings PRIVATE TRANSLATION_DOMAIN="orielos-settings")
target_link_libraries(krunner_orielos_settings PRIVATE
    OrielOSSettingsCatalogue
    KF6::Runner
    KF6::KIOGui
)
