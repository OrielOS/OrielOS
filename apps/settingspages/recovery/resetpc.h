// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// orielos-reset's state file, /var/lib/orielos/reset/state.json, as the Recovery page reads it.
struct ResetState
{
    enum class Phase {
        Idle,
        // Getting the reset ready: finding the build, downloading it, setting up the new system.
        Checking,
        Downloading,
        Preparing,
        // Ready for the restart.
        Ready,
        Failed,
        Cancelled,
        // This PC was reset, at the start before this one or earlier.
        Done,
    };

    Phase phase = Phase::Idle;
    QString message;
    // keep or erase, or empty.
    QString mode;
    QString version;
    qint64 downloaded = 0;
    qint64 total = 0;
    // The start the state was written in.
    QString bootId;

    // Reads the file's JSON; anything that isn't a state reads as idle.
    static ResetState parse(const QByteArray &json);
};

// Settings › System › Recovery: Reset this PC, keeping accounts and home folders or removing
// everything. It reads the state orielos-reset writes and runs orielos-reset through pkexec, so it
// holds no reset logic of its own. Every string is ready to show.
class ResetPC : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // A reset is being got ready in this start: the page shows its progress and Cancel.
    Q_PROPERTY(bool working READ isWorking NOTIFY changed)
    // A reset is ready and happens at the next restart.
    Q_PROPERTY(bool ready READ isReady NOTIFY changed)
    // Whether the reset keeps files (true) or removes everything (false), while working or ready.
    Q_PROPERTY(bool keepsFiles READ keepsFiles NOTIFY changed)
    // What it's doing now, as a sentence.
    Q_PROPERTY(QString status READ status NOTIFY changed)
    // 0 to 1 while downloading, or -1 when the step has no measure.
    Q_PROPERTY(double progress READ progress NOTIFY changed)
    // "1.2 GB of 3.7 GB" while downloading, or empty.
    Q_PROPERTY(QString progressText READ progressText NOTIFY changed)
    // What happened to the last reset: it failed, was cancelled or was done. Empty otherwise.
    Q_PROPERTY(QString outcome READ outcome NOTIFY changed)
    Q_PROPERTY(bool outcomeIsError READ outcomeIsError NOTIFY changed)
    // A pkexec command is running; only one runs at a time.
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    // What went wrong with the last command, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    struct Environment
    {
        QString statePath;
        QString bootIdPath;
        // Runs orielos-reset with these arguments and calls done with its exit code and the first
        // line it wrote to stderr. pkexec's 126 and 127 mean the password prompt was dismissed.
        std::function<void(const QStringList &arguments, std::function<void(int exitCode, const QString &detail)> done)> run;
        std::function<void()> restart;
    };

    // The real state file, pkexec and Plasma's restart.
    explicit ResetPC(QObject *parent = nullptr);
    ResetPC(Environment environment, QObject *parent);

    bool isWorking() const;
    bool isReady() const;
    bool keepsFiles() const { return m_state.mode != QLatin1String("erase"); }
    QString status() const;
    double progress() const;
    QString progressText() const;
    QString outcome() const;
    bool outcomeIsError() const;
    bool isBusy() const { return m_busy; }
    QString error() const { return m_error; }

    // Start getting a reset ready: keeping accounts and home folders, or removing everything.
    Q_INVOKABLE void reset(bool keepFiles);
    // Stop a reset being got ready, or undo one that is ready.
    Q_INVOKABLE void cancel();
    // Restart now, to reset.
    Q_INVOKABLE void restart();
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void changed();

private:
    void init();
    // Whether the state was written in this start.
    bool isCurrent() const;
    void run(const QStringList &arguments);
    void onFinished(const QString &command, int exitCode, const QString &detail);

    Environment m_environment;
    ResetState m_state;
    QString m_bootId;
    bool m_busy = false;
    QString m_error;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadDelay;
    // The state changes every second while downloading; the watcher can miss a replaced file.
    QTimer m_pollWhileWorking;
};

} // namespace OrielOSSettingsPages
