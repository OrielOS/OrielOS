# plasma

OrielOS's layer for KDE Plasma: the taskbar, Start menu, shortcuts and look.

Contains:

- `look-and-feel/org.orielos.desktop/`: OrielOS's look-and-feel package, which sets up OrielOS's taskbar for new users.
- `updates/`: desktop update scripts, which move existing users' desktops to the current layout.

Will contain:

- The Start menu widget.
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

The Start button is Plasma's own launcher, Kickoff, with the `orielos-start` icon: the OrielOS mark, three blue panes over an amber bar, drawn with wider gaps for taskbar sizes. Its source is `artwork/icons/orielos-start.svg`, and `CMakeLists.txt` installs it to `/usr/share/icons/hicolor/scalable/apps/`. OrielOS's own Start menu widget replaces Kickoff later.

The task manager pins Files (`org.kde.dolphin.desktop`), Firefox (`org.mozilla.firefox.desktop`, exported by Flatpak once the first boot has installed it) and Store (`org.kde.discover.desktop`), in that order. It is set not to fill the panel, so the spacers can centre it.

Notifications pop up next to the notifications icon in the system tray, which is at the bottom right of the screen, so they appear at the bottom right like Windows' without any further setting.

To try a change without a new user, log in as a test user with no `plasma-org.kde.plasma.desktop-appletsrc`, or paste the script into Plasma's desktop scripting console on a running desktop, which adds a second panel next to the existing one.

## Wallpapers

`CMakeLists.txt` installs OrielOS's two Plasma wallpaper packages from `artwork/wallpapers/` to `/usr/share/wallpapers/`:

- `OrielOS`: a glass bay window on a warm sill, as Daybreak (light) and Nightfall (dark). It is the default.
- `OrielOS-Horizon`, shown as OrielOS Horizon: the same sky without the window, offered in the wallpaper picker.

Each package has a light image in `contents/images/` and a dark one in `contents/images_dark/`. When a desktop's wallpaper is the package rather than one of its images, Plasma shows the dark image with a dark colour scheme and the light one otherwise, and switches when the colour scheme changes: Daybreak with Breeze Light, Nightfall with Breeze Dark.

OrielOS is the default in three places:

- The layout script writes `Image=file:///usr/share/wallpapers/OrielOS/` to the `[Wallpaper][org.kde.image][General]` group of each new desktop, so a new user's `plasma-org.kde.plasma.desktop-appletsrc` names it.
- `[Wallpaper] Image=OrielOS` in `contents/defaults`. Plasma's image wallpaper shows the default look-and-feel's `[Wallpaper]` image on any desktop without an `Image` of its own, and System Settings applies it when a user picks the theme.
- `/etc/xdg/kscreenlockerrc`, from `image/system/etc/xdg/`, sets the lock screen's wallpaper the same way. Fedora's `kde-settings` profile names Fedora's wallpaper there, and `/etc/xdg` comes first on `XDG_CONFIG_DIRS`.

Plasma Setup's Dark Theme switch applies Fedora's dark look-and-feel instead (see `image/README.md`), so an account set up with it starts with Fedora's wallpaper on the desktop; the lock screen still shows OrielOS's.

The login screen (SDDM) and the boot splash keep their own artwork for now.

## Update scripts

The layout script only runs for new users. To change the desktop of users who already have one, a release adds an update script to `updates/`. Plasma installs them to `/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/`, runs each script once per user when Plasma starts, and records the scripts it has run in `[Updates]` in `~/.config/plasmashellrc`, so a script never runs twice for the same user. Scripts use the same scripting API as the layout script, and what they `print` goes to `plasmashell`'s output. Plasma also runs them right after a layout script for a new user, so they must leave the current layout as it is.

- `orielos-taskbar-1.js` moves the default bottom panel to the taskbar's widget order. It acts only when the user has exactly one bottom panel and it holds a launcher and a task manager; otherwise it logs why and changes nothing. It reuses the widgets already on the panel, adds only missing ones and keeps any others, just before the system tray, so nothing is duplicated or lost. It replaces the launcher's icon only if it is one of Plasma's or Fedora's stock icons, and leaves the pinned apps alone. On a panel that is already in order it changes nothing.

Rules for update scripts:

- Name them `orielos-<topic>-<n>.js`, numbering from 1, and add a new script for every change rather than editing a released one: Plasma would not run an edited script again for users who already ran it.
- Make them safe to run on any desktop, including a brand-new one from the current layout script: check what is there, change only what needs changing and log what changed.
- Keep the layout script and the update scripts in step, so new and existing users end up with the same desktop.
- Add each script to `install(FILES ...)` in `CMakeLists.txt`.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
