# Artwork credits

Every image, font and sound file in OrielOS, with its author, source and licence. Add a line here with every new file.

| Files | Author | Source | Licence |
|---|---|---|---|
| `logo/*.svg` | OrielOS contributors | Original | CC BY-SA 4.0 |
| `icons/orielos-start.svg` | OrielOS contributors | Original | CC BY-SA 4.0 |
| `splash/*.svg`, `splash/*.png` | OrielOS contributors | Original | CC BY-SA 4.0 |
| `wallpapers/src/*.svg` | OrielOS contributors | Original | CC BY-SA 4.0 |
| `wallpapers/OrielOS/**`, `wallpapers/OrielOS-Horizon/**` | OrielOS contributors | Rendered from `wallpapers/src/` | CC BY-SA 4.0 |
| `../.github/assets/readme-banner.png`, `../.github/assets/readme-banner-dark.png` | OrielOS contributors | Original | CC BY-SA 4.0 |

## Fonts

| Font | Used in | Author | Source | Licence |
|---|---|---|---|---|
| Noto Sans Display, Bold and Regular | The wordmark in the logos, the boot splash logo and the README banners, converted to outlines | Google and the Noto project authors | https://github.com/notofonts/latin-greek-cyrillic | SIL Open Font License 1.1 |

The SVG files contain the letter shapes as outlines rather than the fonts themselves. The OFL allows this, and no font file is shipped from this folder.

## From other projects

These are installed with OrielOS's own files but come from the projects named. OrielOS doesn't change them.

| Files | Used in | Author | Source | Licence |
|---|---|---|---|---|
| The spinner, password and keyboard images of Plymouth's spinner theme (`throbber-*.png`, `animation-*.png`, `bullet.png`, `capslock.png`, `entry.png`, `keyboard.png`, `keymap-render.png`, `lock.png`) | The boot splash, copied from Fedora's `plymouth-theme-spinner` package at build time | Jakub Steiner and the Plymouth authors | https://gitlab.freedesktop.org/plymouth/plymouth | GPL-2.0-or-later |
| SDDM's Breeze theme (everything in `/usr/share/sddm/themes/orielos` but OrielOS's `Main.qml`, `metadata.desktop` and `theme.conf`, including the default avatar `faces/.face.icon`) | The sign-in screen, copied from Fedora's `sddm-breeze` package at build time | KDE's Plasma developers | https://invent.kde.org/plasma/plasma-desktop | LGPL-2.0-or-later |
| `plasma/color-schemes/OrielOSLight.colors`, `OrielOSDark.colors` | OrielOS's colour schemes, with OrielOS's palette in Breeze's structure | Breeze's authors and OrielOS contributors | https://invent.kde.org/plasma/breeze | LGPL-2.0-or-later |

## The system's icons, cursors, sounds and fonts

OrielOS uses these themes from Fedora's packages as they are, with no files of its own in them. The icon theme is KDE's own Breeze, so there is nothing of unclear origin to replace.

| Theme | Package (version in the image, 2026-10-26) | Author | Source | Licence |
|---|---|---|---|---|
| Breeze and Breeze Dark icons | `breeze-icon-theme` 6.31.0 | KDE | https://invent.kde.org/frameworks/breeze-icons | LGPL-2.1-or-later, LGPL-3.0-or-later and CC BY-SA 4.0 |
| Breeze cursors and window decorations | `breeze-cursor-theme`, `plasma-breeze` 6.7.5 | KDE | https://invent.kde.org/plasma/breeze | GPL-2.0-or-later and others (BSD-3-Clause, CC0-1.0, MIT) |
| Ocean, Plasma's sound theme | `ocean-sound-theme` 6.7.5 | KDE | https://invent.kde.org/plasma/ocean-sound-theme | CC BY-SA 4.0, CC0-1.0 and BSD-2-Clause |
| The freedesktop.org sounds, which Ocean falls back to | `sound-theme-freedesktop` 0.8 | freedesktop.org | https://www.freedesktop.org/wiki/Specifications/sound-theme-spec | GPL-2.0-or-later, CC BY-SA 3.0 and others |
| Noto Sans, Noto Sans Mono, Noto Sans CJK and Noto Color Emoji | `google-noto-*-fonts` | Google and the Noto project authors | https://notofonts.github.io/ | SIL Open Font License 1.1 (Noto Color Emoji also Apache-2.0) |

## What is not here

None of this artwork comes from Microsoft or is derived from Microsoft's logos, fonts, icons, sounds or wallpapers.
