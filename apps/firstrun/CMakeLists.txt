# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module the first-run setup's own pages use, org.orielos.firstrun. The pages are Plasma
# Setup packages in plasma/firstrun: PowerSettings hands the power page's choices to first-run-power,
# PrivacySettings the privacy page's to first-run-privacy, TimeZoneLookup finds the time zone page's
# zone from the network, and the updates page uses Settings' Update page model,
# org.orielos.updatesettings, linked in here.

find_package(Qt6 6.8 REQUIRED COMPONENTS Network)

ecm_add_qml_module(orielosfirstrun URI org.orielos.firstrun GENERATE_PLUGIN_SOURCE)
target_sources(orielosfirstrun PRIVATE powersettings.cpp powersettings.h privacysettings.cpp privacysettings.h timezonelookup.cpp
    timezonelookup.h updatesimport.cpp)
target_compile_definitions(orielosfirstrun PRIVATE TRANSLATION_DOMAIN="orielos-first-run")
target_link_libraries(orielosfirstrun PRIVATE Qt6::Core Qt6::Network Qt6::Qml KF6::I18n OrielOSUpdateSettingsplugin)
ecm_finalize_qml_module(orielosfirstrun)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
