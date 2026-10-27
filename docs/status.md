# Status

OrielOS is in early development. This page lists what works today, what doesn't work yet and what's planned, so you know what to expect before you install it. "Checked on the laptop" means it was checked on a real PC, an MSI laptop with an RTX 4050; "checked in virtual machines" means it's tested automatically in virtual machines with Secure Boot on, on every change.

Last updated: 27 October 2026.

## Works

### Installing

- **The installer, `OrielOS.iso`**, starts with Secure Boot on, connects over Wi-Fi or a cable, downloads the current stable version, checks its signature and installs it, showing how much is left. Checked on the laptop, and in virtual machines. See [Install OrielOS](install.md).
- **Next to Windows**, in space you free up in Windows first. Windows keeps working and appears in the start menu for five seconds at every start. Checked on the laptop with Windows 11, and in virtual machines; reinstalling over an earlier OrielOS next to Windows is checked in virtual machines.
- **On a whole drive**, replacing what was there. Checked on the laptop.
- **The first start** asks for your language, keyboard, network, time zone, power settings and account. Checked on the laptop, and in virtual machines.

### Desktop

- **The taskbar** with Start and your pinned apps in the middle, and the system tray, clock and show-desktop corner on the right. Checked on the laptop, and in virtual machines.
- **Start**: search for apps, settings and files, pinned apps, All apps, recommendations, and the account and power buttons. See [Using Start](start-menu.md).
- **Windows keyboard shortcuts** for Start, Files, Run, Process Manager, Screenshot, the clipboard history, the overview and snapping windows. See [Keyboard shortcuts](keyboard-shortcuts.md).
- **Snap layouts** (Windows + Z), **light and dark themes**, OrielOS's wallpapers, sounds, boot splash, sign-in and lock screens. Checked in virtual machines.
- **Wi-Fi, Bluetooth, sound, the display's resolution and refresh rate, keyboard and touchpad.** Checked on the laptop.

### Settings

- **One Settings app** with OrielOS's categories and pages, including Update, Taskbar, Accent colour, Power mode, Accessibility, and Device security, which checks that the PC starts the way games with anti-cheat need. See [Settings](settings.md). Checked in virtual machines.

### Updates

- **Automatic updates in the background**, applied when you restart, with **going back** to the previous version from Settings → Update if a new one gives you trouble. Each update's signature is checked first. A real update from the testing channel was checked on the laptop; going back is checked in virtual machines. See [Updates and going back](updates.md).
- **Two channels**: stable, the default, and testing, which gets each new version as soon as it's built.

### Apps and the Store

- **The Store** installs apps from Flathub; Firefox arrives on the first start. See [Installing apps](apps.md). Checked on the laptop, and in virtual machines.
- **Steam from the Store** sees the NVIDIA graphics card. Checked on the laptop.

### Games and drivers

- **The NVIDIA driver** works with Secure Boot on, after a one-time step at the first start. See [Secure Boot and your drivers](secure-boot.md). Checked on the laptop with the RTX 4050.
- **The mode games with anti-cheat need**: every start meets the requirements of Easy Anti-Cheat's Linux support. See [Games with anti-cheat](anti-cheat.md). Checked on the laptop.
- **Gaming defaults and controllers**: the Performance power mode, the settings that games for Windows run best with, and drivers for Xbox and PlayStation controllers. See [Games and controllers](games-and-controllers.md). Checked in virtual machines; controllers haven't been tried on a real PC yet.

## Doesn't work yet

- **Few real PCs so far.** Only one laptop has run OrielOS. Desktop PCs with NVIDIA graphics are what it's for, and the first one is still to be tested.
- **PCs with only AMD or Intel graphics** aren't supported yet: OrielOS is built and tested for NVIDIA. (On the laptop, Intel graphics drive its own screen alongside the RTX 4050, as on most laptops.)
- **Windows programs that aren't games** can't be run with a double-click yet.
- **No game has been played on OrielOS yet** in its tests: Steam and the graphics driver work, but playing games is the next step.
- **Sleep and wake** haven't been checked on a real PC yet.
- **OrielOS's own parts are in English only.**

[Known limitations](known-limitations.md) lists these and more, including what OrielOS won't do by design, such as Hibernate.

## Planned

- **Run this app**: double-click a Windows program and OrielOS runs it, with known apps set up for you.
- **Game Settings**: an app for per-game settings, with GE-Proton as the default way to run games for Windows.
- **Will it run?**: check whether a game works on Linux before you buy it.
- **An FPS overlay** you turn on with a shortcut.
- **A Gaming page in Settings.**
- **What's new**: the changes in each update, shown in Settings → Update before you restart.
- **Settings in one place**: everything opens in OrielOS's Settings, including the NVIDIA settings.
- **Development tools**: editors, containers and a terminal, ready to use.
- **Testing on desktop PCs** and a real-hardware checklist for each stable release.
- **Benchmarks** against Windows on the same PC, and performance targets that each version must meet.
- **AMD and Intel graphics.**
- **Translations** of OrielOS's own parts.
- **Version 1**, once all of this works on real PCs.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
