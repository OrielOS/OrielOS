// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "steamlibrary.h"
#include "willitrun.h"

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlintegration.h>

namespace OrielOSGames {

// What Game Settings shows and changes: the games in Steam from the Store, each with its
// compatibility tool and switches (see GameOptions). Changes are written only while Steam is
// closed, since Steam rewrites its settings when it quits.
class GameSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool steamInstalled READ steamInstalled NOTIFY changed)
    Q_PROPERTY(bool steamRunning READ steamRunning NOTIFY changed)
    // { appId, name, art } for each game, by name.
    Q_PROPERTY(QVariantList games READ games NOTIFY changed)
    // { id, name } for each compatibility tool, Steam's default (an empty id) first.
    Q_PROPERTY(QVariantList tools READ tools NOTIFY changed)
    // What went wrong with the last change, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    // Goes up with every change, so the page reads a game's settings again.
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    // When Will it run?'s list was fetched, as written in it.
    Q_PROPERTY(QString willItRunDate READ willItRunDate NOTIFY changed)

public:
    explicit GameSettings(QObject *parent = nullptr);

    bool steamInstalled() const { return m_library.installed(); }
    bool steamRunning() const { return m_steamRunning; }
    QVariantList games() const;
    QVariantList tools() const;
    QString error() const { return m_error; }
    bool isBusy() const { return m_busy; }
    int revision() const { return m_revision; }
    QString willItRunDate() const { return m_willItRun.fetched(); }

    // { name, status (works, blocked, broken or planned), reason, antiCheats } for the games whose
    // name contains the words.
    Q_INVOKABLE QVariantList willItRun(const QString &words) const;

    // { tool, dlssUpgrade, waylandHdr, gamescope, fpsOverlay, gameMode, descriptorHeap } for a game.
    Q_INVOKABLE QVariantMap settingsFor(const QString &appId) const;
    Q_INVOKABLE void setTool(const QString &appId, const QString &toolId);
    // Turns one switch on or off; the name is one of settingsFor's keys.
    Q_INVOKABLE void setOption(const QString &appId, const QString &name, bool on);
    // Whether a switch needs an add-on from the Store that isn't installed: "gamescope" or "overlay".
    Q_INVOKABLE QString missingAddon(const QString &name) const;
    Q_INVOKABLE void installAddon(const QString &addon);
    // Asks Steam to quit, so changes can be written.
    Q_INVOKABLE void closeSteam();
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void changed();

private:
    void checkSteam();
    void loadWillItRun();
    void fetchWillItRun();
    void runDetached(const QString &program, const QStringList &arguments);

    SteamLibrary m_library;
    QList<SteamGame> m_games;
    QList<CompatTool> m_tools;
    bool m_steamRunning = false;
    bool m_busy = false;
    QString m_error;
    QTimer m_watch;
    int m_revision = 0;
    WillItRun m_willItRun;
};

} // namespace OrielOSGames
