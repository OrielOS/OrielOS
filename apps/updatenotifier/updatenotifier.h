// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "updatestate.h"

#include <QFileSystemWatcher>
#include <QObject>
#include <QPointer>
#include <QTimer>

class KNotification;
class KStatusNotifierItem;
class QAction;
class QActionGroup;
class QMenu;

namespace UpdateNotifier {

// The tray icon that tells the user about OrielOS updates. It follows the state file that
// orielos-update writes, offers "Restart to update" when a build is staged, and changes the pause
// and channel by running orielos-update through pkexec, where polkit decides who may.
class Notifier : public QObject
{
    Q_OBJECT

public:
    Notifier(const QString &statePath, const QString &bootIdPath, QObject *parent = nullptr);

private:
    void reload();
    void updateItem();
    void showReadyNotification();
    void showErrorNotification(const QString &detail);
    void restartToUpdate();
    void runUpdateCommand(const QStringList &arguments);
    void watchStateFile();
    QMenu *buildMenu();

    QString m_statePath;
    QString m_bootId;
    UpdateState m_state;
    // The staged build already announced in this session, so "Later" isn't followed by the same
    // notification at the next check.
    QString m_announcedDigest;

    KStatusNotifierItem *m_item = nullptr;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadDelay;
    QTimer m_periodicReload;
    QPointer<KNotification> m_readyNotification;

    QAction *m_restartAction = nullptr;
    QAction *m_pausedLine = nullptr;
    QAction *m_resumeAction = nullptr;
    QMenu *m_pauseMenu = nullptr;
    QActionGroup *m_channelGroup = nullptr;
    QAction *m_stableAction = nullptr;
    QAction *m_testingAction = nullptr;
};

} // namespace UpdateNotifier
