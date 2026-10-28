# plasma

OrielOS's layer for KDE Plasma: OrielOS's own shell, the taskbar, Start menu, shortcuts and look.

Contains:

- `shell/`: OrielOS's own shell, `org.orielos.desktop`, which Plasma runs in place of its desktop shell: the desktop and taskbar layout, the lock screen and the move from an earlier desktop (see [The OrielOS shell](#the-orielos-shell)).
- `startmenu/`: the Start menu, OrielOS's own Plasma widget (see [The Start menu](#the-start-menu)).
- `desktoptheme/`: OrielOS's Plasma theme, `orielos`, and the script that writes it (see [The Plasma theme](#the-plasma-theme)).
- `look-and-feel/org.orielos.desktop/` and `look-and-feel/org.orielos.desktop.dark/`: OrielOS's look-and-feel packages, light and dark.
- `color-schemes/`: OrielOS's colour schemes, OrielOS Light and OrielOS Dark (see [Colour schemes](#colour-schemes)).
- `updates/`: update scripts for Plasma's desktop shell, from before the OrielOS shell.
- `firstrun/`: OrielOS's pages for the first-run setup, Plasma Setup: `network/`, which shows a computer without Wi-Fi whether its cable connection reaches the internet, and `power/`, which asks when the computer sleeps and the screen turns off. They are Plasma Setup packages; `image/README.md` describes the whole setup and its page order.
- `kwin/snaplayouts/`: the snap layouts picker, a KWin effect (see [Snap layouts](#snap-layouts)).

`CMakeLists.txt` installs them with OrielOS's apps; `tools/test-apps.sh` builds them, and the image build copies them in.

## The OrielOS shell

`shell/org.orielos.desktop/` is OrielOS's own Plasma shell package, installed to `/usr/share/plasma/shells/`. `plasmashell` loads it in place of Plasma's desktop shell (`org.kde.plasma.desktop`), the way Plasma Mobile and Plasma Bigscreen are built, and takes every file the package doesn't have from Plasma's desktop shell, so OrielOS replaces the desktop one part at a time. KWin and Plasma's services stay as they are.

- `metadata.json`: the package, `org.orielos.desktop`, with Plasma's desktop shell as its fallback.
- `contents/layout.js`: the layout for a new desktop (see [The layout script](#the-layout-script)).
- `contents/defaults`: Plasma's desktop shell defaults with OrielOS's desktop menu on the desktop's right button.
- `contents/lockscreen/`: the lock screen, a full copy of plasma-desktop 6.7.5's with OrielOS's `LockScreenUi.qml`, whose time and date sit under the sill of the OrielOS wallpaper while the screen is idle, in ink on Daybreak and white on Nightfall, and fade out while the user unlocks. The whole folder is copied because its files load each other by relative path. `shell/upstream.sha256` lists the checksums of the Plasma files the copies here are based on; `image/build/27-shell.sh` stops the build when Plasma's change, so the copy is rebased on them.
- `contents/applet/CompactApplet.qml`: the popup of a widget on the taskbar, plasma-desktop 6.7.5's with three changes: popups float 12 px above the taskbar with all their corners rounded, a widget whose root item declares `centredPopup: true` (Start) opens in the middle of the taskbar instead of over itself, and an open widget is lit by a rounded highlight instead of Plasma's tab. Plasma's other `applet/` files are used as they are.
- `contents/updates/orielos-desktop-1.js`: carries a user's earlier desktop over (see [Update scripts](#update-scripts)).
- `contents/updates/orielos-buttons-1.js`: adds the Search and Task View buttons after Start on taskbars made before they existed.
- `contents/updates/orielos-sliver-1.js`: swaps Plasma's Show Desktop button for OrielOS's show desktop sliver.
- `contents/updates/orielos-desktop-icons-1.js`: arranges the desktop's icons in columns and gives its right button OrielOS's menu.
- `contents/updates/orielos-clock-1.js`: swaps Plasma's digital clock for the clock and bell, and moves the notifications icon among the hidden icons.
- `contents/updates/orielos-quicksettings-1.js`: adds Quick Settings after the tray and moves the icons it covers among the tray's hidden icons.

**Which shell runs.** `plasmashell` and the lock screen read `ShellPackage` from `[Shell]` in `plasmashellrc`, then `PLASMA_DEFAULT_SHELL`, then use `org.kde.plasma.desktop`. The image's `/etc/xdg/plasmashellrc` names `org.orielos.desktop`, and `/etc/xdg/plasma-workspace/env/orielos-shell.sh` sets `PLASMA_DEFAULT_SHELL` to it too, because applying a global theme can write an empty `ShellPackage` into the user's own `plasmashellrc`, and an empty value falls through to `PLASMA_DEFAULT_SHELL` rather than to `/etc/xdg`.

**Each shell has its own desktop file.** Plasma keeps a shell's desktop in `~/.config/plasma-<shell>-appletsrc`: the OrielOS shell's is `plasma-org.orielos.desktop-appletsrc`, and Plasma's desktop shell's, which OrielOS used until now, `plasma-org.kde.plasma.desktop-appletsrc`. The OrielOS shell only reads the old file, once.

**Updating and going back.** Both settings are in `/etc`, and each OrielOS version has its own `/etc`, so going back to a version from before the OrielOS shell starts Plasma's desktop shell with the user's old desktop exactly as they left it; updating again brings back the OrielOS shell with its own desktop.

**Trying a change.** Restarting `plasmashell` (`plasmashell --replace`) loads the package's files again. For a new desktop, sign in as a test user with no `plasma-org.orielos.desktop-appletsrc`. Update scripts only run from a folder outside the home folder: Plasma ignores any under `~/.local/share`.

`image/build/90-finalise.sh` fails the build if the package, its layout, lock screen or update script, or either default is missing.

## The Plasma theme

`desktoptheme/orielos/` is OrielOS's Plasma theme ("desktop theme"), installed to `/usr/share/plasma/desktoptheme/` and made the default by `/etc/xdg/plasmarc` and both look-and-feel packages. It draws the taskbar, pop-ups (Start, the tray's pop-ups, notifications, the calendar, menus), tooltips and task buttons in Sill's look:

- **Pop-ups** are panes with 8 px corners, a thin light rim and a soft shadow, translucent over Plasma's blur (`translucent/`) or nearly opaque without it.
- **The taskbar** is a translucent bar with a hairline along its top.
- **Task buttons:** the app in use has a soft highlight and the sill, a Daylight line under its icon; other running apps get a short grey dash; hovering highlights; an app asking for attention is tinted.

Colours come from the colour scheme (Plasma's `ColorScheme-*` classes), so the theme is dark with OrielOS Dark and light with OrielOS Light; Daylight is the one fixed colour. `desktoptheme/src/generate.py` writes every SVG from a few numbers (corner sizes, opacities, shadow depths): change it and run it again rather than editing the SVGs. Files the theme doesn't have come from Breeze.

## The look-and-feel packages

Two Plasma 6 look-and-feel packages ("global themes"), installed to `/usr/share/plasma/look-and-feel/`:

- `org.orielos.desktop`, named OrielOS, and `org.orielos.desktop.dark`, named OrielOS Dark.
- `contents/defaults`: the settings applied when a user picks the theme in System Settings: OrielOS Light or OrielOS Dark colours, Breeze's or Breeze Dark's icons, and Breeze's widget style, Plasma theme, cursors and window decorations, with the OrielOS wallpaper (see [Wallpapers](#wallpapers)), which shows Nightfall with the dark colours.
- `contents/layouts/`: the shell's layout script (below), which `CMakeLists.txt` installs into both packages as `org.orielos.desktop-layout.js` and `org.kde.plasma.desktop-layout.js`, so applying either theme with its desktop layout gives the OrielOS taskbar under either shell.

The logout screen and splash screen come from Breeze, which Plasma falls back to when a look-and-feel package doesn't have its own; the lock screen comes from the OrielOS shell.

OrielOS is dark by default: `image/build/20-desktop.sh` makes OrielOS Dark the default for every user with `LookAndFeelPackage=org.orielos.desktop.dark` in the `[KDE]` group of `/etc/xdg/kdeglobals`, with Breeze's dark icons, and `image/build/90-finalise.sh` copies OrielOS Dark's colours into the same file, because apps read the colours themselves, not the scheme's name. Choosing light in Settings writes the user's own. 20-desktop.sh also makes the two packages Plasma's light and dark choices for the Day-Night Cycle (`DefaultLightLookAndFeel` and `DefaultDarkLookAndFeel`). `/etc/xdg` comes before Fedora's `kde-settings` profile on `XDG_CONFIG_DIRS`, so this overrides Fedora's look-and-feel. `image/build/90-finalise.sh` fails the build if the settings, the packages, the colour schemes, the Start button's icon or the wallpapers are missing.

## Colour schemes

`color-schemes/OrielOSLight.colors` and `OrielOSDark.colors` are KDE colour schemes, installed to `/usr/share/color-schemes/`. They have the structure of Breeze's light and dark schemes (LGPL-2.0-or-later, so they keep that licence and Breeze's authors) with OrielOS's palette from its brand guidelines:

- **Light:** Ink text (`#121A2E`), Slate for secondary text (`#5B6478`), Mist (`#F4F6FB`) for windows and white for views, and Oriel Blue (`#3A66F0`) for focus, links and the selection, with white selected text.
- **Dark:** near-white text on cool dark greys drawn from Night (`#1A1F2E` windows, `#121622` views), Pane (`#6D97FA`) for focus, Glass (`#9CC2FF`) for links, and the same Oriel Blue selection.
- **Both:** Night (`#0C1530`) for the complementary areas, such as on-screen displays.

All text is at least 4.5:1 against its background: Ink on Mist is 16:1, Slate on Mist 5.5:1, white on Oriel Blue and Oriel Blue links on white 4.8:1; in the dark scheme, text on windows is 14.5:1, secondary text 6.5:1 and Glass links on views 9.9:1.

Plasma Setup's Dark Theme switch still applies Breeze or Breeze Dark; the first-run setup's own pages replace it.

## The layout script

`shell/org.orielos.desktop/contents/layout.js` runs when the OrielOS shell starts with no desktop yet, that is, when there is no `~/.config/plasma-org.orielos.desktop-appletsrc`: for a new user, and once for someone updating from a version with Plasma's desktop shell, whose pins and wallpaper the update script then copies. (Plasma would run a look-and-feel's `layouts/org.orielos.desktop-layout.js` first; OrielOS's is the same file.) OrielOS's script keeps the desktop set-up from Breeze's own script, gives the desktop the OrielOS wallpaper and creates one taskbar:

- along the bottom of the screen, across its whole width, 48 pixels high at 100 % scale (the height people coming from Windows are used to), not floating;
- a flexible spacer, the Start button, the icons-only task manager and another flexible spacer: two flexible spacers centre the widgets between them on the panel;
- the system tray, which holds the notifications, network, sound and other status icons;
- the digital clock, with the date under the time;
- the show-desktop sliver at the far right.

The Start button is OrielOS's Start menu (`org.orielos.startmenu`, below) with the `orielos-start` icon: the OrielOS mark, three blue panes over an amber bar, drawn with wider gaps for taskbar sizes. Its source is `artwork/icons/orielos-start.svg`, and `CMakeLists.txt` installs it to `/usr/share/icons/hicolor/scalable/apps/`.

The task manager pins Files (`org.kde.dolphin.desktop`), Firefox (`org.mozilla.firefox.desktop`, exported by Flatpak once the first boot has installed it) and Store (`org.kde.discover.desktop`), in that order. It is set not to fill the panel, so the spacers can centre it.

Notifications pop up next to the notifications icon in the system tray, which is at the bottom right of the screen, so they appear at the bottom right like Windows' without any further setting.

To try a change without a new user, log in as a test user with no `plasma-org.orielos.desktop-appletsrc`, or paste the script into Plasma's desktop scripting console on a running desktop, which adds a second panel next to the existing one.

## The Start menu

`startmenu/` is a Plasma 6 widget, `org.orielos.startmenu`, built with libplasma's `plasma_add_applet()`: its QML is compiled into `/usr/lib64/qt6/plugins/plasma/applets/org.orielos.startmenu.so`, and the app build runs qmllint over it with no warnings allowed. Its `metadata.json` says it provides `org.kde.plasma.launchermenu`, which is what Plasma's Win-key shortcut opens.

Pressing Win or clicking the Start button opens it:

- **Search** on top. Typing lists apps, settings, files, Store results and calculations, but runs nothing: only Enter, or a click, opens a result.
- **Pinned** apps in a grid, with an **All apps** list one click away.
- **Recommended:** apps installed in the last three days, then recently opened files, then the Get started suggestions, six entries at most. The suggestions are the Flathub apps listed in `startmenu/getstarted.js` that aren't installed (no desktop entry `<Flathub ID>.desktop` among the apps Kicker lists). Each opens `appstream://<Flathub ID>`, which the Store handles by showing the app's page; nothing is installed until the user chooses Install there. Their icons are Flathub's, from `/var/lib/flatpak/appstream/flathub/x86_64/active/icons/128x128/`, once the Store has fetched Flathub's catalogue, and the Store's icon until then. "Hide these suggestions" in an entry's context menu sets `getStartedHidden` in the widget's settings. The widget's `showRecentlyAdded` and `showRecentFiles` settings, both on by default, leave either out; Settings' Start page changes them.
- **The account button** (picture and name) with Account settings, Lock, Switch user and Sign out, and **the power button** with Sleep, Restart and Shut down. There is no Hibernate: OrielOS doesn't offer hibernation.

Right-click an app, or press the Menu key, to pin it to or unpin it from Start. Everything works from the keyboard.

**Where it gets its data.** It uses the same models as Plasma's own launchers, from plasma-workspace's `org.kde.plasma.private.kicker` QML module, which is a private API:

- the app list, and when each app was first seen;
- the pinned apps;
- recent files;
- KRunner search;
- the session and power actions.

A Plasma update can change that API, so check the Start menu after every Plasma update; this one was written against Plasma 6.7.5.

**Pinned apps** are kept in the widget's own settings, the `favorites` key in the user's `~/.config/plasma-org.orielos.desktop-appletsrc`, so they survive restarts and OS updates. `main.xml` holds the default pins: Files, Firefox, Store, Settings, Konsole, Process Manager and Screenshot. A pinned app that isn't installed yet, such as Firefox before the first-boot install finishes, stays in the list and shows up as soon as it's installed.

## Taskbar widgets

QML-only Plasma widgets in `plasmoids/`, installed to `/usr/share/plasma/plasmoids/`. Plasma draws a widget's own taskbar button from its full representation when it has no popup, so the three buttons without one use `preferredRepresentation: fullRepresentation`.

- `org.orielos.search`: the Search button after Start; opens Start with the search field ready.
- `org.orielos.taskview`: the Task View button (KWin's Overview), with the short line that sets the apps apart after it.
- `org.orielos.showdesktop`: the show desktop sliver at the far end of the taskbar (KWin's Show Desktop).
- `org.orielos.quicksettings`: Quick Settings, between the hidden icons and the clock: one button with the network, volume and battery icons, opening the panel of what's playing, tiles for Wi-Fi, Bluetooth, airplane mode, energy saver, night light and accessibility, the brightness and volume sliders, and the battery. It uses the same Plasma services as Plasma's own network, sound, Bluetooth, power, brightness and media widgets (their QML modules, some of them private to Plasma, so a Plasma update can change them: check Quick Settings after one). Those widgets stay loaded among the hidden icons because the volume and media keys belong to them. The wheel over the button changes the volume by 2 %.
- `org.orielos.clock`: the clock and the bell at the end of the taskbar, the time over the date and the bell with the number of new notifications (or Do not disturb's bell). Either opens the notification centre: the history, newest first, with Do not disturb and Clear all, over the month's calendar with a 30-minute focus session (Do not disturb for half an hour). Sill draws these as two cards with a gap, which Plasma's popups (always one pane) can't, so the widget opens a window of its own with no pane. It reads the same history as Plasma's notifications widget, with the same "don't keep in history" settings, which by default leave out apps with no desktop entry (`@other`); Plasma's widget stays loaded among the hidden icons for the pop-ups.

OrielOS's own line icons for these, drawn like Breeze's where Breeze has none in OrielOS's style, are in `artwork/icons/*-symbolic.svg` and installed to `hicolor/scalable/actions`.

## The desktop

The desktop is Plasma's folder view (`org.kde.plasma.folder`), with icons in columns from the top left as Windows arranges them (`arrangement=1`, set by the layout script and, for earlier desktops, `orielos-desktop-icons-1.js`).

- **The Bin.** `/usr/libexec/orielos/desktop-bin`, run once per user by the user unit `orielos-desktop-bin.service` at sign-in, puts `Bin.desktop` in the Desktop folder: a link to `trash:/` whose `Icon` and `EmptyIcon` are OrielOS's line icons for a full and an empty Bin, in the text colour. A note in `~/.local/state/orielos/desktop-bin` stops it running again, so a deleted Bin stays deleted.
- **The right-click menu.** `desktopmenu/` is a Plasma containment actions plugin, `org.orielos.desktopmenu`, which the shell's `contents/defaults` gives the desktop's right button (and `orielos-desktop-icons-1.js` gives earlier desktops, through Plasma's scripting `ConfigFile`, from their next sign-in; a right button set to something else is left alone). It lists, in Windows' order: View (the folder view's icon options), Sort by, Refresh (KIO's change notification for the Desktop folder), Undo and Paste when there's something to undo or paste, New, Display settings and Personalise (OrielOS Settings' Display and Background pages), Open in Terminal (in the Desktop folder) and Show more options (emptying the Bin, widgets, edit mode, the desktop's settings and the wallpaper's own actions). The folder view's actions have no names, so the plugin finds them by their icons; a Plasma update that changes those icons drops them from the menu, so check it after one.

OrielOS Settings opens a page from an `orielos-settings:` link (`orielos-settings:display`), which its desktop file handles, so the shell's QML and plugins open pages with `Qt.openUrlExternally` and `QDesktopServices::openUrl` instead of Plasma's System Settings.

## Window frames

`decoration/` is OrielOS's KWin window decoration, a C++ plugin on KDecoration3 (`org.orielos.decoration`, installed to `/usr/lib64/qt6/plugins/org.kde.kdecoration3/`), which `/etc/xdg/kwinrc` chooses with the buttons Windows has: minimise, maximise and close on the right, nothing on the left.

- **Title bar:** 40 px, the window's own colour (the colour scheme's window background), with the app's icon and its title on the left; a window menu button, if the user adds one on the left, shows the icon instead.
- **Buttons:** 46 px wide and the bar's full height, flat (resting on maximise opens the snap layouts, see below); hovering lights them faintly and pressing a little more, and Close turns Windows' red with a white cross. The glyphs are 10 px lines; maximise turns into restore while the window is maximised. Other button types are hidden.
- **Corners and edges:** 8 px rounded corners (the decoration rounds the title bar; KWin rounds the bottom through the decoration's border radius), a hairline outline in the text colour, and an 8 px band outside the sides and bottom to grab for resizing. Maximised windows are square and opaque.
- **Shadow:** a wide soft shadow 8 px below the window and a tight one around it, made once (`shadow.cpp`) and fainter for windows not in use.

## Alt+Tab

`kwin/switcher/` is KWin's window switcher layout `org.orielos.switcher`, installed to `/usr/share/kwin/tabbox/`, which `/etc/xdg/kwinrc` chooses (`[TabBox] LayoutName`), with windows not brought forward in turn (`HighlightWindows=false`) and only this desktop's windows (`DesktopMode=1`), as Windows does. The screen dims and a pane in the middle holds the windows' thumbnails, 240 px wide in the screen's shape, most recently used first, each with its app's icon and title above it; the selected window is outlined in the highlight colour. Tab, Shift+Tab and the arrow keys move, a click picks, Delete closes the selected window, and hovering a thumbnail shows an X. KWin's own preview, `/usr/libexec/kwin-tabbox-preview <path to contents/ui/main.qml>`, shows it with sample windows.

## Snap layouts

`kwin/snaplayouts/` is a KWin effect package, `orielos-snaplayouts`, installed to `/usr/share/kwin/effects/` and on by default. It's a QML scene effect (`SceneEffect`, `X-Plasma-API: declarativescript`), so while it shows it has the keyboard and the mouse, as KWin's overview does. Its `ShortcutHandler` registers Win+Z as the `kwin` component's "Snap Layouts" action, so it can be changed under Shortcuts like KWin's own.

- **Opening.** Win+Z keeps the active window if it's a normal window that can be moved and resized and isn't full screen; otherwise nothing happens. Resting the pointer on the maximise button of OrielOS's window frames for half a second opens the same layouts as the button's menu: the frames invoke the effect's "Snap Layouts Menu" action (no key of its own) over D-Bus, for the window in use only.
- **The menu.** As the maximise button's menu, the screen isn't dimmed and the layouts sit in two rows of three, under the button (worked out from the window's frame: the second 46 px button from the right); it closes 0.4 s after the pointer leaves both the menu and the button, or on a click elsewhere.
- **Drawing.** A scene effect replaces the whole screen, so each screen's `Picker` draws that screen's windows as thumbnails (`WindowFilterModel`, as KWin's tiles editor does), dims them, and on the window's own screen shows Sill's six layouts: halves, two thirds and a third, thirds, a half beside two quarters, quarters, and a half between two quarters (`main.qml`'s `layouts`, as fractions of the usable area).
- **Snapping.** The chosen area is worked out from `Workspace.clientArea(MaximizeArea, window)`, the screen without the taskbar; the window is unmaximised, taken out of any tile and given that `frameGeometry`. Win+arrows stay with Plasma's own quick tiling.
- **Keys.** An arrow key moves to the nearest area in that direction as the layouts are drawn (Right past the last layout comes back to the first), Tab and Shift+Tab step through every area in order, Enter or Space snaps, Escape or a click outside closes.
- **One highlight.** The highlighted area belongs to the effect, not to each screen's `Picker`, so whichever screen KWin sends the keys to moves the highlight that shows. If the window closes while the layouts show, they close too.

Strings are in the `orielos-snaplayouts` translation domain. The tour presses Win+Z over Files and saves the picker and the result.

## Wallpapers

`CMakeLists.txt` installs OrielOS's two Plasma wallpaper packages from `artwork/wallpapers/` to `/usr/share/wallpapers/`:

- `OrielOS`: a glass bay window on a warm sill, as Daybreak (light) and Nightfall (dark). It is the default.
- `OrielOS-Horizon`, shown as OrielOS Horizon: the same sky without the window, offered in the wallpaper picker.

Each package has a light image in `contents/images/` and a dark one in `contents/images_dark/`. When a desktop's wallpaper is the package rather than one of its images, Plasma shows the dark image with a dark colour scheme and the light one otherwise, and switches when the colour scheme changes: Daybreak with Breeze Light, Nightfall with Breeze Dark.

OrielOS is the default in three places:

- The layout script writes `Image=file:///usr/share/wallpapers/OrielOS/` to the `[Wallpaper][org.kde.image][General]` group of each new desktop, so a new user's `plasma-org.orielos.desktop-appletsrc` names it.
- `[Wallpaper] Image=OrielOS` in `contents/defaults`. Plasma's image wallpaper shows the default look-and-feel's `[Wallpaper]` image on any desktop without an `Image` of its own, and System Settings applies it when a user picks the theme.
- `/etc/xdg/kscreenlockerrc`, from `image/system/etc/xdg/`, sets the lock screen's wallpaper the same way. Fedora's `kde-settings` profile names Fedora's wallpaper there, and `/etc/xdg` comes first on `XDG_CONFIG_DIRS`.

The login screen (SDDM) and the boot splash keep their own artwork for now.

## Update scripts

The layout script only runs for a new desktop. To change the desktop of users who already have one, a release adds an update script to the shell's `contents/updates/`. Plasma runs the scripts in the running shell's `/usr/share/plasma/shells/<shell>/contents/updates/` once per user when it starts, and records the scripts it has run in `[Updates]` in `~/.config/plasmashellrc`, so a script never runs twice for the same user. Plasma's own scripts for its widgets are in its desktop shell's folder, which the OrielOS shell doesn't read: when a Plasma update adds one that applies to a widget on OrielOS's desktop, copy it into the OrielOS shell's folder. Scripts use the same scripting API as the layout script, and what they `print` goes to `plasmashell`'s output. Plasma also runs them right after a layout script for a new user, so they must leave the current layout as it is.

The OrielOS shell's script:

- `shell/org.orielos.desktop/contents/updates/orielos-desktop-1.js` carries a desktop from Plasma's desktop shell over to the OrielOS shell, the first time it starts for someone who had one: it reads the Start menu's `favorites`, the task manager's `launchers` and the desktop's wallpaper from `plasma-org.kde.plasma.desktop-appletsrc` and writes them onto the taskbar the layout script has just made. It never writes the old file. For a new user there is nothing to copy.

The scripts in `updates/` are for Plasma's desktop shell, which OrielOS used before the OrielOS shell; `CMakeLists.txt` still installs them to `/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/` for anyone who switches back to it:

- `orielos-startmenu-2.js` pins OrielOS's Settings app in place of System Settings in a user's Start menu, when they had System Settings pinned; Start menus on the default pins are left alone, since the default now pins Settings.
- `orielos-startmenu-1.js` replaces Plasma's launcher (Kickoff, Kicker or the application dashboard) on the default bottom panel with OrielOS's Start menu, in the same place. It keeps a custom launcher icon, replacing only Plasma's and Fedora's stock icons, and changes nothing on a panel that already has the Start menu. Plasma runs scripts in file-name order, so it runs before `orielos-taskbar-1.js`. The old launcher's pinned apps aren't carried over: the Start menu starts with OrielOS's default pins.
- `orielos-taskbar-1.js` moves the default bottom panel to the taskbar's widget order. It acts only when the user has exactly one bottom panel and it holds a launcher and a task manager; otherwise it logs why and changes nothing. It reuses the widgets already on the panel, adds only missing ones and keeps any others, just before the system tray, so nothing is duplicated or lost. It replaces the launcher's icon only if it is one of Plasma's or Fedora's stock icons, and leaves the pinned apps alone. On a panel that is already in order it changes nothing.

Rules for update scripts:

- Put new scripts in the OrielOS shell's `contents/updates/`. Name them `orielos-<topic>-<n>.js`, numbering from 1, and add a new script for every change rather than editing a released one: Plasma would not run an edited script again for users who already ran it. Edit a released script only to keep it working with the current layout for the users who haven't run it yet. For example, `orielos-taskbar-1.js` now counts the Start menu as the launcher, so it leaves a new user's taskbar as it is.
- Make them safe to run on any desktop, including a brand-new one from the current layout script: check what is there, change only what needs changing and log what changed.
- Keep the layout script and the update scripts in step, so new and existing users end up with the same desktop.
- Scripts in the shell's `contents/updates/` are installed with the package; add any in `updates/` to `install(FILES ...)` in `CMakeLists.txt`.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
