# apps

OrielOS's own apps, written in C++ with Qt 6, QML and Kirigami and built with CMake. Every user-visible string goes through KI18n so it can be translated.

Will contain:

- Settings.
- Game Settings.
- Run this app, which runs Windows `.exe` and `.msi` programs through Proton.
- The update service and notifier.

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
```

Each app is a QML module (`qt_add_qml_module`) with the URI `org.orielos.<app>`. Unit tests go in an `autotests/` folder next to the code they test and are added with `ecm_add_test`. C++ follows the repository's `.clang-format`, and every source file starts with the `SPDX-FileCopyrightText` and `SPDX-License-Identifier` lines.

## Building and testing

The apps are built inside the image build, in the `app-builder` stage of `image/Containerfile`, on the pinned Fedora image in `image/pins.env`. That stage configures with CMake, builds, runs every test with `ctest`, runs `qmllint` over every QML module and installs the result, which the final image copies in. The image build fails if a test fails or `qmllint` reports a warning.

To run the same stage without building the whole image:

```sh
tools/test-apps.sh
```

It needs only Podman, works rootless, and is what CI runs on every pull request.

To build directly on a Fedora machine, install the packages listed in `image/build/apps-builder.sh`, then from the repository root:

```sh
cmake -S . -B build -G Ninja -DBUILD_TESTING=ON
cmake --build build
QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure
```

## The placeholder app

`orielos-buildcheck` is a minimal Kirigami app that proves the build and install path: it shows a window with the heading "OrielOS" and the system's `PRETTY_NAME` from os-release. Its desktop file, `org.orielos.BuildCheck.desktop`, has `NoDisplay=true`, so it does not appear in menus. It will be removed when the first real app replaces it.

`orielos-buildcheck --self-test` loads the window off screen (it sets `QT_QPA_PLATFORM=offscreen` when that is not set), checks that it was created without any QML warnings or errors, prints `orielos-buildcheck: self-test passed (<PRETTY_NAME>)` and exits with status 0. Otherwise it prints the problems and exits with status 1. `ctest` runs it in the build, and `tests/boot-test.sh` runs it inside the booted image, so it needs no desktop session.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
