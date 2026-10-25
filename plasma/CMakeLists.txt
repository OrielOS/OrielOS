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

# The Start button's icon: the OrielOS mark, drawn with wider gaps for taskbar sizes.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/icons/orielos-start.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# OrielOS's wallpapers: OrielOS (Daybreak and Nightfall), the default set by the look-and-feel
# package, and OrielOS Horizon. Plasma shows the dark image when the colour scheme is dark.
install(DIRECTORY
    ${PROJECT_SOURCE_DIR}/artwork/wallpapers/OrielOS
    ${PROJECT_SOURCE_DIR}/artwork/wallpapers/OrielOS-Horizon
    DESTINATION ${KDE_INSTALL_WALLPAPERDIR})
