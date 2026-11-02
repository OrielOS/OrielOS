# Games and controllers

OrielOS comes ready for games. You install Steam from the Store, or another store's own launcher with Run this app, and the pieces games rely on underneath are already part of the system.

## Getting games

Get your games the way you would on Windows:

- **Steam:** install it from the Store (see [Installing apps](apps.md)).
- **Other stores:** download the store's own launcher from its website, such as the Epic Games Launcher, GOG Galaxy, the EA app, Ubisoft Connect or Battle.net, and double-click it. Run this app installs it, and it appears in Start (see [Windows programs](windows-programs.md)). Some of these launchers are still being tested on OrielOS.

OrielOS doesn't preinstall any of them.

## GE-Proton for Windows games in Steam

> GE-Proton as Steam's default is in testing builds of OrielOS. It arrives on the stable channel with the next stable release; to try it now, switch to testing in Settings → Update.

Windows games run on OrielOS through Proton, a compatibility layer. OrielOS makes **GE-Proton** Steam's default: a community build of Valve's Proton that carries newer fixes, and plays many in-game videos and cutscenes that Valve's build can't.

- When you install Steam from the Store, OrielOS also installs GE-Proton for it, the next time it updates your apps (a few minutes after you start the computer, then about every six hours). It's about 570 MB, and it then updates with your other apps.
- The next time Steam is closed after that, OrielOS sets GE-Proton as Steam's default for Windows games, once. It doesn't change anything while Steam is open, because Steam saves its settings when it closes.
- If Steam already had a default you chose, OrielOS leaves it as it is.

Your own choices always win:

- **For one game:** in Steam, right-click the game, choose **Properties → Compatibility**, tick **Force the use of a specific Steam Play compatibility tool** and pick a version, such as Valve's Proton if a game misbehaves with GE-Proton.
- **For every game:** in Steam, open **Settings → Compatibility** and choose the tool under **Default compatibility tool**.

OrielOS sets the default only once, so it never undoes a choice you make later.

## What OrielOS sets up for games

You don't need to change anything:

- **NTSYNC.** Windows games run through Proton use the kernel's own version of Windows' synchronisation objects, which makes many of them run more smoothly.
- **Settings some games need.** The system allows the large number of memory maps some games use, and doesn't slow down older games that use a CPU instruction pattern the kernel would otherwise penalise.
- **Performance power mode.** OrielOS starts in the Performance power mode, on mains power and on battery, and adds no power limits of its own. You can change it at any time from the battery and power icon in the system tray, and your choice is kept, also after updates. On a laptop, Performance means a shorter battery life and more fan noise.
- **GameMode.** Games and launchers that support it can ask the system for full performance while they run.
- **Compressed memory swap (zram)**, as Fedora sets it up, so the computer stays responsive when memory runs low.
- **umu-launcher**, which OrielOS uses to run Windows programs with Proton.

## Game Settings

**Game Settings**, in Start or under **Settings > Gaming**, lists the games in Steam from the Store. Choose one to set how it runs:

- **Run Windows games with**: Steam's default, GE-Proton, or Proton Experimental or another of Valve's Protons, if a game works better with it.
- **Upgrade DLSS to the newest version**, on NVIDIA graphics cards.
- **HDR**, through Wine's Wayland driver, on an HDR screen.
- **Run in gamescope**, Valve's game window, for scaling and frame limits.
- **DX12 descriptor heaps**, which can make DirectX 12 games faster on NVIDIA cards but breaks some.
- **FPS overlay** and **GameMode**.

Game Settings also lists the Windows programs you installed with Run this app, such as a game store's launcher, with the same switches except the Proton version and gamescope; they apply whenever that program, or a game it installed, starts from Start.

Each switch adds its part to the game's launch options in Steam, next to anything you typed there yourself, and turning it off takes out only what it added. Steam saves its own settings as it closes, so Game Settings waits until Steam is closed, and offers to close it. The first change keeps a copy of Steam's settings next to them.

**Will it run?**, at the top of Game Settings, says whether a game with anti-cheat runs on OrielOS: it works, the publisher blocks Linux, it doesn't work yet, or support is planned. The answers come from [AreWeAntiCheatYet](https://areweanticheatyet.com/)'s list (MIT licence), updated whenever Game Settings opens online, with the date of the copy it uses, and OrielOS's own tests win over it.

### Fix it

When a game from Steam won't start or misbehaves, open it in Game Settings and choose **Fix it**, under Will it run?. Fix it closes Steam, starts the game once with Proton's log turned on, and asks you to play until the problem happens and then close the game. It reads the log, puts the game's settings back as they were, and says in plain words what most likely went wrong, with the fixes for it, best first. Nothing changes until you choose one.

A fix is always for that game only: running it with another version of Proton, a setting in its launch options, turning off one of Game Settings' switches, or clearing the shaders it saved. After you choose **Apply**, Fix it starts the game again, and counts the fix as working if the game keeps running for 2 minutes. **Undo the last fix** puts back exactly what was there before. Some problems, such as an anti-cheat runtime missing in Steam, come with steps to follow instead of a button.

Fix it remembers which fixes worked on this PC, with its graphics card and driver, and suggests those first next time. Nothing leaves your PC. It can't help with games whose publisher blocks Linux: Will it run? says so.

## The FPS overlay

OrielOS's Game Bar is one thing: a small frame-rate counter over the game you're playing. Turn it on in **Settings > Gaming > FPS overlay**; games you start after you next sign in have it, hidden until you press **Windows + G**, which shows or hides it in the game's top-left corner. The same page can add the frame time, and processor and graphics card use, under the frame rate.

Steam from the Store runs its games in its own sandbox, so it needs the overlay's add-on from the Store: the page offers **Install the add-on** when Steam is installed without it. A few games with anti-cheat may refuse to start with an overlay; turn it off for those. Steam's own overlay still takes screenshots and records.

## Controllers

Controllers work in Steam and in other games without extra drivers.

- **Xbox controllers** work over a USB cable or Bluetooth.
- **PlayStation 4 and 5 controllers** (DualShock 4, DualSense and DualSense Edge) work over a USB cable or Bluetooth, with rumble, the light bar, motion sensors and the battery level.

To pair a controller over Bluetooth:

1. Open **Settings > Bluetooth & devices**.
2. Put the controller in pairing mode:
   - **DualSense or DualSense Edge:** hold the **Create** button and the **PS** button until the light around the touchpad flashes quickly.
   - **DualShock 4:** hold **Share** and **PS** until the light bar flashes.
   - **Xbox controller:** hold the pair button on its top edge until the Xbox button flashes quickly.
3. Choose the controller in the list of devices, then **Pair** or **Connect**.

The touchpad on PlayStation controllers doesn't move the mouse pointer on the desktop, so resting a thumb on it changes nothing outside the game. Games still read it, and Steam can turn it into a mouse in its controller settings.

The controller's battery level shows in Quick Settings, on the Bluetooth tile's list of devices.

## Mice, keyboards and lighting

Apps for gaming mice, keyboards and lighting come from the Store too: Solaar for Logitech devices, Piper for configurable gaming mice, and OpenRGB for RGB lighting. The parts that have to be in the system, so these apps can reach your devices, are already there. **Settings > Bluetooth & devices > Accessory apps** opens each one, or its page in the Store if it isn't installed.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
