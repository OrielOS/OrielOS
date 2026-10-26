# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compares a VM screenshot with its reference image, for the visual check in the boot test.

    python3 -I tests/lib/screens.py REFERENCE SCREENSHOT [--mask FILE] [--diff FILE]
                                    [--fuzz N] [--max-changed FRACTION]

A pixel counts as changed when any colour channel differs by more than --fuzz (0 to 255,
default 32), which absorbs anti-aliasing and font rendering noise. Areas listed in the mask file
are ignored: one "x y width height" rectangle per line, with # starting a comment, for parts of the
screen that change from run to run, such as the clock. The check passes when at most
--max-changed of the other pixels changed (default 0.01, one in a hundred).

Prints "changed=<fraction> pixels=<changed>/<compared>" and exits with 0 when the screenshot
matches, 1 when it doesn't, and 2 when an image can't be read or the sizes differ. --diff writes
the screenshot dimmed, with the changed pixels in red and the masked areas in blue.
"""

import argparse
import sys

from PIL import Image, ImageChops


def read_mask(path, size):
    """The rectangles to ignore, clipped to the image: [(left, top, right, bottom), ...]."""
    width, height = size
    boxes = []
    if not path:
        return boxes
    with open(path, encoding="utf-8") as lines:
        for number, line in enumerate(lines, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            try:
                x, y, w, h = (int(value) for value in line.split())
            except ValueError:
                raise SystemExit(f"{path}:{number}: expected 'x y width height', got {line!r}")
            boxes.append((max(0, x), max(0, y), min(width, x + w), min(height, y + h)))
    return boxes


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("reference")
    parser.add_argument("screenshot")
    parser.add_argument("--mask")
    parser.add_argument("--diff")
    parser.add_argument("--fuzz", type=int, default=32)
    parser.add_argument("--max-changed", type=float, default=0.01)
    args = parser.parse_args()

    try:
        reference = Image.open(args.reference).convert("RGB")
        screenshot = Image.open(args.screenshot).convert("RGB")
    except OSError as error:
        print(f"error: {error}")
        return 2
    if reference.size != screenshot.size:
        print(f"error: the screenshot is {screenshot.size[0]}x{screenshot.size[1]}, the reference {reference.size[0]}x{reference.size[1]}")
        return 2

    # The largest channel difference of each pixel, then 255 where it's above the fuzz.
    difference = ImageChops.difference(reference, screenshot)
    changed = Image.eval(max_channel(difference), lambda v: 255 if v > args.fuzz else 0)
    masked = Image.new("L", reference.size, 0)
    for box in read_mask(args.mask, reference.size):
        masked.paste(255, box)
    changed = ImageChops.subtract(changed, masked)

    total = reference.size[0] * reference.size[1] - masked.histogram()[255]
    count = changed.histogram()[255]
    fraction = count / total if total else 0.0
    print(f"changed={fraction:.4f} pixels={count}/{total}")

    if args.diff:
        view = Image.blend(screenshot, Image.new("RGB", screenshot.size, (0, 0, 0)), 0.6)
        view.paste((40, 80, 200), mask=masked)
        view.paste((255, 0, 0), mask=changed)
        view.save(args.diff)
    return 0 if fraction <= args.max_changed else 1


def max_channel(image):
    """A greyscale image of each pixel's largest channel value."""
    red, green, blue = image.split()
    return ImageChops.lighter(ImageChops.lighter(red, green), blue)


if __name__ == "__main__":
    sys.exit(main())
