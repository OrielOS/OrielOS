<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/readme-banner-dark.png">
  <img alt="OrielOS" src=".github/assets/readme-banner.png">
</picture>

# OrielOS

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15906/badge)](https://www.bestpractices.dev/projects/15906)

OrielOS is a free and open-source Linux desktop, tuned for gaming and development, that feels familiar from the first boot. It runs on desktop PCs, starting with NVIDIA RTX graphics. If you're coming from Windows, the taskbar, Start menu, keyboard shortcuts and Settings are where you expect them, and Windows games and programs run through Proton.

**Status:** early development. There is nothing to download or install yet. Version 0.0.0 until the first build lands.

## Goals

- **Familiar from the first boot.** A centred taskbar, a Start menu with search and pinned apps, the keyboard shortcuts you know from Windows (Win+E, Win+Shift+S, Win+V, Ctrl+Shift+Esc and more), and a Settings app organised by task.
- **No terminal needed.** Installing apps, updating, changing settings and running games all have a graphical path.
- **Tuned for gaming.** Native Linux games and Windows games through Proton, with GE-Proton as the default. Performance is measured against Windows on the same PC and published.
- **Ready for development.** Code editors such as VS Code, AI coding tools and containers for your toolchains, with a proper terminal whenever you want one.
- **Updates you can trust.** Updates download in the background and apply on "Restart to update". If something goes wrong, go back to the previous version in one click, or pick it from the boot menu.
- **Windows programs open with a double-click.** A "Run this app" dialog installs and runs `.exe` and `.msi` files through Proton, and suggests a native version when one exists.
- **No telemetry.** OrielOS itself collects nothing.

## How it's built

| Area | Choice |
|---|---|
| Base | Fedora Atomic, built as a bootable container image with bootc |
| Kernel and graphics | Fedora's kernel; NVIDIA's open kernel modules and driver for RTX graphics, signed for Secure Boot |
| Desktop | KDE Plasma with OrielOS's own taskbar, Start menu, shortcuts and look |
| OrielOS apps | C++ with Qt 6, QML and Kirigami |
| Apps | Installed from Flathub through the Store; Firefox comes preinstalled |
| Gaming | Steam and Heroic from the Store, GE-Proton by default, umu-launcher for Windows programs |

## Hardware

The first release targets desktop PCs with NVIDIA RTX (20-series or newer) graphics. Support for AMD and Intel graphics is planned to follow the first release. Laptops and handhelds may come later.

## Known limitations

- **Some online games won't run.** Games whose publishers block Linux through their anti-cheat (for example Valorant, League of Legends, Call of Duty and Battlefield 6) can't be played on any Linux distribution. OrielOS shows which games work and which are blocked, and boots in a way that meets Easy Anti-Cheat's Linux requirements so games that allow Linux can run.
- **No hibernation.** The secure boot configuration that anti-cheat needs disables hibernation. Sleep works as normal.
- **Microsoft 365 and Adobe apps** have no Linux versions. Use the web versions or Linux alternatives.
- **Not affiliated with Microsoft.** OrielOS follows layouts and habits people know from Windows, but uses none of Microsoft's logos, fonts, icons, sounds or wallpapers.

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
website/   The orielos.org website and its build
discord/   The Discord bot that posts releases and merges and gives linked members their GitHub roles
```

Each folder has a short README describing what belongs there.

## Contributing

OrielOS is developed in the open on GitHub. Changes go through pull requests into `main`. Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started, and please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems as described in [SECURITY.md](SECURITY.md). Ask questions, share ideas and follow announcements in [GitHub Discussions](https://github.com/ncjsvr/OrielOS/discussions); [SUPPORT.md](SUPPORT.md) says where everything else goes. For live chat, join [the official OrielOS Discord server](https://discord.gg/RnpZYaKbHA). It's the only official one.

## Licence

Code and configuration are licensed under the GNU General Public License, version 3 or (at your option) any later version (`GPL-3.0-or-later`). The full text is in `LICENSE`.

Documentation in `docs/` and artwork in `artwork/` are licensed under Creative Commons Attribution-ShareAlike 4.0 International (`CC BY-SA 4.0`). The full text is in `docs/LICENSE` and `artwork/LICENSE`.

## Changes

See [CHANGELOG.md](CHANGELOG.md).
