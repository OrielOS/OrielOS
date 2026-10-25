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
- **Clicking the icon** opens the Update settings page with `systemsettings kcm_orielos_update`, passing the tray's activation token as `XDG_ACTIVATION_TOKEN` so the window gets the focus. Its menu has only "Restart to update" (or "Restart to go back") while there's something to restart for, and "Open update settings". Everything else is on the page.
- **Testing.** `--state FILE` and `--boot-id-file FILE` point it at other files. The rules it follows are `OrielOSUpdateState`'s, which `updatestate/autotests/updatestatetest.cpp` covers: reading the state, when an update counts as waiting, pauses, the pause choices, the channels, going back, removing the previous build, an undone update and the tooltip texts.

## The Update settings page

`kcm_orielos_update` is a Plasma settings module, so System Settings shows it as **OrielOS Update** under System, and `systemsettings kcm_orielos_update` (or `kcmshell6 kcm_orielos_update`) opens it on its own. `kcmutils_add_qml_kcm` builds it, installs it to `plasma/kcms/systemsettings` and generates its `kcm_orielos_update.desktop`. The page and its model are a static QML module, `org.orielos.updatesettings`, linked into it, so `qmllint` checks the page like every other QML module.

- **What it shows.** `UpdateSettings` reads the same state file as the notifier, the same way: the running version, when updates were last checked and what the check found, whether an update is waiting or going back is queued (with **Restart now**), the pause, the channel, and the previous build with the date it's removed after (`previous.removedAfter`).
- **What it runs.** Every change runs `pkexec /usr/bin/orielos-update ...`, so the page holds no update logic of its own: `check-now`, `pause N` (1 to 5 weeks), `resume`, `channel stable|testing`, `rollback` and `remove-previous`. polkit (`org.orielos.update.policy`) allows the first three without a password, and asks for an administrator to change the channel, go back or remove the previous version. One command runs at a time; a dismissed password prompt changes nothing and shows nothing, and any other failure shows orielos-update's reason on the page. Going back and removing the previous version ask first, with Cancel as the default.
- **Checking.** "Check for updates" starts `orielos-update-check.service`, which runs in the background. The page follows the unit's `ActiveState` from systemd over the system bus (`LoadUnit`, `Subscribe` and `PropertiesChanged`), so it also shows the timer's checks, and shows the result once the unit stops. A check that never starts stops being shown after 30 seconds.
- **The keyboard.** Every button and option has an Alt mnemonic, each letter used once: Check for updates (U), Restart now (N), Pause updates (P), Resume updates (R), Stable (S), Testing (T), Go back to the previous version (G) and Remove the previous version (M), and Go back (B) and Remove (E) in the questions. C is left for `kcmshell6`'s Close button, where the VM test uses them. Keep them unique when adding options. A button that starts hidden inside a hidden row gets no working mnemonic when the row appears, so Pause updates and Resume updates are one button whose text changes.
- **Translations.** The page translates through its own `KI18nContext` with the module's domain, `kcm_orielos_update`: System Settings' engine doesn't set up the `KI18n` singleton.
- **Testing.** `autotests/updatesettingstest.cpp` runs the model against a scratch state file with stand-ins for the command runner and the check unit, and a fixed clock: what it shows, what each action runs and refuses, one command at a time, the error messages, the channel while it changes, and checking. `autotests/kcmloadtest.cpp` loads the built module from the build's plugin folder the way System Settings does, with no system bus and no state file, and fails on any QML warning.

## The placeholder app

`orielos-buildcheck` is a minimal Kirigami app that proves the build and install path: it shows a window with the heading "OrielOS" and the system's `PRETTY_NAME` from os-release. Its desktop file, `org.orielos.BuildCheck.desktop`, has `NoDisplay=true`, so it does not appear in menus. It will be removed when the first real app replaces it.

`orielos-buildcheck --self-test` loads the window off screen (it sets `QT_QPA_PLATFORM=offscreen` when that is not set), checks that it was created without any QML warnings or errors, prints `orielos-buildcheck: self-test passed (<PRETTY_NAME>)` and exits with status 0. Otherwise it prints the problems and exits with status 1. `ctest` runs it in the build, and `tests/boot-test.sh` runs it inside the booted image, so it needs no desktop session.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
