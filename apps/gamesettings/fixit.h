// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace OrielOSGames {

// One change Fix it can make to a game, or advise.
struct Fix
{
    enum class Kind : quint8 {
        // Run the game with the compatibility tool in value; empty is Steam's default.
        Tool,
        // Add the NAME=value in value to the launch options.
        Variable,
        // Turn off the Game Settings switch named in value (see GameOptions).
        TurnOff,
        // Move the game's shader cache aside, so Steam builds it again.
        ClearShaderCache,
        // Something only the user can do; nothing is applied.
        Advice,
    };

    QString id;
    Kind kind = Kind::Advice;
    QString value;
    // What the fix changes, in plain words.
    QString explanation;
};

// A likely cause found in a game's Proton log, with its fixes, best first.
struct Diagnosis
{
    QString id;
    QString cause;
    QList<Fix> fixes;
};

// The PC a fix was tried on, so suggestions are ranked by what worked on matching hardware.
struct SystemFacts
{
    QString gpu;
    QString driver;
    QString kernel;

    // Reads the running PC's graphics card, its driver's version and the kernel.
    static SystemFacts current();
};

// One try of a fix, kept on this PC only.
struct Attempt
{
    QString appId;
    QString diagnosis;
    QString fix;
    QString tool;
    SystemFacts system;
    bool worked = false;
    QDateTime when;
};

// Fix it's failure signatures (data/fix-it.json) and what they match.
class FixItRules
{
public:
    static FixItRules fromJson(const QByteArray &json);
    bool isEmpty() const { return m_signatures.isEmpty(); }

    // The causes the log shows, in the data file's order. Fixes that would change nothing for this
    // game are left out: turning off a switch that's off, a tool it already uses, or a tool that
    // isn't installed (installedTools are compatibility tool ids). A cause left with no fix, and a
    // signature whose switch is off, are left out too.
    QList<Diagnosis> diagnose(const QString &log, const QString &launchOptions, const QString &tool, const QStringList &installedTools) const;

private:
    struct Signature
    {
        QString id;
        QString when;
        QString cause;
        QList<QRegularExpression> patterns;
        QList<Fix> fixes;
    };
    QList<Signature> m_signatures;
};

// The fixes in the order to suggest them: those that worked most often for this cause on the same
// graphics card and driver series first, untried ones in their own order after those that worked,
// and those that only failed last.
QList<Fix> rankFixes(const QList<Fix> &fixes, const QString &diagnosis, const QList<Attempt> &history, const SystemFacts &system);

// Steam's launch options with NAME=value before %command% (adding %command% when there's none),
// or without it. Everything else stays as it was typed.
QString withVariable(const QString &launchOptions, const QString &assignment);
QString withoutVariable(const QString &launchOptions, const QString &assignment);

// The tries kept in a file (JSON), oldest first; a missing or broken file is no tries.
QList<Attempt> readAttempts(const QString &path);
bool appendAttempt(const QString &path, const Attempt &attempt);

// What a fix changed in a game, to put back exactly: its tool, its launch options as they were
// typed, and where its shader cache was moved to, if it was.
struct Undo
{
    QString appId;
    QString fix;
    QString tool;
    QString launchOptions;
    QString shaderCache;
    QString shaderCacheMovedTo;

    bool isValid() const { return !appId.isEmpty(); }
    static Undo read(const QString &path);
    bool write(const QString &path) const;
};

} // namespace OrielOSGames
