# apps

OrielOS's own apps, written in C++ with Qt 6, QML and Kirigami and built with CMake. Every user-visible string goes through KI18n so it can be translated.

Will contain:

- Settings.
- Game Settings.
- Run this app, which runs Windows `.exe` and `.msi` programs through Proton.

## Layout

```text
CMakeLists.txt        adds each app (the CMake project starts at the repository root)
common/               code shared by the apps (static library OrielOSCommon)
  osrelease.h/.cpp    OrielOS::OsRelease, a parser for /etc/os-release
  autotests/          Qt Test unit tests, run by ctest
buildcheck/           orielos-buildcheck, the placeholder app
  main.cpp            start-up, translations and --self-test
  systeminfo.h/.cpp   the SystemInfo QML singleton
  qml/Main.qml        the window
updatestate/          the update state and its rules (static library OrielOSUpdateState)
  updatestate.h/.cpp  reads orielos-update's state file; shared by the tray icon and the page
  autotests/          Qt Test unit tests for the update state
settings/             orielos-settings, the Settings app
  main.cpp            start-up, one window per session, and the page to open
  pagecatalogue.h/.cpp  the categories and pages, and search (static library OrielOSSettingsCatalogue)
  modules.h/.cpp      finding settings modules where System Settings does
  settingssearch.h/.cpp  what Start and KRunner find: Settings' pages, then System Settings' other modules
  runner/             krunner_orielos_settings, the search runner for Start and KRunner
  settingswindow.h/.cpp  the window, which hosts Plasma's settings modules
  autotests/          Qt Test unit tests for the catalogue, both searches and the runner
settingspages/       OrielOS's own Settings pages, each a Plasma settings module
  accessories/        kcm_orielos_accessories, Accessory apps: StoreApps (QML module org.orielos.accessories) and its page
  accent/             kcm_orielos_accent, Accent colour: AccentColour (QML module org.orielos.accent) and its page
  shell/              ShellSettings, which reads and changes Start's and the taskbar's settings in the running desktop
  start/              kcm_orielos_start, Start: StartOptions (QML module org.orielos.start) and its page
  taskbar/            kcm_orielos_taskbar, Taskbar: TaskbarOptions (QML module org.orielos.taskbar) and its page
  autotests/          Qt Test unit tests for both models, and a test that loads both modules
updatenotifier/       orielos-update-notifier, the update tray icon
  main.cpp            start-up, translations, --state and --boot-id-file
  updatenotifier.h/.cpp  the tray icon, its menu, the notifications and restarting
updatesettings/       kcm_orielos_update, the Update settings page (a Plasma settings module)
  updatesettings.h/.cpp  UpdateSettings, the page's model (QML module org.orielos.updatesettings)
  updatecommands.h/.cpp  running orielos-update through pkexec, and following the check unit
  UpdatePage.qml      the page; ConfirmationDialog.qml asks before going back or removing
  kcmupdate.cpp       the settings module itself, and kcm_orielos_update.json, its metadata
  ui/main.qml         what System Settings loads: just the page
  autotests/          Qt Test unit tests for the model, and a test that loads the module
```

Each app is a QML module (`qt_add_qml_module`) with the URI `org.orielos.<app>`. Unit tests go in an `autotests/` folder next to the code they test and are added with `ecm_add_test`. C++ follows the repository's `.clang-format`, and every source file starts with the `SPDX-FileCopyrightText` and `SPDX-License-Identifier` lines.

## Building and testing

The apps are built inside the image build, in the `app-builder` stage of `image/Containerfile`, on the pinned Fedora image in `image/pins.env`. That stage configures with CMake, builds, runs every test with `ctest`, runs `qmllint` over every QML module and installs the result, which the final image copies in. The image build fails if a test fails or `qmllint` reports a warning.

To run the same stage without building the whole image:

```sh
tools/test-apps.sh
```

It needs only Podman, works rootless, and is what CI runs on every pull request that changes a file the app build reads: `apps/`, `plasma/`, `artwork/`, `CMakeLists.txt`, `VERSION`, the image's `Containerfile`, `pins.env` and `build/apps-builder.sh`, or the script and workflow themselves. The list is in `.github/workflows/apps.yml`; add to it when the build starts reading another file.

To build directly on a Fedora machine, install the packages listed in `image/build/apps-builder.sh`, then from the repository root:

```sh
cmake -S . -B build -G Ninja -DBUILD_TESTING=ON
cmake --build build
QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure
```

## The update notifier

`orielos-update-notifier` tells the user about OrielOS updates. The autostart entry `org.orielos.UpdateNotifier.desktop`, installed to `/etc/xdg/autostart`, starts it in every Plasma session; `KDBusService` keeps it to one per session.

- **What it reads.** It follows `/var/lib/orielos/update/state.json`, which `orielos-update` writes (see `image/README.md`). It watches the file and its folder, and also rereads them every five minutes. The file describes one boot, so the notifier trusts it only when its `bootId` matches `/proc/sys/kernel/random/boot_id`.
- **The tray icon** (`KStatusNotifierItem`, "OrielOS updates") stays in the tray's hidden area until a build is staged for the next restart, or going back is queued, then turns Active. Its tooltip says what the last check found, until when updates are paused, or which version a restart goes back to.
- **The notifications.** It shows the KNotification event `updateReady`, from `orielos-update-notifier.notifyrc`, once per staged build per session, with "Restart to update" and "Later", `goBackReady` once going back is queued, with "Restart to go back" and "Later", and `updateUndone` once per session after an update that didn't reach the desktop was undone, with orielos-update's message.
- **Restarting.** The restart actions call `org.kde.Shutdown.logoutAndReboot`, so Plasma signs out cleanly before restarting.
- **Clicking the icon** opens the Update settings page with `orielos-settings kcm_orielos_update`, passing the tray's activation token as `XDG_ACTIVATION_TOKEN` so the window gets the focus. Its menu has only "Restart to update" (or "Restart to go back") while there's something to restart for, and "Open update settings". Everything else is on the page.
- **Testing.** `--state FILE` and `--boot-id-file FILE` point it at other files. The rules it follows are `OrielOSUpdateState`'s, which `updatestate/autotests/updatestatetest.cpp` covers: reading the state, when an update counts as waiting, pauses, the pause choices, the channels, going back, removing the previous build, an undone update and the tooltip texts.

## Searching for settings from Start

`krunner_orielos_settings` (`settings/runner/`) is a KRunner plugin, installed to `kf6/krunner`, that Start's search uses in place of System Settings' runner, `krunner_systemsettings`; `etc/xdg/krunnerrc` in the image turns System Settings' runner off in KRunner too. It searches with `SettingsSearch`:

- **Settings' pages** come first, found by the same rules as Settings' own search field (`PageCatalogue::search`, with the Windows words), and open with `orielos-settings <page>`. Their subtext says where they are, such as "Settings › System".
- **Every other module** System Settings lists (from `plasma/kcms/systemsettings` and `systemsettings_qwidgets`, with a category and not hidden) follows, found by its name, description and `X-KDE-Keywords`, and opens with `systemsettings <module>`. Modules Settings has a page for are left out, so nothing shows twice.
- A page whose title matches gets a high category relevance in KRunner, above apps found only by their keywords; System Settings' modules get less. Commands start through `KIO::CommandLauncherJob`, so the window gets an activation token and comes to the front.
- The modules are found once, in the runner's `init()`, which KRunner runs on the runner's own thread before its first match; they only change with an OS update, which needs a restart. The query is split into words once per search, and a page's keywords and description are only looked at when its title doesn't match. A program that can't start says so in a notification (`KNotificationJobUiDelegate`).
- **Testing.** `settingssearchtest` covers the search with made-up pages and modules; `settingsrunnertest` loads the built runner the way Start does, through `KRunner::AbstractRunnerTest`, and checks the commands it gives for OrielOS's pages and for Plasma's Fonts module.

## OrielOS's own Settings pages

`settingspages/` holds pages that Settings shows among Plasma's, built the same way as the Update page: each is a settings module made with `kcmutils_add_qml_kcm`, with its page and model in a static QML module of its own linked into it. Each needs its own QML module because Settings loads every page into one process, and a QML module can be registered only once there. Their strings are in the `orielos-settings-pages` translation domain.

- **Accessory apps** (`kcm_orielos_accessories`, under Bluetooth & devices). `StoreApps` lists Solaar, Piper and OpenRGB, whose udev rules and ratbagd the image already has. An app counts as installed when its Flatpak desktop entry is on `XDG_DATA_DIRS`; **Open** starts it with `flatpak run`, and **Get it from the Store** opens its `appstream:` link in Discover, where the user decides whether to install it. The page looks again every three seconds while it's shown, so an app installed meanwhile changes to **Open**. Icons of apps that aren't installed come from Flathub's catalogue in `/var/lib/flatpak/appstream`.
- **Accent colour** (`kcm_orielos_accent`, under Personalisation). `AccentColour` offers ten colours and the colour scheme's own selection colour. It records a choice as `AccentColor` in `kdeglobals` (or removes it for the scheme's own) and applies it with `plasma-apply-colorscheme --accent-color` (`transparent` for none), in its own process. `plasma-apply-colorscheme` recolours the scheme but doesn't record the accent, and applying a scheme later, as switching to dark mode does, keeps only a recorded one. It runs in its own process because Plasma's Colours module links GPL-2.0-only code, so Settings never loads it. It reads `AccentColor` and `ColorScheme` from `kdeglobals`, and follows changes made elsewhere, such as on the Themes page. Light and dark mode stay on the Themes page; the accent carries over between them.
- **Start and Taskbar** (`kcm_orielos_start` and `kcm_orielos_taskbar`, under Personalisation). Both use `ShellSettings`, which runs a script in `plasmashell` through `org.kde.PlasmaShell.evaluateScript`. The script finds the panel with OrielOS's Start menu and the panel spacer just before Start (by the panel's saved `AppletOrder`), makes the one change asked for, and prints the settings as JSON. Desktop scripting writes a widget's setting through its configuration, so Start and the panel follow at once, as if the change had been made on the desktop. Start's `showRecentlyAdded` and `showRecentFiles` are the widget's own settings; left alignment turns off that spacer's `expanding`, so the spacer after the task manager fills the panel; auto-hide sets the panel's `hiding` to `autohide` or `none`. Without the spacer before Start the alignment is greyed out. One script runs at a time; a change shows at once on the page and goes back if it fails.
- **Testing.** `storeappstest` and `accentcolourtest` cover the models, with their own environment and command. `shellsettingstest` runs the desktop script in a `QJSEngine` against a fake of Plasma's scripting API (panels, widgets, settings, the saved order, hiding), and the models against a fake desktop. `pagesloadtest` loads every built module the way Settings does, into one shared QML engine, and fails on any QML warning.

## The Update settings page

`kcm_orielos_update` is a Plasma settings module. Settings hosts it as its Update page, `orielos-settings kcm_orielos_update` opens it there, and `kcmshell6 kcm_orielos_update` opens it on its own. `kcmutils_add_qml_kcm` builds it, installs it to `plasma/kcms/systemsettings` and generates its `kcm_orielos_update.desktop`. The page and its model are a static QML module, `org.orielos.updatesettings`, linked into it, so `qmllint` checks the page like every other QML module.

- **What it shows.** `UpdateSettings` reads the same state file as the notifier, the same way: the running version, when updates were last checked and what the check found, whether an update is waiting or going back is queued (with **Restart now**), the pause, the channel, and the previous build with the date it's removed after (`previous.removedAfter`).
- **What it runs.** Every change runs `pkexec /usr/bin/orielos-update ...`, so the page holds no update logic of its own: `check-now`, `pause N` (1 to 5 weeks), `resume`, `channel stable|testing`, `rollback` and `remove-previous`. polkit (`org.orielos.update.policy`) allows the first three without a password, and asks for an administrator to change the channel, go back or remove the previous version. One command runs at a time; a dismissed password prompt changes nothing and shows nothing, and any other failure shows orielos-update's reason on the page. Going back and removing the previous version ask first, with Cancel as the default.
- **Checking.** "Check for updates" starts `orielos-update-check.service`, which runs in the background. The page follows the unit's `ActiveState` from systemd over the system bus (`LoadUnit`, `Subscribe` and `PropertiesChanged`), so it also shows the timer's checks, and shows the result once the unit stops. A check that never starts stops being shown after 30 seconds.
- **The keyboard.** Every button and option has an Alt mnemonic, each letter used once: Check for updates (U), Restart now (N), Pause updates (P), Resume updates (R), Stable (S), Testing (T), Go back to the previous version (G) and Remove the previous version (M), and Go back (B) and Remove (E) in the questions. C is left for `kcmshell6`'s Close button, where the VM test uses them. Keep them unique when adding options. A button's mnemonic is fixed when the button is made: showing it later, or changing its text, leaves the letter doing nothing. So a `Loader` makes a new Pause updates or Resume updates button each time a pause starts or ends.
- **Translations.** The page translates through its own `KI18nContext` with the module's domain, `kcm_orielos_update`: System Settings' engine doesn't set up the `KI18n` singleton.
- **Testing.** `autotests/updatesettingstest.cpp` runs the model against a scratch state file with stand-ins for the command runner and the check unit, and a fixed clock: what it shows, what each action runs and refuses, one command at a time, the error messages, the channel while it changes, and checking. `autotests/kcmloadtest.cpp` loads the built module from the build's plugin folder the way System Settings does, with no system bus and no state file, and fails on any QML warning.

## Settings

`orielos-settings` is OrielOS's Settings app. Its window is Qt Widgets, as Plasma's System Settings is, so it can host both kinds of Plasma settings module: QML ones and older Qt Widgets ones.

- **Pages.** `PageCatalogue::standard()` lists the categories in the order Windows Settings uses (System, Bluetooth & devices, Network & internet, Personalisation, Apps, Accounts, Time & language, Update), and under each the pages, each a settings module: Display is `kcm_kscreen`, Update is `kcm_orielos_update`, and so on. A page whose module isn't installed is left out, and so is a category left with none. A category with one page opens it straight away; the others show their pages first. Colours (`kcm_colors`) isn't hosted: it links a GPL-2.0-only library, which can't be combined with OrielOS's GPL-3.0-or-later code in one process.
- **Hosting.** Each module is loaded on first use with `KCModuleLoader::loadModule()` into a `QStackedWidget`; every QML module shares one `QQmlEngine`. Modules are looked for where System Settings looks: `plasma/kcms/systemsettings`, `systemsettings_qwidgets`, `plasma/kcms` and `plasma/kcms/kinfocenter`. The window owns Apply, Reset and Defaults and shows the ones each module asks for (`buttons()`); before leaving a page with unsaved changes, or closing, it asks whether to apply or discard them.
- **Search.** The field above the categories (Ctrl+F) searches page names and the words in each page's translatable keyword list, which include the names people know from Windows ("wifi", "default apps", "windows update", "specs"). Every word typed must start a word of the page; matches in the title come first. Enter opens the best match.
- **Starting.** `orielos-settings [page]` opens a page by its ID (such as `display` or `update`), its module (such as `kcm_kscreen`) or a category. Settings runs once per session (`KDBusService::Unique`): starting it again, with Win+I or from the update tray icon, brings the window forward and opens the page asked for.
- **Win+I and Start.** `org.orielos.Settings.desktop` has `X-KDE-Shortcuts=Meta+I`, and a copy in `/usr/share/kglobalaccel` registers it. `image/build/26-shortcuts.sh` takes Win+I from System Settings and hides it from Start, and the Start menu's default pins and `orielos-startmenu-2.js` pin Settings in its place. System Settings stays installed, because parts of Plasma open their pages in it.
- **Testing.** `autotests/pagecataloguetest.cpp` covers the category order, the pages, leaving out missing modules, and search: Windows terms, titles before keywords, every word needed, and accents.

## The placeholder app

`orielos-buildcheck` is a minimal Kirigami app that proves the build and install path: it shows a window with the heading "OrielOS" and the system's `PRETTY_NAME` from os-release. Its desktop file, `org.orielos.BuildCheck.desktop`, has `NoDisplay=true`, so it does not appear in menus. It will be removed when the first real app replaces it.

`orielos-buildcheck --self-test` loads the window off screen (it sets `QT_QPA_PLATFORM=offscreen` when that is not set), checks that it was created without any QML warnings or errors, prints `orielos-buildcheck: self-test passed (<PRETTY_NAME>)` and exits with status 0. Otherwise it prints the problems and exits with status 1. `ctest` runs it in the build, and `tests/boot-test.sh` runs it inside the booted image, so it needs no desktop session.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
