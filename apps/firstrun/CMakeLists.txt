# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module the first-run setup's power page saves through, org.orielos.firstrun. The page is
# a Plasma Setup package in plasma/firstrun; PowerSettings hands its choices to first-run-power.

ecm_add_qml_module(orielosfirstrun URI org.orielos.firstrun GENERATE_PLUGIN_SOURCE)
target_sources(orielosfirstrun PRIVATE powersettings.cpp powersettings.h)
target_compile_definitions(orielosfirstrun PRIVATE TRANSLATION_DOMAIN="orielos-first-run")
target_link_libraries(orielosfirstrun PRIVATE Qt6::Core Qt6::Qml KF6::I18n)
ecm_finalize_qml_module(orielosfirstrun)

if(BUILD_TESTING)
    add_subdirectory(autotests)
endif()
