# data

Data that installed systems fetch as public files.

- `known-apps.json`: the Windows programs Run this app knows (apps the Store has, game stores' launchers, Microsoft Store packages). Installed systems fetch the newest copy from here.
- `anticheat-games.json`: Will it run?'s list, from [AreWeAntiCheatYet](https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet) (MIT, see `LICENSE-AreWeAntiCheatYet`): each game's name, status, anti-cheat and whether it's native. Game Settings fetches the newest list from AreWeAntiCheatYet when online and uses this copy until then.
- `will-it-run-overrides.json`: OrielOS's own verdicts, tested on OrielOS, which win over AreWeAntiCheatYet's.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root), apart from `anticheat-games.json`, which is AreWeAntiCheatYet's data under the MIT licence.
