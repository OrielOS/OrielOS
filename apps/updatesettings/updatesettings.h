// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "updatecommands.h"
#include "updatestate.h"

#include <QDateTime>
#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

#include <chrono>
#include <functional>
#include <optional>

namespace OrielOSUpdates {

// What the Update settings page shows and does. It reads the state file that orielos-update writes,
// follows the check unit, and runs orielos-update for every change, so it holds no update logic of
// its own. Every string is ready to show.
class UpdateSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // The state was read and describes this boot.
    Q_PROPERTY(bool valid READ isValid NOTIFY changed)
    Q_PROPERTY(QString headline READ headline NOTIFY changed)
    // What orielos-update said about the last check, when there's something to add.
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(QString lastChecked READ lastChecked NOTIFY changed)
    Q_PROPERTY(QString runningVersion READ runningVersion NOTIFY changed)
    Q_PROPERTY(bool checking READ isChecking NOTIFY changed)
    // A command is running; only one runs at a time.
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    Q_PROPERTY(bool updateWaiting READ updateWaiting NOTIFY changed)
    Q_PROPERTY(QString stagedVersion READ stagedVersion NOTIFY changed)
    Q_PROPERTY(bool goingBack READ goingBack NOTIFY changed)
    Q_PROPERTY(bool paused READ isPaused NOTIFY changed)
    Q_PROPERTY(QString pausedUntil READ pausedUntil NOTIFY changed)
    // 0 for stable, 1 for testing. While a change is running it is the chosen channel.
    Q_PROPERTY(int channel READ channel NOTIFY changed)
    Q_PROPERTY(bool hasPrevious READ hasPrevious NOTIFY changed)
    Q_PROPERTY(QString previousVersion READ previousVersion NOTIFY changed)
    // The date the previous version is removed, or empty when that isn't known.
    Q_PROPERTY(QString previousAvailableUntil READ previousAvailableUntil NOTIFY changed)
    // Whether going back and removing are offered; while busy they're offered but wait.
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY changed)
    Q_PROPERTY(bool canRemovePrevious READ canRemovePrevious NOTIFY changed)
    // Apps from the Store update by themselves. While a change is running it is the chosen setting.
    Q_PROPERTY(bool appUpdates READ appUpdates NOTIFY changed)
    // When the apps were last updated, ready to show, or empty.
    Q_PROPERTY(QString appsUpdated READ appsUpdated NOTIFY changed)
    // What went wrong with the last command, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // The pause lengths offered, from minPauseWeeks up.
    Q_PROPERTY(QStringList pauseChoices READ pauseChoices CONSTANT)
    Q_PROPERTY(int minPauseWeeks READ minPauseWeeks CONSTANT)
    // The restart that finishes the update or goes back is scheduled, and when, ready to show.
    Q_PROPERTY(bool restartScheduled READ restartScheduled NOTIFY changed)
    Q_PROPERTY(QString restartAt READ restartAt NOTIFY changed)
    // The days a restart can be scheduled for: today and the six after it.
    Q_PROPERTY(QStringList restartDays READ restartDays NOTIFY changed)
    // Every hour of the day, as the locale shows times, for the active hours and the restart.
    Q_PROPERTY(QStringList hourChoices READ hourChoices CONSTANT)
    Q_PROPERTY(int activeHoursStart READ activeHoursStart NOTIFY changed)
    Q_PROPERTY(int activeHoursEnd READ activeHoursEnd NOTIFY changed)
    Q_PROPERTY(bool autoRestart READ autoRestart NOTIFY changed)
    // The versions this computer ran, newest first: each a map with version and date.
    Q_PROPERTY(QVariantList history READ history NOTIFY changed)
    // What's new in the running version, as Markdown from OrielOS's changelog, or empty.
    Q_PROPERTY(QString whatsNew READ whatsNew NOTIFY changed)

public:
    // Where the page reads from and what it runs. The tests pass their own; the page doesn't own
    // the runner or the monitor passed in.
    struct Environment
    {
        QString statePath;
        QString bootIdPath;
        CommandRunner *runner = nullptr;
        CheckMonitor *monitor = nullptr;
        std::function<QDateTime()> now;
        std::function<void()> restart;
        // OrielOS's changelog, which the image carries.
        QString changelogPath;
        // How long a requested check may take to start before the page stops waiting for it.
        std::chrono::milliseconds checkStartTimeout = std::chrono::seconds(30);
    };

    // The real files, pkexec, systemd and Plasma's restart.
    explicit UpdateSettings(QObject *parent = nullptr);
    explicit UpdateSettings(Environment environment, QObject *parent = nullptr);

    bool isValid() const;
    QString headline() const;
    QString detail() const;
    QString lastChecked() const;
    QString runningVersion() const;
    bool isChecking() const;
    bool isBusy() const { return m_busy; }
    bool updateWaiting() const;
    QString stagedVersion() const;
    bool goingBack() const;
    bool isPaused() const;
    QString pausedUntil() const;
    int channel() const;
    bool hasPrevious() const;
    QString previousVersion() const;
    QString previousAvailableUntil() const;
    bool canGoBack() const;
    bool canRemovePrevious() const;
    bool appUpdates() const;
    QString appsUpdated() const;
    QString error() const { return m_error; }
    QStringList pauseChoices() const;
    int minPauseWeeks() const { return OrielOSUpdates::minPauseWeeks; }
    bool restartScheduled() const;
    QString restartAt() const;
    QStringList restartDays() const;
    QStringList hourChoices() const;
    int activeHoursStart() const { return m_state.activeHoursStart(); }
    int activeHoursEnd() const { return m_state.activeHoursEnd(); }
    bool autoRestart() const { return m_state.autoRestart(); }
    QVariantList history() const;
    QString whatsNew() const;

    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void pause(int weeks);
    Q_INVOKABLE void resume();
    Q_INVOKABLE void setChannel(int channel);
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void removePrevious();
    Q_INVOKABLE void setAppUpdates(bool on);
    Q_INVOKABLE void restart();
    Q_INVOKABLE void clearError();
    // Schedule the restart for <day> days from today (0 to 6) at <hour>:<minute> local time.
    Q_INVOKABLE void scheduleRestart(int day, int hour, int minute);
    Q_INVOKABLE void cancelRestart();
    Q_INVOKABLE void setActiveHours(int start, int end);
    Q_INVOKABLE void setAutoRestart(bool on);

Q_SIGNALS:
    void changed();

private:
    void init();
    void reload();
    void watchStateFile();
    void run(const QStringList &arguments);
    void onFinished(const QStringList &arguments, CommandRunner::Outcome outcome, const QString &detail);
    void onCheckRunningChanged();
    void endPendingCheck();
    QDateTime now() const;
    bool isForThisBoot() const;

    Environment m_environment;
    QString m_bootId;
    UpdateState m_state;
    bool m_busy = false;
    QString m_error;
    // A channel change that is running.
    std::optional<Channel> m_pendingChannel;
    // An app updates change that is running.
    std::optional<bool> m_pendingAppUpdates;
    // A check was asked for and the check unit hasn't started yet.
    bool m_checkPending = false;
    QDateTime m_checkedAtWhenAsked;

    QFileSystemWatcher m_watcher;
    QTimer m_reloadDelay;
    QTimer m_periodicReload;
    QTimer m_checkStartTimer;
};

} // namespace OrielOSUpdates
