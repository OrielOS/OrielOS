# Games and controllers

OrielOS comes ready for games. You install the game launchers you want from the Store, and the pieces games rely on underneath are already part of the system.

## Getting games

Install Steam, Heroic Games Launcher, Lutris or another launcher from the Store (see [Installing apps](apps.md)). OrielOS doesn't preinstall any of them.

## What OrielOS sets up for games

You don't need to change anything:

- **NTSYNC.** Windows games run through Proton use the kernel's own version of Windows' synchronisation objects, which makes many of them run more smoothly.
- **Settings some games need.** The system allows the large number of memory maps some games use, and doesn't slow down older games that use a CPU instruction pattern the kernel would otherwise penalise.
- **GameMode.** Games and launchers that support it can ask the system for full performance while they run.
- **Compressed memory swap (zram)**, as Fedora sets it up, so the computer stays responsive when memory runs low.
- **umu-launcher**, which OrielOS uses to run Windows programs with Proton.

## Controllers

Controllers work in Steam and in other games without extra drivers.

- **Xbox controllers** work over a USB cable or Bluetooth.
- **PlayStation 4 and 5 controllers** (DualShock 4, DualSense and DualSense Edge) work over a USB cable or Bluetooth, with rumble, the light bar, motion sensors and the battery level.

To pair a controller over Bluetooth:

1. Open the Bluetooth settings: click the Bluetooth icon in the system tray, then **Configure**.
2. Put the controller in pairing mode:
   - **DualSense or DualSense Edge:** hold the **Create** button and the **PS** button until the light around the touchpad flashes quickly.
   - **DualShock 4:** hold **Share** and **PS** until the light bar flashes.
   - **Xbox controller:** hold the pair button on its top edge until the Xbox button flashes quickly.
3. Choose the controller in the list of devices, then **Pair** or **Connect**.

The touchpad on PlayStation controllers doesn't move the mouse pointer on the desktop, so resting a thumb on it changes nothing outside the game. Games still read it, and Steam can turn it into a mouse in its controller settings.

The controller's battery level shows in the battery widget in the system tray.

## Mice, keyboards and lighting

Apps for gaming mice, keyboards and lighting come from the Store too: Solaar for Logitech devices, Piper for configurable gaming mice, and OpenRGB for RGB lighting. The parts that have to be in the system, so these apps can reach your devices, are already there. **Settings > Bluetooth & devices > Accessory apps** opens each one, or its page in the Store if it isn't installed.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
