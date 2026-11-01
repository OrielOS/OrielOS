// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <qqmlintegration.h>

// The Run box's window model: the history of what was run, and running what's typed. The history
// is kept in orielos-runrc.
class RunBoxModel : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Newest first.
    Q_PROPERTY(QStringList history READ history NOTIFY historyChanged FINAL)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged FINAL)

public:
    explicit RunBoxModel(QObject *parent = nullptr);

    QStringList history() const { return m_history; }
    bool isBusy() const { return m_busy; }

    // Opens or runs what was typed. Started emits when it worked, failed with what to tell the user
    // when it didn't.
    Q_INVOKABLE void run(const QString &text);

Q_SIGNALS:
    void historyChanged();
    void busyChanged();
    void started();
    void failed(const QString &message);

private:
    void finish(const QString &text, bool ok);

    QStringList m_history;
    bool m_busy = false;
};
