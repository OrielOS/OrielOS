# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Mouse pointer, under Accessibility in Settings: the pointer's colour and size.
qt_add_qml_module(OrielOSPointer STATIC
    URI org.orielos.pointer
    VERSION 1.0
    QML_FILES PointerPage.qml
    SOURCES pointerstyle.cpp pointerstyle.h
)
target_include_directories(OrielOSPointer PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSPointer PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSPointer PUBLIC Qt6::Core Qt6::Qml Qt6::Quick KF6::I18n KF6::ConfigCore)

kcmutils_add_qml_kcm(kcm_orielos_pointer SOURCES kcmpointer.cpp)
target_link_libraries(kcm_orielos_pointer PRIVATE
    OrielOSPointerplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
