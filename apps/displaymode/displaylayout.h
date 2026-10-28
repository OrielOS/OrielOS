// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QObject>
#include <QPoint>
#include <QSize>

// How the screens are used, as Windows + P offers it: the computer's own screen only, the same
// picture on every screen, one desktop across all of them, or the other screens only.
namespace DisplayLayout {
Q_NAMESPACE

enum class Mode {
    MainOnly,
    Duplicate,
    Extend,
    OthersOnly,
};
Q_ENUM_NS(Mode)

// One connected screen, as far as the layout needs it. The main screen is the computer's built-in
// one, or the first screen when none is built in.
struct Screen
{
    int id = 0;
    bool main = false;
    bool enabled = false;
    // The size it takes on the desktop, at the mode and scale it has or would have when turned on.
    QSize logicalSize;
    QPoint position;
    // The screen it shows the same picture as, or 0.
    int replicationSource = 0;
    // 1 for the screen with the taskbar, then 2 and up; 0 while it is off.
    unsigned priority = 0;

    bool operator==(const Screen &other) const = default;
};

// The mode the screens are in now. A single screen is always MainOnly.
Mode currentMode(const QList<Screen> &screens);

// The screens arranged for a mode: which are on, where they sit (left to right from the main
// screen, top edges aligned), which mirror the main screen, and which has the taskbar. With a
// single screen every mode is MainOnly.
QList<Screen> arrange(QList<Screen> screens, Mode mode);
} // namespace DisplayLayout
