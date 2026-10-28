# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# libplasma provides plasma_add_applet(), which builds a widget's QML into a plugin. Its CMake
# package needs KF6 Config to be found first.
find_package(KF6 6.0 REQUIRED COMPONENTS Config)
find_package(Plasma 6.0 REQUIRED)

# The Start menu widget.
add_subdirectory(startmenu)

# OrielOS's wording for some of Plasma's own text, such as "Pin to taskbar" in the taskbar's menu,
# as catalogues for the language en@orielos, which
# image/system/etc/xdg/plasma-workspace/env/orielos-wording.sh puts first for English.
ki18n_install(translations)

# Snap layouts: a KWin effect that Win+Z opens, to snap the active window into a layout.
install(DIRECTORY kwin/snaplayouts/ DESTINATION ${KDE_INSTALL_DATADIR}/kwin/effects/orielos-snaplayouts)

# The first-run setup's network page, for computers without Wi-Fi, and its power page, as Plasma
# Setup packages. image/build/41-first-run.sh puts every page in order and shows this logo on the
# last one.
install(DIRECTORY firstrun/network/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/packages/org.orielos.plasmasetup.network)
install(DIRECTORY firstrun/power/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/packages/org.orielos.plasmasetup.power)
install(FILES ${PROJECT_SOURCE_DIR}/artwork/splash/orielos-splash.png
    DESTINATION ${KDE_INSTALL_DATADIR}/orielos/first-run RENAME finished-logo.png)

# OrielOS's own shell, org.orielos.desktop: the desktop and taskbar layout, the lock screen and the
# script that carries a user's earlier desktop over. Plasma takes every file it doesn't have from
# its own desktop shell. /etc/xdg/plasmashellrc makes it the default.
install(DIRECTORY shell/org.orielos.desktop DESTINATION ${KDE_INSTALL_DATADIR}/plasma/shells)

# OrielOS's Plasma theme, orielos, in Sill's look: the taskbar, pop-ups, tooltips and task buttons.
# desktoptheme/src/generate.py writes its SVGs; any file it doesn't have comes from Breeze.
# /etc/xdg/plasmarc makes it the default.
install(DIRECTORY desktoptheme/orielos DESTINATION ${KDE_INSTALL_DATADIR}/plasma/desktoptheme)

# The taskbar's Search and Task View buttons, QML-only Plasma widgets.
install(DIRECTORY plasmoids/org.orielos.search plasmoids/org.orielos.taskview DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids)

# OrielOS's look-and-feel packages: OrielOS, in light colours, and OrielOS Dark. Their layout is the
# shell's own, so applying either with its desktop layout gives the OrielOS taskbar, whether Plasma
# looks it up for the OrielOS shell or for its own desktop shell.
install(DIRECTORY look-and-feel/org.orielos.desktop look-and-feel/org.orielos.desktop.dark
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/look-and-feel)
foreach(lnf org.orielos.desktop org.orielos.desktop.dark)
    foreach(shell org.orielos.desktop org.kde.plasma.desktop)
        install(FILES shell/org.orielos.desktop/contents/layout.js
            DESTINATION ${KDE_INSTALL_DATADIR}/plasma/look-and-feel/${lnf}/contents/layouts
            RENAME ${shell}-layout.js)
    endforeach()
endforeach()

# OrielOS's colour schemes, which the look-and-feel packages choose.
install(FILES color-schemes/OrielOSLight.colors color-schemes/OrielOSDark.colors
    DESTINATION ${KDE_INSTALL_DATADIR}/color-schemes)

# Update scripts move existing users' desktops to the current layout. Plasma runs each one once
# per user, in file-name order, so the Start menu replaces the old launcher before the taskbar is
# put in order. They are for Plasma's desktop shell, which OrielOS no longer uses by default; they
# stay for anyone who switches back to it. The OrielOS shell's own are in its package.
install(FILES updates/orielos-startmenu-1.js updates/orielos-startmenu-2.js updates/orielos-taskbar-1.js
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/shells/org.kde.plasma.desktop/contents/updates)

# The boot splash's logo, for the Plymouth theme in image/system/usr/share/plymouth/themes/orielos.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/splash/orielos-splash-white.png
    DESTINATION ${KDE_INSTALL_DATADIR}/plymouth/themes/orielos RENAME watermark.png)

# The Start button's icon: the OrielOS mark, drawn with wider gaps for taskbar sizes.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/icons/orielos-start.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# OrielOS's logo as an icon, which os-release's LOGO names: About this System and other tools that
# show the system's logo use it.
install(FILES ${PROJECT_SOURCE_DIR}/artwork/logo/orielos-mark.svg
    DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps RENAME orielos-logo-icon.svg)

# OrielOS's wallpapers: OrielOS (Daybreak and Nightfall), the default set by the look-and-feel
# package, and OrielOS Horizon. Plasma shows the dark image when the colour scheme is dark.
install(DIRECTORY
    ${PROJECT_SOURCE_DIR}/artwork/wallpapers/OrielOS
    ${PROJECT_SOURCE_DIR}/artwork/wallpapers/OrielOS-Horizon
    DESTINATION ${KDE_INSTALL_WALLPAPERDIR})

# OrielOS's sound theme, which the image makes the default. It inherits Plasma's Ocean theme for
# the sounds it doesn't have.
install(DIRECTORY ${PROJECT_SOURCE_DIR}/artwork/sounds/orielos DESTINATION ${KDE_INSTALL_SOUNDDIR})
