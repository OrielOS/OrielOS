// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "launchoptions.h"

#include <QStringList>

namespace OrielOSGames {

namespace {

const QString command = QStringLiteral("%command%");

// Steam's launch options as words: before %command% come variables and wrapper programs, after it
// the game's own arguments. Without %command%, everything typed is the game's arguments.
struct Split
{
    QStringList before;
    QStringList after;
    bool hadCommand = false;
};

Split split(const QString &options)
{
    Split out;
    const QStringList words = options.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    const qsizetype at = words.indexOf(command);
    if (at < 0) {
        out.after = words;
        return out;
    }
    out.hadCommand = true;
    out.before = words.mid(0, at);
    out.after = words.mid(at + 1);
    return out;
}

bool hasVariable(const QStringList &before, const QString &assignment)
{
    return before.contains(assignment);
}

// The gamescope wrapper: "gamescope", its options, then "--".
qsizetype gamescopeAt(const QStringList &before)
{
    return before.indexOf(QStringLiteral("gamescope"));
}

} // namespace

GameOptions GameOptions::read(const QString &launchOptions)
{
    const Split words = split(launchOptions);
    GameOptions options;
    options.dlssUpgrade = hasVariable(words.before, QStringLiteral("PROTON_DLSS_UPGRADE=1"));
    options.waylandHdr = hasVariable(words.before, QStringLiteral("PROTON_ENABLE_WAYLAND=1"));
    options.fpsOverlay = hasVariable(words.before, QStringLiteral("MANGOHUD=1"));
    options.descriptorHeap = hasVariable(words.before, QStringLiteral("VKD3D_CONFIG=descriptor_heap"));
    options.gameMode = words.before.contains(QStringLiteral("gamemoderun"));
    options.gamescope = gamescopeAt(words.before) >= 0;
    return options;
}

QString GameOptions::apply(const QString &launchOptions) const
{
    Split words = split(launchOptions);
    QStringList &before = words.before;

    // Take out every part these switches own, then put back those that are on, variables first.
    const QStringList variables = { QStringLiteral("PROTON_DLSS_UPGRADE=1"), QStringLiteral("PROTON_ENABLE_WAYLAND=1"), QStringLiteral("MANGOHUD=1"),
        QStringLiteral("VKD3D_CONFIG=descriptor_heap") };
    for (const QString &variable : variables) {
        before.removeAll(variable);
    }
    before.removeAll(QStringLiteral("gamemoderun"));
    if (const qsizetype at = gamescopeAt(before); at >= 0) {
        // Only OrielOS's own form is removed; a gamescope line the user wrote themselves stays.
        if (before.mid(at, 3) == QStringList { QStringLiteral("gamescope"), QStringLiteral("-f"), QStringLiteral("--") }) {
            before.remove(at, 3);
        }
    }

    QStringList ours;
    if (dlssUpgrade) {
        ours.append(QStringLiteral("PROTON_DLSS_UPGRADE=1"));
    }
    if (waylandHdr) {
        ours.append(QStringLiteral("PROTON_ENABLE_WAYLAND=1"));
    }
    if (fpsOverlay) {
        ours.append(QStringLiteral("MANGOHUD=1"));
    }
    if (descriptorHeap) {
        ours.append(QStringLiteral("VKD3D_CONFIG=descriptor_heap"));
    }
    // Variables stay at the front; wrappers go straight before the game, GameMode outermost.
    qsizetype firstWrapper = 0;
    while (firstWrapper < before.size() && before.at(firstWrapper).contains(QLatin1Char('='))) {
        ++firstWrapper;
    }
    QStringList wrappers;
    if (gameMode) {
        wrappers.append(QStringLiteral("gamemoderun"));
    }
    if (gamescope && gamescopeAt(before) < 0) {
        wrappers << QStringLiteral("gamescope") << QStringLiteral("-f") << QStringLiteral("--");
    }
    QStringList result = before.mid(0, firstWrapper) + ours + wrappers + before.mid(firstWrapper);

    if (result.isEmpty()) {
        // Nothing before the game: no %command% is needed unless the user had one.
        return (words.hadCommand ? QStringList { command } + words.after : words.after).join(QLatin1Char(' '));
    }
    return (result + QStringList { command } + words.after).join(QLatin1Char(' '));
}

} // namespace OrielOSGames
