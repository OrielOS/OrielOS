// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// What chronyd says about the server it follows, from "chronyc -c tracking": one line of
// comma-separated fields, where field 1 is the reference ID in hex, field 2 the server's name or
// address, field 4 the time of the last measurement in seconds since 1970 and field 14 the leap
// status.
struct SyncStatus
{
    // The line could be read.
    bool valid = false;
    // chronyd follows a server: there's a reference time, and the reference is neither none
    // (00000000) nor the PC's own clock (7F7F0101), and the leap status isn't "Not synchronised".
    bool synchronised = false;
    QString server;
    QDateTime lastMeasurement;

    static SyncStatus parse(const QByteArray &csv);
};

// What systemd-timedated says about the clock.
struct ClockState
{
    // timedated answered.
    bool valid = false;
    // Network time (chronyd) keeps the clock right.
    bool ntp = false;
    // A network time service is installed, so ntp can be turned on.
    bool canNtp = false;
    // The time zone's name, such as Europe/London.
    QString timeZone;
};

// Settings › Time & language › Date & time: the time, set automatically or not, the time zone, set
// automatically from the PC's location or not, and synchronising the clock now. It reads and
// changes the clock through systemd-timedated, and runs /usr/libexec/orielos/auto-timezone and
// /usr/libexec/orielos/time-sync through pkexec, so it holds no clock logic of its own. Every
// string is ready to show.
class DateTimeSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // The time and date now, in the user's formats and the PC's time zone; they change every second.
    Q_PROPERTY(QString time READ time NOTIFY clockTicked FINAL)
    Q_PROPERTY(QString date READ date NOTIFY clockTicked FINAL)
    // The time zone, such as "Europe/London (UTC+01:00)".
    Q_PROPERTY(QString timeZone READ timeZone NOTIFY clockTicked FINAL)

    // Network time keeps the clock right. While it's being changed, this is the state asked for.
    Q_PROPERTY(bool autoTime READ autoTime NOTIFY changed FINAL)
    // Whether the switch can change it: a network time service is installed and no change is
    // running.
    Q_PROPERTY(bool canChangeAutoTime READ canChangeAutoTime NOTIFY changed FINAL)
    // The time zone follows the PC's location. While it's being changed, this is the state asked for.
    Q_PROPERTY(bool autoTimeZone READ autoTimeZone NOTIFY changed FINAL)
    Q_PROPERTY(bool canChangeAutoTimeZone READ canChangeAutoTimeZone NOTIFY changed FINAL)

    // Sync now is running.
    Q_PROPERTY(bool syncing READ isSyncing NOTIFY changed FINAL)
    // Sync now can run: the time is set automatically and nothing else is running.
    Q_PROPERTY(bool canSync READ canSync NOTIFY changed FINAL)
    // How the last Sync now went, or empty.
    Q_PROPERTY(QString syncResult READ syncResult NOTIFY changed FINAL)
    Q_PROPERTY(bool syncFailed READ syncFailed NOTIFY changed FINAL)
    // When the clock was last synchronised, and with which server.
    Q_PROPERTY(QString lastSync READ lastSync NOTIFY changed FINAL)

    // What went wrong with the last change of a switch, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)

public:
    struct Environment
    {
        // The file that says the time zone is set automatically.
        QString autoTimeZonePath;
        // Runs a program and calls done with its exit code, what it wrote to stdout and the first
        // line it wrote to stderr. pkexec's 126 and 127 mean the password prompt was dismissed or
        // the user isn't allowed.
        std::function<void(
            const QString &program, const QStringList &arguments, std::function<void(int exitCode, const QByteArray &output, const QString &detail)> done)>
            run;
        // Reads timedated's properties and calls done with them.
        std::function<void(std::function<void(const ClockState &state)> done)> readClock;
        // Calls timedated's SetNTP, letting polkit ask for a password, and calls done with the
        // D-Bus error's name and message, both empty when it worked.
        std::function<void(bool enable, std::function<void(const QString &errorName, const QString &errorMessage)> done)> setNtp;
        // The time now.
        std::function<QDateTime()> now;
    };

    // timedated on the system bus, pkexec, chronyc and the real clock.
    explicit DateTimeSettings(QObject *parent = nullptr);
    DateTimeSettings(Environment environment, QObject *parent);

    QString time() const;
    QString date() const;
    QString timeZone() const;
    bool autoTime() const { return m_pendingAutoTime >= 0 ? m_pendingAutoTime == 1 : m_clock.ntp; }
    bool canChangeAutoTime() const;
    bool autoTimeZone() const { return m_pendingAutoTimeZone >= 0 ? m_pendingAutoTimeZone == 1 : m_autoTimeZone; }
    bool canChangeAutoTimeZone() const { return m_pendingAutoTimeZone < 0; }
    bool isSyncing() const { return m_syncing; }
    bool canSync() const;
    QString syncResult() const { return m_syncResult; }
    bool syncFailed() const { return m_syncFailed; }
    QString lastSync() const;
    QString error() const { return m_error; }

    Q_INVOKABLE void setAutoTime(bool on);
    Q_INVOKABLE void setAutoTimeZone(bool on);
    Q_INVOKABLE void syncNow();
    // Reads the clock's state, the time zone setting and chronyd's status again.
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void changed();
    void clockTicked();

private Q_SLOTS:
    // timedated changed a property.
    void reloadClock();

private:
    void init();
    void readAutoTimeZone();
    void readSyncStatus();
    // The time now, in the PC's time zone.
    QDateTime localNow() const;
    // Fires just after each second starts, so the seconds change together with the system clock's.
    void scheduleTick();

    Environment m_environment;
    ClockState m_clock;
    bool m_autoTimeZone = false;
    // A switch being changed: -1 for none, else the state asked for, 0 or 1.
    int m_pendingAutoTime = -1;
    int m_pendingAutoTimeZone = -1;
    bool m_syncing = false;
    QString m_syncResult;
    bool m_syncFailed = false;
    SyncStatus m_syncStatus;
    QString m_error;
    QTimer m_tick;
    // chronyd measures every minute or more; its status is read again this often while the page is
    // open.
    QTimer m_refresh;
};

} // namespace OrielOSSettingsPages
