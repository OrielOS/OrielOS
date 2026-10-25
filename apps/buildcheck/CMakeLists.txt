# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# A minimal Kirigami app that proves the build and install path. It is hidden from menus
# and is replaced by the first real app.

add_executable(orielos-buildcheck main.cpp)

qt_add_qml_module(orielos-buildcheck
    URI org.orielos.buildcheck
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES systeminfo.cpp systeminfo.h
)

target_compile_definitions(orielos-buildcheck PRIVATE
    TRANSLATION_DOMAIN="orielos-buildcheck"
    ORIELOS_VERSION_STRING="${PROJECT_VERSION}"
)
target_link_libraries(orielos-buildcheck PRIVATE
    OrielOS::Common
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::I18n
    KF6::I18nQml
    KF6::CoreAddons
)

install(TARGETS orielos-buildcheck ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES org.orielos.BuildCheck.desktop DESTINATION ${KDE_INSTALL_APPDIR})

if(BUILD_TESTING)
    add_test(NAME buildcheck-selftest COMMAND orielos-buildcheck --self-test)
    set_tests_properties(buildcheck-selftest PROPERTIES PASS_REGULAR_EXPRESSION "orielos-buildcheck: self-test passed \\(")
endif()
