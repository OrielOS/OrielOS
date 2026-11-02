// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "fixit.h"
#include "gamesettings.h"

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>
#include <qqmlintegration.h>

namespace OrielOSGames {

// Fix it, for one Steam game at a time: starts the game once with Proton's log turned on, reads
// the log once the game has closed, says what most likely went wrong with fixes for it, applies
// one, and starts the game again to see whether it now keeps running for two minutes. Every
// change can be undone exactly, and what worked is kept on this PC to order later suggestions.
// Steam's settings change only while Steam is closed, so Fix it closes Steam when it needs to.
class FixIt : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(OrielOSGames::GameSettings *settings READ settings WRITE setSettings NOTIFY changed)
    // idle, blocked, starting, playing, closing, diagnosed, nothing-found, no-log, verifying,
    // worked, failed or undone.
    Q_PROPERTY(QString state READ state NOTIFY changed)
    // The game Fix it is working on.
    Q_PROPERTY(QString appId READ appId NOTIFY changed)
    // Why a game can't be fixed, or what went wrong, in plain words.
    Q_PROPERTY(QString message READ message NOTIFY changed)
    // { id, cause, fixes: [{ id, explanation, advice }] } for each likely cause, best fix first.
    Q_PROPERTY(QVariantList causes READ causes NOTIFY changed)

public:
    explicit FixIt(QObject *parent = nullptr);

    GameSettings *settings() const { return m_settings; }
    void setSettings(GameSettings *settings);
    QString state() const { return m_state; }
    QString appId() const { return m_appId; }
    QString message() const { return m_message; }
    QVariantList causes() const;

    // Starts the game once with Proton's log on. Steam has to be closed.
    Q_INVOKABLE void start(const QString &appId, const QString &gameName);
    // Applies one of the fixes found, then starts the game to check it. Steam has to be closed.
    Q_INVOKABLE void apply(const QString &diagnosisId, const QString &fixId);
    Q_INVOKABLE bool canUndo(const QString &appId) const;
    // Puts back what the last fix changed. Steam has to be closed.
    Q_INVOKABLE void undo(const QString &appId);
    Q_INVOKABLE void reset();

Q_SIGNALS:
    void changed();

private:
    void tick();
    void setState(const QString &state, const QString &message = { });
    void launch();
    void diagnose();
    void finishCheck(bool worked);
    QString folder() const;

    QPointer<GameSettings> m_settings;
    FixItRules m_rules;
    QTimer m_timer;
    QString m_state = QStringLiteral("idle");
    QString m_appId;
    QString m_message;
    // The game's launch options before Proton's log was turned on, put back exactly afterwards.
    QString m_original;
    QList<Diagnosis> m_causes;
    QDateTime m_deadline;
    QDateTime m_seenAt;
    bool m_seen = false;
    // When Fix it last asked Steam to close.
    QDateTime m_closeAskedAt;
    // The fix being checked.
    QString m_diagnosisId;
    QString m_fixId;
};

} // namespace OrielOSGames
