# Changelog

All notable changes to OrielOS are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and OrielOS uses [semantic versioning](https://semver.org/) for its releases; OS image builds are additionally tagged by Fedora release and date.

## [Unreleased]

### Added

- Contribution guidelines, a code of conduct, a security policy, support and governance notes, issue and pull request templates, and a GitHub Discussions form for questions.
- OrielOS has its own logo, Start button icon and wallpapers. Daybreak (light) and Nightfall (dark) are the default on the desktop and the lock screen, and the plainer Horizon is in the wallpaper picker.
- Every boot meets Easy Anti-Cheat's Linux requirements: kernel lockdown, IOMMU on, the BPF LSM, kexec disabled and only signed drivers. Hibernation is not offered.
- Windows keyboard shortcuts work out of the box, including Win+R for Run, Win+Tab for the task overview, Ctrl+Shift+Esc for Task Manager and Win+PrtSc to save a screenshot, and the system tools appear in Start as Task Manager, Snipping Tool and Files.
- First boot queues Universal Blue's driver-signing key for enrolment and explains the one-time Secure Boot step; a warning appears if the firmware lacks Microsoft's 2023 UEFI CA.
- A Windows 11-style taskbar for new users: Start button and pinned apps in the centre, system tray, clock and notifications at the right.
- Discover appears as Store, with Flathub as its only source of apps. Firefox is installed from Flathub on first boot, retrying until it succeeds, and is the default web browser.
- README describing what OrielOS is, its goals, how it will be built and its known limitations.
- Repository layout, with a README in each folder describing what belongs there.
- Licence files: GPL-3.0-or-later for code and configuration, and CC BY-SA 4.0 for documentation and artwork.
- Editor settings, ignore rules and secret-scanning configuration.
- OS image recipe based on Fedora 44 bootc with the Fedora CoreOS stable kernel, NVIDIA's open kernel modules and driver, and a minimal KDE Plasma desktop, with a local build script that pins every upstream input by digest.
- The complete KDE Plasma desktop on Wayland, with Discover for apps from Flathub, sound, Bluetooth, printing and a boot splash, and with the server features that a desktop doesn't need switched off: automatic update reboots, the SSH server, crash dumps and cloud tools.
- Plasma Setup on first boot: a new installation has no user account, and KDE's setup wizard asks for the language, keyboard layout, network, time zone and the first account, then opens the login screen. It doesn't run again once setup is finished, and the boot test checks both.
- Virtual machine disks for QEMU (qcow2) and VMware (VMDK) from one command, a tool that creates and boot-checks a VMware Workstation VM from the VMDK, and a guide to trying OrielOS in a virtual machine.
- A command-line update tool that stages a new build for the next restart and rolls back to the previous build; rolled-back builds are not offered again.
