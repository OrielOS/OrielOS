# Benchmarks

How OrielOS measures its game performance against Windows 11 on the same computer: average FPS and
1% lows from each game's own benchmark, three runs each at fixed settings, plus boot time and idle
memory.

- `games.json`: the benchmark set (Vulkan, DX11 and DX12 games with built-in benchmarks), where each
  benchmark is, and the settings every run uses.
- `summarise.py`: turns MangoHud's frame logs into average FPS and 1% lows per run and per game,
  with how far the runs spread; `--markdown` prints a table.
- `system.sh`: boot loader to sign-in screen, sign-in to desktop, and memory in use after two idle
  minutes, on the computer it runs on.

## A run on OrielOS

1. In Settings › Gaming › FPS overlay, turn the overlay on and sign in again.
2. In each game's Steam launch options, add MangoHud's logging settings in front of what Game
   Settings wrote, for example:

   ```
   MANGOHUD_CONFIG=output_folder=/home/you/benchmarks,toggle_logging=Shift_L+F2 MANGOHUD=1 %command%
   ```

3. Set the game to the settings in `games.json`, start its benchmark, press Shift + F2 as it
   starts and again as it ends. Do this three times per game, restarting the game between runs.
4. Summarise: `tests/benchmark/summarise.py ~/benchmarks/*.csv --markdown`.
5. After a fresh start and sign-in, run `tests/benchmark/system.sh`.

## A run on Windows

Use the same games, settings and three runs, with the game's own results screen, or a frame-time
logger such as CapFrameX or PresentMon, and record average FPS and 1% lows per run.
