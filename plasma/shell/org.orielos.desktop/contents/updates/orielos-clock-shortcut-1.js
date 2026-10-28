// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Gives the clock and bell Win+N, which opens the notifications and the calendar, on taskbars made
// before it had a shortcut. A shortcut the user gave the clock is kept. Plasma runs this once per user.

panels().forEach(function (panel) {
    panel.widgets("org.orielos.clock").forEach(function (clock) {
        if (!clock.globalShortcut) {
            clock.globalShortcut = "Meta+N";
            print("orielos-clock-shortcut-1: gave the clock Win+N");
        }
    });
});
