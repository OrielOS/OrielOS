# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Sign-in options, under Accounts in Settings: the PIN (through OrielOS's PIN service), fingerprints,
# dynamic lock and the sign-in and lock screens' settings.
qt_add_qml_module(OrielOSSignIn STATIC
    URI org.orielos.signin
    VERSION 1.0
    QML_FILES SignInPage.qml
    SOURCES signinoptions.cpp signinoptions.h
)
target_include_directories(OrielOSSignIn PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(OrielOSSignIn PRIVATE TRANSLATION_DOMAIN="orielos-settings-pages")
target_link_libraries(OrielOSSignIn PUBLIC Qt6::Core Qt6::DBus Qt6::Network Qt6::Qml Qt6::Quick KF6::ConfigCore KF6::I18n)

kcmutils_add_qml_kcm(kcm_orielos_signin SOURCES kcmsignin.cpp)
target_link_libraries(kcm_orielos_signin PRIVATE
    OrielOSSignInplugin
    KF6::KCMUtilsQuick
    KF6::CoreAddons
)
