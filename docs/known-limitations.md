# Known limitations

OrielOS is in early development. This page lists what it can't do yet, and what it won't do by design, so you know before you try it.

## Trying it out

- **It has been tested on few real PCs so far.** OrielOS runs on an MSI laptop with an RTX 4050 (installed next to Windows 11, and on its own), and in virtual machines. Laptops aren't officially supported yet: OrielOS is built for desktop PCs.
- **The installer needs an internet connection.** It downloads OrielOS while it installs, over Wi-Fi or a cable: see [Install OrielOS](install.md).
- **The installer doesn't shrink Windows for you.** Make room for OrielOS in Windows' Disk Management first, as [Install OrielOS](install.md) shows.
- **A virtual machine isn't a gaming PC.** In a virtual machine the desktop uses basic graphics, so it can feel slower and games don't run as they would on your PC (see [Graphics in a virtual machine](install-vm.md#graphics-in-a-virtual-machine)).

## Games

- **Some games won't run, whatever OrielOS does.** A game's publisher decides whether its anti-cheat allows Linux. If they don't, the game refuses to start on any Linux system. Check whether a game supports Linux or the Steam Deck before you buy it. OrielOS itself always starts in the mode that games with anti-cheat need: see [Games with anti-cheat](anti-cheat.md).
- **There's no Hibernate.** The locked-down start that games with anti-cheat need rules it out. Sleep works as usual.
- **Windows programs that aren't games** run with a double-click through Run this app **(testing; not yet in stable v0.0.7)**, but it's new and has been tried with only a few programs; programs that need special drivers don't run. Games run best through Steam from the Store, or a store's own launcher installed with Run this app. See [Windows programs](windows-programs.md).

## Everyday use

- **OrielOS's own parts are in English only.** The words OrielOS adds, such as in Start, the update notifications and its own settings pages, aren't translated yet. Plasma and the apps that come with it follow the language you choose.
- **The first-start wizard still says "Welcome to Plasma Desktop"**, the name of the desktop OrielOS is built on, over Plasma's own picture rather than OrielOS's wallpaper.
- **The taskbar's menu says "Pin to Task Manager" if you choose languages in Settings → Region & Language.** OrielOS changes it to "Pin to taskbar" for English, but a language list chosen there replaces OrielOS's wording.
- **There are no high-contrast colour themes.** Zoom, the magnifier and colour filters are there, but not Windows-style contrast themes.
- **Microsoft's fonts, apps and services aren't included**, and never will be: OrielOS doesn't ship anything Microsoft owns. Apps such as Microsoft 365 work in the browser.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
