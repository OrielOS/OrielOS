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
class QMenu;

namespace UpdateNotifier {

// The tray icon that tells the user about OrielOS updates. It follows the state file that
// orielos-update writes and shows only while a build is staged or going back is queued, offering
// "Restart to update"; with nothing waiting for a restart there is no icon at all. It also tells
// the user when an update that didn't start was undone. Everything else is on the Update settings
// page, which clicking the icon opens.
class Notifier : public QObject
{
    Q_OBJECT

public:
    Notifier(const QString &statePath, const QString &bootIdPath, QObject *parent = nullptr);

private:
    void reload();
    void updateItem();
    // The icon, made when there's something to restart for and taken away when there isn't.
    void createItem();
    void removeItem();
    void showReadyNotification();
    void showGoBackNotification();
    void showUndoneNotification();
    void restart();
    void openSettings();
    void watchStateFile();
    QMenu *buildMenu();

    QString m_statePath;
    QString m_bootId;
    OrielOSUpdates::UpdateState m_state;
    // The staged build, and the previous build being gone back to, already announced in this
    // session, so "Later" isn't followed by the same notification at the next change.
    QString m_announcedDigest;
    QString m_announcedGoBackDigest;
    // Undoing an update is told once per session.
    bool m_announcedUndone = false;

    KStatusNotifierItem *m_item = nullptr;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadDelay;
    QTimer m_periodicReload;
    QPointer<KNotification> m_readyNotification;
    QPointer<KNotification> m_goBackNotification;

    QAction *m_restartAction = nullptr;
};

} // namespace UpdateNotifier
