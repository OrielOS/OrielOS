---
title: OrielOS v0.0.7: the first build you can install
date: 2026-10-27
summary: v0.0.7 is the first OrielOS release with an installer. Write OrielOS.iso to a USB stick and install it on an NVIDIA RTX PC, or next to Windows.
---

v0.0.7 is the first OrielOS release you can install on a PC. The installer is `OrielOS.iso`, about 1.2 GB. [Download it](/download/), check the SHA-256 checksum, and follow [Install OrielOS](/guides/install/).

Already running OrielOS? There's nothing to download. The update arrives by itself; to fetch it now, open Settings → Update and choose Check for updates. For new versions sooner, switch to the testing channel on that same page.

## What the installer does

It starts with Secure Boot on. It asks for your language, keyboard, time zone and network, over Wi-Fi or a cable, and where to install. It then downloads the current stable version, checks its signature and installs it, showing how much is left and how long it will take. Your account is created when OrielOS first starts, not during the install.

Next to Windows, it uses space you freed in Windows' Disk Management and keeps Windows in the boot menu. On a PC that also has Windows, that menu shows for five seconds at every start. On other PCs it stays hidden.

The ISO doesn't contain the whole system, so the PC needs an internet connection while installing.

## What this release includes

v0.0.7 is the first stable release with its own version number, so the notes describe the desktop as it stands:

- The desktop: KDE Plasma with OrielOS's taskbar and Start menu, snap layouts (Windows + Z), and OrielOS's own colours, sounds, boot splash and sign-in screen.
- Settings, opened with Windows + I, including the update page. Updates download in the background and apply when you restart. You can go back to the previous version, and if a new version never reaches the desktop, OrielOS goes back on its own.
- The Store, with apps from Flathub, and Firefox from the first start. Windows games run through Proton. Steam from the Store reaches Xbox and PlayStation controllers.
- Wi-Fi and Bluetooth firmware for the common cards, from the first start.
- No telemetry of its own. This release also stops sending Fedora's anonymous weekly package count.

[Known limitations](/guides/known-limitations/) lists what still doesn't work, including games whose anti-cheat doesn't allow Linux, and Hibernate, which OrielOS doesn't offer. It's early.

## Install it

[Download OrielOS](/download/) and follow [Install OrielOS](/guides/install/). The same guide covers keeping Windows.
