# artwork

The artwork that OrielOS itself uses: the logo, the Start button icon, the boot splash logo and the wallpapers. [CREDITS.md](CREDITS.md) records where every file comes from.

Contents:

- `logo/`: the mark, the wordmark and the horizontal and stacked logos, as SVG. Each comes in colour, for dark grounds (`-dark`), in one colour (`-mono`) and in white (`-white`). They are for the OS's own screens, such as About, sign-in and setup.
- `icons/orielos-start.svg`: the Start button on the taskbar, installed as the `orielos-start` icon. It is the mark drawn with wider gaps between the panes, so it stays clear at 16 to 32 px.
- `splash/`: the stacked logo in one colour, as SVG and PNG, for the boot splash.
- `sounds/orielos/`: OrielOS's sound theme, soft glass-like chimes in D major for signing in and out, notifications, questions, warnings and errors, devices, power and battery, the volume keys and the window system's bell. It inherits Plasma's Ocean theme for any other sound. `sounds/src/generate.py` synthesises every file from sine waves; change the sounds there and run it again (it needs `oggenc`, or `gst-launch-1.0` with GStreamer's vorbis plugin).
- `wallpapers/`: two Plasma wallpaper packages, each with a light and a dark image that Plasma switches with the colour scheme.
  - `OrielOS` is the default: Daybreak (light) and Nightfall (dark), a glass bay window standing on a sill of daylight.
  - `OrielOS-Horizon` is the same sky without the window.
  - Their SVG sources are in `wallpapers/src/`.

Using the logo:

- Keep clear space around the logo at least as wide as one side pane of the mark.
- Don't recolour, stretch, rotate or outline it, or add effects to it.
- Use the `-dark` or `-white` files on dark grounds.

Will contain:

- The boot splash theme.
- The login and lock screen theme.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder), not the GPL.

Contributions must be original or under a compatible licence, with the attribution recorded in `CREDITS.md`. Nothing owned by Microsoft may be added: no Windows logos, Segoe fonts, Microsoft icons, sounds or wallpapers.
