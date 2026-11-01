# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# Windows + .: the emoji panel, with emoji, kaomoji, symbols and the clipboard history. Its emoji
# come from Plasma's emoji selector (org.kde.plasma.emoji), so they're the same, with the same
# search words and recent emoji.

find_package(Qt6 6.8 REQUIRED COMPONENTS DBus)
find_package(KF6 6.0 REQUIRED COMPONENTS DBusAddons)

add_executable(orielos-emoji main.cpp)

qt_add_qml_module(orielos-emoji
    URI org.orielos.emojipanel
    VERSION 1.0
    QML_FILES qml/Main.qml qml/CharacterGrid.qml qml/characters.js
    SOURCES clipboardhistory.cpp clipboardhistory.h
)

target_compile_definitions(orielos-emoji PRIVATE
    TRANSLATION_DOMAIN="orielos-emoji"
)
target_link_libraries(orielos-emoji PRIVATE
    OrielOS::Common
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::DBusAddons
    KF6::I18n
    KF6::I18nQml
)

install(TARGETS orielos-emoji ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# Its desktop entry gives it Windows + .; kglobalaccel reads that from its own folder. NoDisplay
# keeps it out of Start.
install(FILES org.orielos.EmojiPanel.desktop DESTINATION ${KDE_INSTALL_APPDIR})
install(FILES org.orielos.EmojiPanel.desktop DESTINATION ${KDE_INSTALL_DATADIR}/kglobalaccel)
