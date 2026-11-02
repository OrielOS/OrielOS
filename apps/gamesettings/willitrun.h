// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringList>

namespace OrielOSGames {

// Whether a game with anti-cheat runs on Linux.
struct Verdict
{
    enum class Status : quint8 {
        // Works: the publisher supports Linux, or the game runs without its support.
        Works,
        // The publisher's anti-cheat refuses Linux players on purpose.
        Blocked,
        // Its anti-cheat doesn't support Linux yet.
        Broken,
        // Support is planned.
        Planned,
    };

    QString name;
    Status status = Status::Planned;
    QStringList antiCheats;
    bool native = false;
    // One line on why, in plain words.
    QString reason;
};

// Will it run?: AreWeAntiCheatYet's list of games with anti-cheat (MIT), with OrielOS's own
// tested verdicts winning over it. No ProtonDB data is used.
class WillItRun
{
public:
    // games: AreWeAntiCheatYet's games.json, or OrielOS's trimmed copy of it ({ fetched, games });
    // overrides: data/will-it-run-overrides.json.
    static WillItRun fromJson(const QByteArray &games, const QByteArray &overrides = { });

    bool isEmpty() const { return m_verdicts.isEmpty(); }
    // When the list was fetched, as written in the copy, or empty.
    QString fetched() const { return m_fetched; }
    // The games whose name contains the words, an exact match first, at most limit.
    QList<Verdict> search(const QString &words, int limit = 20) const;
    // OrielOS's trimmed copy of the list, for the cache: name, status, anti-cheats and native.
    static QByteArray trimmed(const QByteArray &games, const QString &fetched);

private:
    QList<Verdict> m_verdicts;
    QString m_fetched;
};

} // namespace OrielOSGames
