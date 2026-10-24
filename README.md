# OrielOS

OrielOS is a Linux distribution that looks and works like Windows 11 and is tuned for gaming on NVIDIA RTX desktop PCs. The aim is simple: everything you do on Windows, done the same way, without Windows.

**Status:** early development. There is nothing to download or install yet. Version 0.0.0 until the first build lands.

## Goals

- **Feels like Windows 11.** Centred taskbar, a Windows 11-style Start menu, the keyboard shortcuts you already know (Win+E, Win+Shift+S, Win+V, Ctrl+Shift+Esc and more), and a Settings app organised the way Windows organises it.
- **No terminal needed.** Installing apps, updating, changing settings and running games all have a graphical path.
- **Games run well.** Native Linux games and Windows games through Proton, with GE-Proton as the default. Performance is measured against Windows on the same PC and published.
- **Updates you can trust.** Updates download in the background and apply on "Restart to update", like Windows Update. If something goes wrong, go back to the previous version in one click, or pick it from the boot menu.
- **Windows programs open with a double-click.** A "Run this app" dialog installs and runs `.exe` and `.msi` files through Proton, and suggests a native version when one exists.
- **No telemetry.** OrielOS itself collects nothing.

## How it's built

| Area | Choice |
|---|---|
| Base | Fedora Atomic, built as a bootable container image with bootc |
| Kernel and graphics | Fedora's kernel with NVIDIA's open kernel modules, signed for Secure Boot |
| Desktop | KDE Plasma with OrielOS's own Windows 11 layer |
| OrielOS apps | C++ with Qt 6, QML and Kirigami |
| Apps | Installed from Flathub through the Store; Firefox comes preinstalled |
| Gaming | Steam and Heroic from the Store, GE-Proton by default, umu-launcher for Windows programs |

## Hardware

The first release targets desktop PCs with NVIDIA RTX (20-series or newer) graphics. AMD and Intel graphics, laptops and handhelds may follow later.

## Known limitations

- **Some online games won't run.** Games whose publishers block Linux through their anti-cheat (for example Valorant, League of Legends, Call of Duty and Battlefield 6) can't be played on any Linux distribution. OrielOS shows which games work and which are blocked, and boots in a way that meets Easy Anti-Cheat's Linux requirements so games that allow Linux can run.
- **No hibernation.** The secure boot configuration that anti-cheat needs disables hibernation. Sleep works as normal.
- **Microsoft 365 and Adobe apps** have no Linux versions. Use the web versions or Linux alternatives.
- **Not affiliated with Microsoft.** OrielOS imitates the Windows 11 layout and behaviour but uses none of Microsoft's logos, fonts, icons, sounds or wallpapers.

## Repository layout

```text
image/     OS image recipe: Containerfile, build scripts, system configuration
apps/      OrielOS apps: Settings, Game Settings, Run this app, updates
plasma/    Start menu, window snapping and desktop layout for KDE Plasma
artwork/   Logo, wallpapers, sounds, boot and login themes
data/      Compatibility data and app recipes used by installed systems
tests/     Boot, update and rollback tests, benchmarks
tools/     Developer scripts
docs/      User documentation
```

Each folder has a short README describing what belongs there.

## Contributing

OrielOS is developed in the open on GitHub. Changes go through pull requests into `main`. Contribution guidelines will be added before the first public build.

## Licence

Code and configuration are licensed under the GNU General Public License, version 3 or (at your option) any later version (`GPL-3.0-or-later`). The full text is in `LICENSE`.

Documentation in `docs/` and artwork in `artwork/` are licensed under Creative Commons Attribution-ShareAlike 4.0 International (`CC BY-SA 4.0`). The full text is in `docs/LICENSE` and `artwork/LICENSE`.

## Changes

See [CHANGELOG.md](CHANGELOG.md).
