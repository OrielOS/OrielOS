#!/usr/bin/python3 -I
# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarises MangoHud's frame logs from benchmark runs: average FPS and 1% lows per run, and per
game across its runs, with how far the runs spread.

MangoHud writes one CSV per logging session: a header with the system (os, cpu, gpu...), its values,
then a header starting "fps,frametime" and one line per frame. Average FPS is frames over time
(1000 / the mean frame time in milliseconds); the 1% low is the average FPS of the slowest 1% of
frames. Runs are grouped by game from the file name, which MangoHud starts with the program's name
(such as Cyberpunk2077_2026-11-02_10-00-00.csv).

Usage: tests/benchmark/summarise.py LOG.csv... [--markdown]
"""

import csv
import re
import statistics
import sys
from pathlib import Path


def frame_times(path):
    """The frame times in milliseconds from one MangoHud log."""
    times = []
    with open(path, newline="", encoding="utf-8", errors="replace") as file:
        rows = csv.reader(file)
        column = None
        for row in rows:
            if column is None:
                if row and row[0].strip() == "fps" and "frametime" in row:
                    column = row.index("frametime")
                continue
            try:
                value = float(row[column])
            except (IndexError, ValueError):
                continue
            if value > 0:
                times.append(value)
    if not times:
        raise ValueError(f"{path} has no frame times")
    return times


def summarise_run(times):
    """(average FPS, 1% low FPS) for one run's frame times."""
    average = 1000.0 / statistics.fmean(times)
    slowest = sorted(times, reverse=True)[: max(1, len(times) // 100)]
    low = 1000.0 / statistics.fmean(slowest)
    return average, low


def game_of(path):
    """The game a log belongs to: its file name up to the date MangoHud adds."""
    return re.sub(r"_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$", "", Path(path).stem)


def main(argv):
    markdown = "--markdown" in argv
    paths = [a for a in argv if a != "--markdown"]
    if not paths:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    games = {}
    for path in paths:
        try:
            games.setdefault(game_of(path), []).append(summarise_run(frame_times(path)))
        except (OSError, ValueError) as error:
            print(f"skipping {path}: {error}", file=sys.stderr)
    if not games:
        return 1
    if markdown:
        print("| Game | Runs | Average FPS | 1% low FPS | Spread of averages |")
        print("|---|---|---|---|---|")
    for game, runs in sorted(games.items()):
        averages = [r[0] for r in runs]
        lows = [r[1] for r in runs]
        mean = statistics.fmean(averages)
        spread = (max(averages) - min(averages)) / mean * 100 if len(averages) > 1 else 0.0
        if markdown:
            print(f"| {game} | {len(runs)} | {mean:.1f} | {statistics.fmean(lows):.1f} | {spread:.1f} % |")
        else:
            print(f"{game}: {len(runs)} runs, average {mean:.1f} FPS, 1% low {statistics.fmean(lows):.1f} FPS, spread {spread:.1f} %")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
