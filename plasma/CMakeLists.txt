# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# The Plasma widgets and KWin scripts will be added here.

# OrielOS's look-and-feel package, which lays out the Windows 11-style taskbar for new users.
install(DIRECTORY look-and-feel/org.orielos.desktop
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/look-and-feel)

# Update scripts move existing users' desktops to the current layout. Plasma runs each one once
# per user.
install(FILES updates/orielos-taskbar-1.js
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/shells/org.kde.plasma.desktop/contents/updates)

# The Start button's icon: the OrielOS logo placeholder.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/logo/orielos-logo-placeholder.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps
    RENAME orielos-start.svg)
