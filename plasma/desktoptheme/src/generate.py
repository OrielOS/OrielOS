#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the SVGs of OrielOS's Plasma theme, "orielos", in Sill's look.

Plasma draws panels, pop-ups, tooltips and task buttons from "nine-patch" SVG elements: four
corners, four edges and a centre, named by convention, plus margin hints, shadows and blur masks.
This script draws those elements from a few numbers, so the look can be changed here and the files
written again. Any file the theme doesn't have comes from Plasma's own theme, Breeze.

Colours come from the user's colour scheme through Plasma's ColorScheme-* classes, so the theme is
dark with OrielOS Dark and light with OrielOS Light. The one fixed colour is Daylight, the sill
line under the app in use.

Usage: generate.py [OUTPUT_DIR]   (default: the theme folder next to this script's folder)
"""

import os
import sys

DAYLIGHT = "#FFB547"
STYLE = (
    '<style id="current-color-scheme" type="text/css">'
    ".ColorScheme-Background { color:#1a1f2e; } "
    ".ColorScheme-Text { color:#ffffff; } "
    ".ColorScheme-Highlight { color:#3a66f0; } "
    ".ColorScheme-NegativeText { color:#e05a5a; }"
    "</style>"
)


class Svg:
    """Collects elements, each at its own place on a grid so none overlap."""

    def __init__(self):
        self.parts = []
        self.defs = []
        self.x = 0
        self.y = 0
        self.row_height = 0

    def slot(self, w, h):
        if self.x + w > 600:
            self.x = 0
            self.y += self.row_height + 10
            self.row_height = 0
        x, y = self.x, self.y
        self.x += w + 10
        self.row_height = max(self.row_height, h)
        return x, y

    def add(self, text):
        self.parts.append(text)

    def write(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                "<!-- SPDX-FileCopyrightText: 2026 OrielOS contributors -->\n"
                "<!-- SPDX-License-Identifier: GPL-3.0-or-later -->\n"
                "<!-- Written by plasma/desktoptheme/src/generate.py; change that and run it again. -->\n"
                '<svg xmlns="http://www.w3.org/2000/svg" width="620" height="%d">\n' % (self.y + self.row_height + 10)
            )
            f.write("<defs>%s\n%s</defs>\n" % (STYLE, "\n".join(self.defs)))
            f.write("\n".join(self.parts))
            f.write("\n</svg>\n")


def fill(cls, opacity):
    return 'class="%s" style="fill:currentColor;fill-opacity:%s"' % (cls, opacity)


def rounded_corner(r, c):
    """The top-left corner piece of a rounded rectangle, c by c, with radius r <= c."""
    return "M 0,%s L 0,%s A %s,%s 0 0 1 %s,0 L %s,0 L %s,%s Z" % (c, r, r, r, r, c, c, c)


def corner_border(r):
    """The top-left part of a 1 px outline with radius r."""
    h = 0.5
    return "M %s,%s L %s,%s A %s,%s 0 0 1 %s,%s" % (h, r + 0.01, h, r, r - h, r - h, r, h)


ROTATE = {
    "topleft": "",
    "topright": "scale(-1,1)",
    "bottomleft": "scale(1,-1)",
    "bottomright": "scale(-1,-1)",
}
EDGE_SIDES = ("top", "bottom", "left", "right")


def frame(svg, prefix, c, r, background, border=None, border_sides=EDGE_SIDES, extra=None):
    """A nine-patch frame: corners c by c rounded with radius r, edges and centre filled with
    `background` (a (class, opacity) pair or None), an optional 1 px outline `border` on the given
    sides, and `extra`, a function that adds more drawing to a piece."""
    p = (prefix + "-") if prefix else ""

    def corner(name):
        x, y = svg.slot(c, c)
        ox = x + (c if "right" in name else 0)
        oy = y + (c if "bottom" in name else 0)
        inner = []
        if background:
            inner.append('<path d="%s" %s/>' % (rounded_corner(r, c) if r else "M 0,0 H %s V %s H 0 Z" % (c, c), fill(*background)))
        sides = [s for s in ("top", "bottom", "left", "right") if s in name]
        if border and all(s in border_sides for s in sides) and r:
            inner.append('<path d="%s" class="%s" style="fill:none;stroke:currentColor;stroke-opacity:%s;stroke-width:1"/>' % (corner_border(r), border[0], border[1]))
        elif border:
            for s in sides:
                if s in border_sides:
                    if s in ("top", "bottom"):
                        inner.append('<rect x="0" y="0" width="%s" height="1" %s/>' % (c, fill(*border)))
                    else:
                        inner.append('<rect x="0" y="0" width="1" height="%s" %s/>' % (c, fill(*border)))
        if extra:
            inner += extra(name, c, c)
        svg.add('<g id="%s%s" transform="translate(%s,%s) %s"><rect x="0" y="0" width="%s" height="%s" style="fill:none"/>%s</g>' % (
            p, name, ox, oy, ROTATE[name], c, c, "".join(inner)))

    def edge(name):
        w, h = (1, c) if name in ("top", "bottom") else (c, 1)
        x, y = svg.slot(w, h)
        inner = ['<rect x="0" y="0" width="%s" height="%s" style="fill:none"/>' % (w, h)]
        if background:
            inner.append('<rect x="0" y="0" width="%s" height="%s" %s/>' % (w, h, fill(*background)))
        if border and name in border_sides:
            bx = {"top": (0, 0, w, 1), "bottom": (0, h - 1, w, 1), "left": (0, 0, 1, h), "right": (w - 1, 0, 1, h)}[name]
            inner.append('<rect x="%s" y="%s" width="%s" height="%s" %s/>' % (bx + (fill(*border),)))
        if extra:
            inner += extra(name, w, h)
        svg.add('<g id="%s%s" transform="translate(%s,%s)">%s</g>' % (p, name, x, y, "".join(inner)))

    for name in ROTATE:
        corner(name)
    for name in EDGE_SIDES:
        edge(name)
    x, y = svg.slot(c, c)
    centre = '<rect x="0" y="0" width="%s" height="%s" style="fill:none"/>' % (c, c)
    if background:
        centre += '<rect x="0" y="0" width="%s" height="%s" %s/>' % (c, c, fill(*background))
    svg.add('<g id="%scenter" transform="translate(%s,%s)">%s</g>' % (p, x, y, centre))


def hints(svg, prefix, top, bottom, left, right, kind="margin"):
    p = (prefix + "-") if prefix else ""
    for side, size in (("top", top), ("bottom", bottom), ("left", left), ("right", right)):
        w, h = (2, size) if side in ("top", "bottom") else (size, 2)
        x, y = svg.slot(w, h)
        svg.add('<rect id="%shint-%s-%s" x="%s" y="%s" width="%s" height="%s" fill="#ff00ff"/>' % (p, side, kind, x, y, w, h))


def masks(svg, c, r):
    frame(svg, "mask", c, r, ("ColorScheme-Text", 1))


def shadows(svg, top, bottom, side, alpha):
    """Soft shadows around a frame: `top`, `bottom` and `side` px deep, starting at `alpha`."""
    grads = {
        "top": ("0", "1", "0", "0"),
        "bottom": ("0", "0", "0", "1"),
        "left": ("1", "0", "0", "0"),
        "right": ("0", "0", "1", "0"),
    }
    for name, (x1, y1, x2, y2) in grads.items():
        svg.defs.append(
            '<linearGradient id="shade-%s" x1="%s" y1="%s" x2="%s" y2="%s">'
            '<stop offset="0" stop-color="#000" stop-opacity="%s"/><stop offset="1" stop-color="#000" stop-opacity="0"/>'
            "</linearGradient>" % (name, x1, y1, x2, y2, alpha)
        )
    size = {"top": (1, top), "bottom": (1, bottom), "left": (side, 1), "right": (side, 1)}
    for name, (w, h) in size.items():
        x, y = svg.slot(w, h)
        svg.add('<rect id="shadow-%s" x="%s" y="%s" width="%s" height="%s" fill="url(#shade-%s)"/>' % (name, x, y, w, h, name))
    for name in ("topleft", "topright", "bottomleft", "bottomright"):
        w, h = side, (top if "top" in name else bottom)
        x, y = svg.slot(w, h)
        cx = x + (0 if "right" in name else w)
        cy = y + (h if "top" in name else 0)
        rr = max(w, h)
        svg.defs.append(
            '<radialGradient id="shade-%s" cx="%s" cy="%s" r="%s" gradientUnits="userSpaceOnUse" '
            'gradientTransform="translate(%s,%s) scale(%s,%s) translate(%s,%s)">'
            '<stop offset="0" stop-color="#000" stop-opacity="%s"/><stop offset="1" stop-color="#000" stop-opacity="0"/>'
            "</radialGradient>" % (name, cx, cy, rr, cx, cy, w / rr, h / rr, -cx, -cy, alpha)
        )
        svg.add('<rect id="shadow-%s" x="%s" y="%s" width="%s" height="%s" fill="url(#shade-%s)"/>' % (name, x, y, w, h, name))
    hints(svg, "shadow", top, bottom, side, side)


def pane(path, opacity, radius=8, margin=12):
    """Pop-ups: Start, Quick Settings, notifications, the calendar and menus. A rounded pane of the
    window colour with a thin light rim and a soft shadow; translucent over Plasma's blur."""
    svg = Svg()
    frame(svg, "", radius, radius, ("ColorScheme-Background", opacity), border=("ColorScheme-Text", 0.13))
    hints(svg, "", margin, margin, margin, margin)
    masks(svg, radius, radius)
    shadows(svg, top=10, bottom=28, side=20, alpha=0.32)
    svg.write(path)


def tooltip(path, opacity):
    svg = Svg()
    frame(svg, "", 6, 6, ("ColorScheme-Background", opacity), border=("ColorScheme-Text", 0.13))
    hints(svg, "", 6, 6, 8, 8)
    masks(svg, 6, 6)
    shadows(svg, top=6, bottom=14, side=10, alpha=0.28)
    svg.write(path)


def panel(path, opacity):
    """The taskbar: a full-width bar of the window colour with a hairline along its top. Plasma
    leaves out the edges that touch the screen's edges."""
    svg = Svg()
    frame(svg, "", 4, 0, ("ColorScheme-Background", opacity), border=("ColorScheme-Text", 0.09), border_sides=("top",))
    hints(svg, "", 4, 4, 4, 4)
    masks(svg, 4, 0)
    shadows(svg, top=8, bottom=8, side=8, alpha=0.18)
    svg.write(path)


def tasks(path):
    """Task buttons. The app in use has a soft highlight and a Daylight line under its icon, the
    sill; other running apps get a short grey dash; hovering highlights; an app asking for
    attention is tinted. The line sits in the bottom edge, between corners wide enough that it
    stays short on a square taskbar button."""

    def line(colour_attrs, height=3):
        def draw(name, w, h):
            if name != "bottom":
                return []
            return ['<rect x="0" y="%s" width="%s" height="%s" %s/>' % (h - height - 2, w, height, colour_attrs)]
        return draw

    svg = Svg()
    daylight = 'style="fill:%s"' % DAYLIGHT
    dash = fill("ColorScheme-Text", 0.45)
    # (state, corner size, background, line)
    states = [
        ("focus", 13, ("ColorScheme-Text", 0.12), line(daylight)),
        ("normal", 19, None, line(dash)),
        ("minimized", 19, None, line(dash)),
        ("hover", 13, ("ColorScheme-Text", 0.08), None),
        ("attention", 13, ("ColorScheme-NegativeText", 0.30), line(dash)),
    ]
    for state, c, background, extra in states:
        frame(svg, state, c, 6, background, extra=extra)
        hints(svg, state, 4, 4, 4, 4)
    svg.write(path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "orielos")
    # Solid pieces are used without compositing; translucent/ ones over Plasma's blur.
    pane(os.path.join(out, "dialogs", "background.svg"), 0.97)
    pane(os.path.join(out, "translucent", "dialogs", "background.svg"), 0.68)
    tooltip(os.path.join(out, "widgets", "tooltip.svg"), 0.97)
    tooltip(os.path.join(out, "translucent", "widgets", "tooltip.svg"), 0.78)
    panel(os.path.join(out, "widgets", "panel-background.svg"), 0.97)
    panel(os.path.join(out, "translucent", "widgets", "panel-background.svg"), 0.72)
    tasks(os.path.join(out, "widgets", "tasks.svg"))
    print("wrote the OrielOS Plasma theme to", out)


if __name__ == "__main__":
    main()
