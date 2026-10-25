# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# libplasma provides plasma_add_applet(), which builds a widget's QML into a plugin. Its CMake
# package needs KF6 Config to be found first.
find_package(KF6 6.0 REQUIRED COMPONENTS Config)
find_package(Plasma 6.0 REQUIRED)

# The Start menu widget.
add_subdirectory(startmenu)

# OrielOS's look-and-feel packages, which lay out OrielOS's taskbar for new users: OrielOS, in light
# colours, and OrielOS Dark, which has the same layout script.
install(DIRECTORY look-and-feel/org.orielos.desktop look-and-feel/org.orielos.desktop.dark
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/look-and-feel)
install(DIRECTORY look-and-feel/org.orielos.desktop/contents/layouts
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/look-and-feel/org.orielos.desktop.dark/contents)

# OrielOS's colour schemes, which the look-and-feel packages choose.
install(FILES color-schemes/OrielOSLight.colors color-schemes/OrielOSDark.colors
    DESTINATION ${KDE_INSTALL_DATADIR}/color-schemes)

# Update scripts move existing users' desktops to the current layout. Plasma runs each one once
# per user, in file-name order, so the Start menu replaces the old launcher before the taskbar is
# put in order.
install(FILES updates/orielos-startmenu-1.js updates/orielos-taskbar-1.js
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/shells/org.kde.plasma.desktop/contents/updates)

# The boot splash's logo, for the Plymouth theme in image/system/usr/share/plymouth/themes/orielos.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/splash/orielos-splash-white.png
    DESTINATION ${KDE_INSTALL_DATADIR}/plymouth/themes/orielos RENAME watermark.png)

# The Start button's icon: the OrielOS mark, drawn with wider gaps for taskbar sizes.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/icons/orielos-start.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# OrielOS's wallpapers: OrielOS (Daybreak and Nightfall), the default set by the look-and-feel
# package, and OrielOS Horizon. Plasma shows the dark image when the colour scheme is dark.
install(DIRECTORY
    ${PROJECT_SOURCE_DIR}/artwork/wallpapers/OrielOS
    ${PROJECT_SOURCE_DIR}/artwork/wallpapers/OrielOS-Horizon
    DESTINATION ${KDE_INSTALL_WALLPAPERDIR})
