---
title: In testing: Run this app and GE-Proton for Steam
date: 2026-11-01
summary: Testing builds since v0.0.7 open Windows programs with a double click and make GE-Proton Steam's default for Windows games. Stable v0.0.7 doesn't have them yet.
---

Since [v0.0.7](/news/orielos-v0-0-7/), OrielOS has put out a run of testing builds. They go to computers on the testing channel first, and the changes in them reach the stable version, the one the [download](/download/) installs, once they've been checked on real PCs. Nothing here is in stable v0.0.7 yet.

## Run this app

Double click a Windows program, an `.exe` or `.msi`, and OrielOS shows you the file and the website it came from, and asks before running anything. Say yes and it runs through GE-Proton in a Windows set up of its own. Shortcuts the program's installer makes turn up in Start, and a program that isn't an installer can be added to Start too.

That's also how other game stores work now: the Epic Games Launcher or GOG Galaxy, installed with Run this app, the way you'd get them on Windows. Start no longer suggests Heroic Games Launcher or Lutris, though both are still in the Store. [Windows programs](/guides/windows-programs/) explains it.

## GE-Proton as Steam's default

Install Steam from the Store and OrielOS puts GE-Proton next to it. The next time Steam is closed, it makes GE-Proton Steam's default for Windows games, once, and leaves alone a default you've already picked. A game's own compatibility setting in Steam still wins. [Games and controllers](/guides/games-and-controllers/) has the details.

## Smaller things

- The sign in screen shows your account and the password box straight away, over the OrielOS wallpaper, with the time and date above.
- The installer names the OrielOS version it was made from, and warns that Windows may ask for its recovery key when a drive uses BitLocker.
- Right click an app on the taskbar and it says Pin to taskbar and Unpin from taskbar, the same words as Start.
- Every testing build has its own [release notes](/releases/), saying what's new since the build before it.

## Trying it

If you already run OrielOS, switch to the testing channel in Settings → Update and the newest testing build arrives by itself. You can go back to the previous version from the same page. New installs still start from stable v0.0.7: [download it](/download/) and follow [Install OrielOS](/guides/install/).

It's still early. [Known limitations](/guides/known-limitations/) lists what doesn't work, including games whose anti-cheat doesn't allow Linux, no Hibernate, and no Microsoft 365 or Adobe apps.
