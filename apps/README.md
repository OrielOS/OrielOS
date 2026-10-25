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
updatenotifier/       orielos-update-notifier, the update tray icon
  main.cpp            start-up, translations, --state and --boot-id-file
  updatestate.h/.cpp  the update state and its rules (static library OrielOSUpdateState)
  updatenotifier.h/.cpp  the tray icon, its menu, the notification and restarting
  autotests/          Qt Test unit tests for the update state
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
- **The notifications.** It shows the KNotification event `updateReady`, from `orielos-update-notifier.notifyrc`, once per staged build per session, with "Restart to update" and "Later", and `goBackReady` once going back is queued, with "Restart to go back" and "Later".
- **Restarting.** Both restart actions call `org.kde.Shutdown.logoutAndReboot`, so Plasma signs out cleanly before restarting.
- **The menu.** It checks for updates, pauses for 1 to 5 weeks, resumes, and switches between the stable and testing channels by running `pkexec /usr/bin/orielos-update ...`. polkit allows the first three without a password and asks for an administrator to change channel. A failure other than a cancelled password prompt shows the `settingsFailed` event.
- **Going back.** "Go back to the previous version…" is shown while the state names a previous build that wasn't rejected and going back isn't queued yet. It asks first with `KMessageBox`, Cancel being the default, then runs `pkexec /usr/bin/orielos-update rollback`, for which polkit asks for an administrator.
- **Testing.** `--state FILE` and `--boot-id-file FILE` point it at other files. `autotests/updatestatetest.cpp` covers reading the state, when an update counts as waiting, pauses, the pause choices, the channels, going back and the tooltip texts.

## The placeholder app

`orielos-buildcheck` is a minimal Kirigami app that proves the build and install path: it shows a window with the heading "OrielOS" and the system's `PRETTY_NAME` from os-release. Its desktop file, `org.orielos.BuildCheck.desktop`, has `NoDisplay=true`, so it does not appear in menus. It will be removed when the first real app replaces it.

`orielos-buildcheck --self-test` loads the window off screen (it sets `QT_QPA_PLATFORM=offscreen` when that is not set), checks that it was created without any QML warnings or errors, prints `orielos-buildcheck: self-test passed (<PRETTY_NAME>)` and exits with status 0. Otherwise it prints the problems and exits with status 1. `ctest` runs it in the build, and `tests/boot-test.sh` runs it inside the booted image, so it needs no desktop session.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
