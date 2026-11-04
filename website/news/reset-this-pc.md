---
title: Coming to testing: Reset this PC
date: 2026-11-04
summary: Reset this PC puts a fresh OrielOS back from Settings, keeping your accounts and files or removing everything, without repartitioning. It's not in a build yet.
---

OrielOS now has Reset this PC. It's merged, but it isn't in a published build yet: it reaches the testing channel first, then the stable version, the one the [download](/download/) installs, once it's been checked on real PCs.

## What it does

If OrielOS isn't working as it should, and going back to the previous version doesn't help, you can reset it. Open Settings → System → Recovery, or search Start for "reset". A reset puts the newest version of OrielOS on your update channel back on the computer, with its own system settings, as if it had just been installed.

There are two choices, and each asks you to confirm first:

- **Reset and keep files** keeps every account, everything in each person's home folder (documents, downloads, games from Steam, and each person's own settings), the computer's name, language, keyboard layout and time zone, saved Wi-Fi networks and paired Bluetooth devices. Apps from the Store and system settings you changed go back to how OrielOS ships, and Firefox comes back by itself.
- **Reset and remove everything** starts again with nothing kept. After the restart, first run setup opens, as after installing OrielOS.

## How it works

OrielOS downloads the newest version and checks its signature, as it does for updates, with a progress bar on the page. It gets the new system ready next to the one you're running while you keep using the computer, and nothing changes until you restart. Until then, Cancel the reset undoes everything. After the restart, the old system is removed in the background.

A reset doesn't repartition or format anything. Only OrielOS's own part of the drive changes, so Windows and its boot files, other partitions and other drives stay as they are, and the boot menu still offers Windows afterwards. If the computer can't reach the desktop after the reset, twice in a row, it goes back to the system it had before by itself.

It needs an internet connection and about 10 GB of free space, and the page says so before downloading anything if there isn't enough. Removing everything doesn't securely erase the drive, so use a proper erasing tool before giving a computer away. [Resetting this PC](/guides/recovery/) has the details.

## Trying it

Once it's in a testing build, switch to the testing channel in Settings → Update and it arrives by itself. It's been tested in virtual machines and with a keep files reset on a real laptop. It hasn't been tried yet on a computer that also has Windows installed.

It's still early. [Known limitations](/guides/known-limitations/) lists what doesn't work, including games whose anti-cheat doesn't allow Linux, no Hibernate, and no Microsoft 365 or Adobe apps.
