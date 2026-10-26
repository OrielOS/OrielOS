# Known limitations

OrielOS is in early development. This page lists what it can't do yet, and what it won't do by design, so you know before you try it.

## Trying it out

- **There's no download or installer yet.** You build OrielOS yourself from the source code and try it in a virtual machine: see [Try OrielOS in a virtual machine](install-vm.md).
- **It hasn't been tested on real PCs yet.** So far OrielOS has only run in virtual machines. The first installs on real hardware, alongside Windows, come next.
- **A virtual machine isn't a gaming PC.** In a virtual machine the desktop uses basic graphics, so it can feel slower and games don't run as they would on your PC (see [Graphics in a virtual machine](install-vm.md#graphics-in-a-virtual-machine)).

## Games

- **Some games won't run, whatever OrielOS does.** A game's publisher decides whether its anti-cheat allows Linux. If they don't, the game refuses to start on any Linux system. Check whether a game supports Linux or the Steam Deck before you buy it. OrielOS itself always starts in the mode that games with anti-cheat need: see [Games with anti-cheat](anti-cheat.md).
- **There's no Hibernate.** The locked-down start that games with anti-cheat need rules it out. Sleep works as usual.
- **Windows programs that aren't games** can't be run with a double-click yet. Games run through Steam and the other launchers from the Store.

## Everyday use

- **OrielOS's own parts are in English only.** The words OrielOS adds, such as in Start, the update notifications and its own settings pages, aren't translated yet. Plasma and the apps that come with it follow the language you choose.
- **The first-start wizard still says "Welcome to Plasma Desktop"**, the name of the desktop OrielOS is built on.
- **There are no high-contrast colour themes.** Zoom, the magnifier and colour filters are there, but not Windows-style contrast themes.
- **Microsoft's fonts, apps and services aren't included**, and never will be: OrielOS doesn't ship anything Microsoft owns. Apps such as Microsoft 365 work in the browser.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
