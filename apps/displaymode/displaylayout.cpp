// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "displaylayout.h"

#include <algorithm>

namespace DisplayLayout {
namespace {

const Screen *mainScreen(const QList<Screen> &screens)
{
    const auto found = std::find_if(screens.cbegin(), screens.cend(), [](const Screen &screen) { return screen.main; });
    return found == screens.cend() ? (screens.isEmpty() ? nullptr : &screens.first()) : &*found;
}

// Puts the screens that are on side by side from x = 0, in the order given.
void placeInRow(QList<Screen> &screens)
{
    int x = 0;
    for (Screen &screen : screens) {
        if (screen.enabled && screen.replicationSource == 0) {
            screen.position = QPoint(x, 0);
            x += screen.logicalSize.width();
        }
    }
}

// The taskbar goes on the main screen when it is on, otherwise on the first screen that is.
void setPriorities(QList<Screen> &screens, int mainId)
{
    unsigned next = 1;
    for (Screen &screen : screens) {
        screen.priority = 0;
    }
    for (Screen &screen : screens) {
        if (screen.enabled && screen.id == mainId) {
            screen.priority = next++;
        }
    }
    for (Screen &screen : screens) {
        if (screen.enabled && screen.id != mainId) {
            screen.priority = next++;
        }
    }
}

} // namespace

Mode currentMode(const QList<Screen> &screens)
{
    const Screen *main = mainScreen(screens);
    if (!main || screens.size() < 2) {
        return Mode::MainOnly;
    }
    const int mainId = main->id;
    const bool othersOn = std::any_of(screens.cbegin(), screens.cend(), [mainId](const Screen &screen) { return screen.id != mainId && screen.enabled; });
    if (!main->enabled) {
        return othersOn ? Mode::OthersOnly : Mode::MainOnly;
    }
    if (!othersOn) {
        return Mode::MainOnly;
    }
    const bool mirrored = std::all_of(screens.cbegin(), screens.cend(),
        [mainId](const Screen &screen) { return screen.id == mainId || !screen.enabled || screen.replicationSource == mainId; });
    return mirrored ? Mode::Duplicate : Mode::Extend;
}

QList<Screen> arrange(QList<Screen> screens, Mode mode)
{
    const Screen *main = mainScreen(screens);
    if (!main) {
        return screens;
    }
    const int mainId = main->id;
    if (screens.size() < 2) {
        mode = Mode::MainOnly;
    }
    // The main screen first, so it is the leftmost when extending.
    std::stable_partition(screens.begin(), screens.end(), [mainId](const Screen &screen) { return screen.id == mainId; });
    for (Screen &screen : screens) {
        const bool isMain = screen.id == mainId;
        screen.replicationSource = 0;
        switch (mode) {
        case Mode::MainOnly:
            screen.enabled = isMain;
            break;
        case Mode::OthersOnly:
            screen.enabled = !isMain;
            break;
        case Mode::Duplicate:
            screen.enabled = true;
            screen.replicationSource = isMain ? 0 : mainId;
            break;
        case Mode::Extend:
            screen.enabled = true;
            break;
        }
    }
    placeInRow(screens);
    // A mirroring screen sits where the screen it mirrors does.
    for (Screen &screen : screens) {
        if (screen.replicationSource != 0) {
            screen.position = QPoint(0, 0);
        }
    }
    setPriorities(screens, mainId);
    return screens;
}
} // namespace DisplayLayout

#include "moc_displaylayout.cpp"
