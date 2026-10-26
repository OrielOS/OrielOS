# plasma

OrielOS's layer for KDE Plasma: the taskbar, Start menu, shortcuts and look.

Contains:

- `startmenu/`: the Start menu, OrielOS's own Plasma widget (see [The Start menu](#the-start-menu)).
- `look-and-feel/org.orielos.desktop/`: OrielOS's look-and-feel package, which sets up OrielOS's taskbar for new users.
- `updates/`: desktop update scripts, which move existing users' desktops to the current layout.
- `firstrun/`: OrielOS's pages for the first-run setup, Plasma Setup: `network/`, which shows a computer without Wi-Fi whether its cable connection reaches the internet, and `power/`, which asks when the computer sleeps and the screen turns off. They are Plasma Setup packages; `image/README.md` describes the whole setup and its page order.

Will contain:

- KWin scripts, for example window snap layouts.

`CMakeLists.txt` installs them with OrielOS's apps; `tools/test-apps.sh` builds them, and the image build copies them in.

## The look-and-feel package

A Plasma 6 look-and-feel package (a "global theme"), installed to `/usr/share/plasma/look-and-feel/org.orielos.desktop`:

- `metadata.json`: its id, `org.orielos.desktop`, and name, OrielOS.
- `contents/defaults`: the settings applied when a user picks the theme in System Settings. For now they are Breeze's: Breeze colours, Plasma theme, icons, cursors and window decorations, with the OrielOS wallpaper (see [Wallpapers](#wallpapers)).
- `contents/layouts/org.kde.plasma.desktop-layout.js`: the layout script (below).

The lock screen, logout screen and splash screen come from Breeze, which Plasma falls back to when a look-and-feel package doesn't have its own.

`image/build/20-desktop.sh` makes it the default for every user with `LookAndFeelPackage=org.orielos.desktop` in the `[KDE]` group of `/etc/xdg/kdeglobals`. `/etc/xdg` comes before Fedora's `kde-settings` profile on `XDG_CONFIG_DIRS`, so this overrides Fedora's look-and-feel. `image/build/90-finalise.sh` fails the build if the setting, the package, the Start button's icon or the wallpapers are missing.

## The layout script

Plasma runs the default look-and-feel's layout script when a user logs in for the first time, that is, when there is no `~/.config/plasma-org.kde.plasma.desktop-appletsrc` yet. OrielOS's script keeps the desktop set-up from Breeze's own script, gives the desktop the OrielOS wallpaper and creates one taskbar:

- along the bottom of the screen, across its whole width, 48 pixels high at 100 % scale (the height people coming from Windows are used to), not floating;
- a flexible spacer, the Start button, the icons-only task manager and another flexible spacer: two flexible spacers centre the widgets between them on the panel;
- the system tray, which holds the notifications, network, sound and other status icons;
- the digital clock, with the date under the time;
- the show-desktop sliver at the far right.

The Start button is OrielOS's Start menu (`org.orielos.startmenu`, below) with the `orielos-start` icon: the OrielOS mark, three blue panes over an amber bar, drawn with wider gaps for taskbar sizes. Its source is `artwork/icons/orielos-start.svg`, and `CMakeLists.txt` installs it to `/usr/share/icons/hicolor/scalable/apps/`.

The task manager pins Files (`org.kde.dolphin.desktop`), Firefox (`org.mozilla.firefox.desktop`, exported by Flatpak once the first boot has installed it) and Store (`org.kde.discover.desktop`), in that order. It is set not to fill the panel, so the spacers can centre it.

Notifications pop up next to the notifications icon in the system tray, which is at the bottom right of the screen, so they appear at the bottom right like Windows' without any further setting.

To try a change without a new user, log in as a test user with no `plasma-org.kde.plasma.desktop-appletsrc`, or paste the script into Plasma's desktop scripting console on a running desktop, which adds a second panel next to the existing one.

## The Start menu

`startmenu/` is a Plasma 6 widget, `org.orielos.startmenu`, built with libplasma's `plasma_add_applet()`: its QML is compiled into `/usr/lib64/qt6/plugins/plasma/applets/org.orielos.startmenu.so`, and the app build runs qmllint over it with no warnings allowed. Its `metadata.json` says it provides `org.kde.plasma.launchermenu`, which is what Plasma's Win-key shortcut opens.

Pressing Win or clicking the Start button opens it:

- **Search** on top. Typing lists apps, settings, files, Store results and calculations, but runs nothing: only Enter, or a click, opens a result.
- **Pinned** apps in a grid, with an **All apps** list one click away.
- **Recommended:** apps installed in the last three days, then recently opened files. The widget's `showRecentlyAdded` and `showRecentFiles` settings, both on by default, leave either out; Settings' Start page changes them.
- **The account button** (picture and name) with Account settings, Lock, Switch user and Sign out, and **the power button** with Sleep, Restart and Shut down. There is no Hibernate: OrielOS doesn't offer hibernation.

Right-click an app, or press the Menu key, to pin it to or unpin it from Start. Everything works from the keyboard.

**Where it gets its data.** It uses the same models as Plasma's own launchers, from plasma-workspace's `org.kde.plasma.private.kicker` QML module, which is a private API:

- the app list, and when each app was first seen;
- the pinned apps;
- recent files;
- KRunner search;
- the session and power actions.

A Plasma update can change that API, so check the Start menu after every Plasma update; this one was written against Plasma 6.7.5.

**Pinned apps** are kept in the widget's own settings, the `favorites` key in the user's `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, so they survive restarts and OS updates. `main.xml` holds the default pins: Files, Firefox, Store, Settings, Konsole, Process Manager and Screenshot. A pinned app that isn't installed yet, such as Firefox before the first-boot install finishes, stays in the list and shows up as soon as it's installed.

## Wallpapers

`CMakeLists.txt` installs OrielOS's two Plasma wallpaper packages from `artwork/wallpapers/` to `/usr/share/wallpapers/`:

- `OrielOS`: a glass bay window on a warm sill, as Daybreak (light) and Nightfall (dark). It is the default.
- `OrielOS-Horizon`, shown as OrielOS Horizon: the same sky without the window, offered in the wallpaper picker.

Each package has a light image in `contents/images/` and a dark one in `contents/images_dark/`. When a desktop's wallpaper is the package rather than one of its images, Plasma shows the dark image with a dark colour scheme and the light one otherwise, and switches when the colour scheme changes: Daybreak with Breeze Light, Nightfall with Breeze Dark.

OrielOS is the default in three places:

- The layout script writes `Image=file:///usr/share/wallpapers/OrielOS/` to the `[Wallpaper][org.kde.image][General]` group of each new desktop, so a new user's `plasma-org.kde.plasma.desktop-appletsrc` names it.
- `[Wallpaper] Image=OrielOS` in `contents/defaults`. Plasma's image wallpaper shows the default look-and-feel's `[Wallpaper]` image on any desktop without an `Image` of its own, and System Settings applies it when a user picks the theme.
- `/etc/xdg/kscreenlockerrc`, from `image/system/etc/xdg/`, sets the lock screen's wallpaper the same way. Fedora's `kde-settings` profile names Fedora's wallpaper there, and `/etc/xdg` comes first on `XDG_CONFIG_DIRS`.

The login screen (SDDM) and the boot splash keep their own artwork for now.

## Update scripts

The layout script only runs for new users. To change the desktop of users who already have one, a release adds an update script to `updates/`. Plasma installs them to `/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/`, runs each script once per user when Plasma starts, and records the scripts it has run in `[Updates]` in `~/.config/plasmashellrc`, so a script never runs twice for the same user. Scripts use the same scripting API as the layout script, and what they `print` goes to `plasmashell`'s output. Plasma also runs them right after a layout script for a new user, so they must leave the current layout as it is.

- `orielos-startmenu-2.js` pins OrielOS's Settings app in place of System Settings in a user's Start menu, when they had System Settings pinned; Start menus on the default pins are left alone, since the default now pins Settings.
- `orielos-startmenu-1.js` replaces Plasma's launcher (Kickoff, Kicker or the application dashboard) on the default bottom panel with OrielOS's Start menu, in the same place. It keeps a custom launcher icon, replacing only Plasma's and Fedora's stock icons, and changes nothing on a panel that already has the Start menu. Plasma runs scripts in file-name order, so it runs before `orielos-taskbar-1.js`. The old launcher's pinned apps aren't carried over: the Start menu starts with OrielOS's default pins.
- `orielos-taskbar-1.js` moves the default bottom panel to the taskbar's widget order. It acts only when the user has exactly one bottom panel and it holds a launcher and a task manager; otherwise it logs why and changes nothing. It reuses the widgets already on the panel, adds only missing ones and keeps any others, just before the system tray, so nothing is duplicated or lost. It replaces the launcher's icon only if it is one of Plasma's or Fedora's stock icons, and leaves the pinned apps alone. On a panel that is already in order it changes nothing.

Rules for update scripts:

- Name them `orielos-<topic>-<n>.js`, numbering from 1, and add a new script for every change rather than editing a released one: Plasma would not run an edited script again for users who already ran it. Edit a released script only to keep it working with the current layout for the users who haven't run it yet. For example, `orielos-taskbar-1.js` now counts the Start menu as the launcher, so it leaves a new user's taskbar as it is.
- Make them safe to run on any desktop, including a brand-new one from the current layout script: check what is there, change only what needs changing and log what changed.
- Keep the layout script and the update scripts in step, so new and existing users end up with the same desktop.
- Add each script to `install(FILES ...)` in `CMakeLists.txt`.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
