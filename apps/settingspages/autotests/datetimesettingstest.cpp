// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "datetimesettings.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QTimeZone>

using namespace OrielOSSettingsPages;

namespace {

// chronyc -c tracking, synchronised to a server, as chrony's manual describes the fields.
QByteArray synchronisedAt(qint64 seconds, const char *server = "ntp.example.org")
{
    return QStringLiteral("C0A80101,%1,3,%2.471107394,-0.000016084,-0.000000519,0.000004434,-21.519,-0.003,0.040,0.000356485,0.000569195,1064.4,Normal\n")
        .arg(QLatin1String(server))
        .arg(seconds)
        .toUtf8();
}

constexpr auto notSynchronised = "00000000,,0,0.000000000,0.000000000,0.000000000,0.000000000,0.000,0.000,0.000,1.000000000,1.000000000,0.0,Not synchronised\n";

// Thursday 5 November 2026, 14:03:09.250 UTC: GMT in London.
QDateTime november()
{
    return QDateTime(QDate(2026, 11, 5), QTime(14, 3, 9, 250), QTimeZone::UTC);
}

} // namespace

class DateTimeSettingsTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    ClockState m_clock;
    QDateTime m_now;
    QByteArray m_tracking;
    int m_chronycExit = 0;
    int m_chronycRuns = 0;
    QString m_lastProgram;
    QStringList m_lastRun;
    std::function<void(int, const QByteArray &, const QString &)> m_done;
    QList<bool> m_ntpCalls;
    std::function<void(const QString &, const QString &)> m_ntpDone;

    QString autoTimeZonePath() const { return m_dir.filePath(QStringLiteral("auto-timezone")); }

    void turnOnAutoTimeZone()
    {
        QFile file(autoTimeZonePath());
        QVERIFY(file.open(QIODevice::WriteOnly));
    }

    // chronyc answers at once; pkexec waits for the test to call m_done.
    DateTimeSettings::Environment environment()
    {
        return DateTimeSettings::Environment {
            autoTimeZonePath(),
            [this](const QString &program, const QStringList &arguments, std::function<void(int, const QByteArray &, const QString &)> done) {
                if (program == QLatin1String("chronyc")) {
                    QCOMPARE(arguments, (QStringList { QStringLiteral("-c"), QStringLiteral("-N"), QStringLiteral("tracking") }));
                    ++m_chronycRuns;
                    done(m_chronycExit, m_chronycExit == 0 ? m_tracking : QByteArray(), { });
                    return;
                }
                m_lastProgram = program;
                m_lastRun = arguments;
                m_done = std::move(done);
            },
            [this](std::function<void(const ClockState &)> done) { done(m_clock); },
            [this](bool enable, std::function<void(const QString &, const QString &)> done) {
                m_ntpCalls.append(enable);
                m_ntpDone = std::move(done);
            },
            [this] { return m_now; },
        };
    }

private Q_SLOTS:
    void init()
    {
        QFile::remove(autoTimeZonePath());
        m_clock = ClockState { true, true, true, QStringLiteral("Europe/London") };
        m_now = november();
        m_tracking = synchronisedAt(november().toSecsSinceEpoch() - 240);
        m_chronycExit = 0;
        m_chronycRuns = 0;
        m_lastProgram.clear();
        m_lastRun.clear();
        m_done = nullptr;
        m_ntpCalls.clear();
        m_ntpDone = nullptr;
    }

    void parsesChronyTracking()
    {
        const SyncStatus synced = SyncStatus::parse(synchronisedAt(1700000000));
        QVERIFY(synced.valid);
        QVERIFY(synced.synchronised);
        QCOMPARE(synced.server, QStringLiteral("ntp.example.org"));
        QCOMPARE(synced.lastMeasurement.toSecsSinceEpoch(), qint64(1700000000));

        const SyncStatus notSynced = SyncStatus::parse(notSynchronised);
        QVERIFY(notSynced.valid);
        QVERIFY(!notSynced.synchronised);
        QVERIFY(notSynced.server.isEmpty());

        // The PC's own clock isn't a server, whatever the leap status says.
        const SyncStatus local = SyncStatus::parse("7F7F0101,,10,1700000000.000000000,0,0,0,0,0,0,0,0,0,Normal\n");
        QVERIFY(local.valid);
        QVERIFY(!local.synchronised);

        // chronyc couldn't name the server.
        QVERIFY(SyncStatus::parse(synchronisedAt(1700000000, "?")).server.isEmpty());
    }

    void ignoresWhatIsntTracking()
    {
        QVERIFY(!SyncStatus::parse("506 Cannot talk to daemon\n").valid);
        QVERIFY(!SyncStatus::parse("").valid);
        QVERIFY(!SyncStatus::parse("C0A80101,ntp.example.org").valid);
        QVERIFY(!SyncStatus::parse("not hex!,ntp.example.org,3,1700000000.0,0").valid);
        QVERIFY(!SyncStatus::parse("C0A80101,ntp.example.org,3,yesterday,0").valid);
    }

    void showsTheClockInThePCsTimeZone()
    {
        DateTimeSettings settings(environment(), nullptr);
        QCOMPARE(settings.time(), QStringLiteral("14:03:09"));
        QVERIFY(settings.date().contains(QStringLiteral("5 November 2026")));
        QCOMPARE(settings.timeZone(), QStringLiteral("Europe/London (UTC)"));

        m_now = QDateTime(QDate(2026, 7, 1), QTime(12, 0), QTimeZone::UTC);
        QCOMPARE(settings.time(), QStringLiteral("13:00:00"));
        QCOMPARE(settings.timeZone(), QStringLiteral("Europe/London (UTC+1)"));

        m_clock.timeZone = QStringLiteral("America/New_York");
        settings.reload();
        QCOMPARE(settings.timeZone(), QStringLiteral("America/New York (UTC") + QChar(0x2212) + QStringLiteral("4)"));

        m_clock.timeZone = QStringLiteral("Asia/Kolkata");
        settings.reload();
        QCOMPARE(settings.time(), QStringLiteral("17:30:00"));
        QCOMPARE(settings.timeZone(), QStringLiteral("Asia/Kolkata (UTC+5:30)"));

        // UTC is only an offset.
        m_clock.timeZone = QStringLiteral("Etc/UTC");
        settings.reload();
        QCOMPARE(settings.timeZone(), QStringLiteral("UTC"));
    }

    void readsTheSwitches()
    {
        DateTimeSettings off(environment(), nullptr);
        QVERIFY(off.autoTime());
        QVERIFY(off.canChangeAutoTime());
        QVERIFY(!off.autoTimeZone());
        QVERIFY(off.canSync());

        turnOnAutoTimeZone();
        m_clock.ntp = false;
        DateTimeSettings on(environment(), nullptr);
        QVERIFY(!on.autoTime());
        QVERIFY(on.autoTimeZone());
        // Syncing needs network time.
        QVERIFY(!on.canSync());
        on.syncNow();
        QVERIFY(m_lastRun.isEmpty());

        // Without a network time service, there's nothing to turn on.
        m_clock.canNtp = false;
        DateTimeSettings noService(environment(), nullptr);
        QVERIFY(!noService.canChangeAutoTime());
        noService.setAutoTime(true);
        QVERIFY(m_ntpCalls.isEmpty());
    }

    void turnsNetworkTimeOff()
    {
        DateTimeSettings settings(environment(), nullptr);
        settings.setAutoTime(false);
        QCOMPARE(m_ntpCalls, (QList<bool> { false }));
        // The switch shows the state asked for while timedated works.
        QVERIFY(!settings.autoTime());
        QVERIFY(!settings.canChangeAutoTime());
        QVERIFY(!settings.canSync());
        // Asking again meanwhile does nothing.
        settings.setAutoTime(true);
        QCOMPARE(m_ntpCalls.size(), 1);

        m_clock.ntp = false;
        m_ntpDone({ }, { });
        QVERIFY(!settings.autoTime());
        QVERIFY(settings.canChangeAutoTime());
        QVERIFY(settings.error().isEmpty());
    }

    void saysWhyNetworkTimeCouldntChange()
    {
        m_clock.ntp = false;
        DateTimeSettings settings(environment(), nullptr);
        settings.setAutoTime(true);
        QVERIFY(settings.autoTime());
        m_ntpDone(QStringLiteral("org.freedesktop.timedate1.NoNTPSupport"), QStringLiteral("NTP not supported"));
        QVERIFY(!settings.autoTime());
        QCOMPARE(settings.error(), QStringLiteral("Couldn't turn on setting the time automatically: no network time service is installed."));

        // A dismissed password prompt isn't an error; the switch just goes back.
        settings.setAutoTime(true);
        QVERIFY(settings.error().isEmpty());
        m_ntpDone(QStringLiteral("org.freedesktop.DBus.Error.AccessDenied"), QStringLiteral("Access denied"));
        QVERIFY(!settings.autoTime());
        QVERIFY(settings.error().isEmpty());
    }

    void turnsTheAutomaticTimeZoneOn()
    {
        DateTimeSettings settings(environment(), nullptr);
        settings.setAutoTimeZone(true);
        QCOMPARE(m_lastProgram, QStringLiteral("pkexec"));
        QCOMPARE(m_lastRun, (QStringList { QStringLiteral("/usr/libexec/orielos/auto-timezone"), QStringLiteral("on") }));
        QVERIFY(settings.autoTimeZone());
        QVERIFY(!settings.canChangeAutoTimeZone());

        // auto-timezone created the file and set the zone.
        turnOnAutoTimeZone();
        m_clock.timeZone = QStringLiteral("Europe/Paris");
        m_done(0, { }, { });
        QVERIFY(settings.autoTimeZone());
        QVERIFY(settings.canChangeAutoTimeZone());
        QVERIFY(settings.error().isEmpty());
        QVERIFY(settings.timeZone().startsWith(QStringLiteral("Europe/Paris")));

        settings.setAutoTimeZone(false);
        QCOMPARE(m_lastRun, (QStringList { QStringLiteral("/usr/libexec/orielos/auto-timezone"), QStringLiteral("off") }));
    }

    void aDismissedPromptLeavesTheTimeZoneSettingAlone()
    {
        DateTimeSettings settings(environment(), nullptr);
        for (const int exitCode : { 126, 127 }) {
            settings.setAutoTimeZone(true);
            QVERIFY(settings.autoTimeZone());
            m_done(exitCode, { }, { });
            QVERIFY(!settings.autoTimeZone());
            QVERIFY(settings.error().isEmpty());
        }
    }

    void saysWhyTheTimeZoneSettingCouldntChange()
    {
        turnOnAutoTimeZone();
        DateTimeSettings settings(environment(), nullptr);
        settings.setAutoTimeZone(false);
        m_done(1, { }, QStringLiteral("auto-timezone: couldn't turn off orielos-auto-timezone.timer"));
        QVERIFY(settings.autoTimeZone());
        QCOMPARE(settings.error(), QStringLiteral("Couldn't turn off setting the time zone automatically: couldn't turn off orielos-auto-timezone.timer"));
    }

    void syncsNow()
    {
        DateTimeSettings settings(environment(), nullptr);
        const int runsBefore = m_chronycRuns;
        settings.syncNow();
        QCOMPARE(m_lastProgram, QStringLiteral("pkexec"));
        QCOMPARE(m_lastRun, (QStringList { QStringLiteral("/usr/libexec/orielos/time-sync") }));
        QVERIFY(settings.isSyncing());
        QVERIFY(!settings.canSync());

        m_tracking = synchronisedAt(november().toSecsSinceEpoch() - 1);
        m_done(0, { }, { });
        QVERIFY(!settings.isSyncing());
        QCOMPARE(settings.syncResult(), QStringLiteral("Synchronised"));
        QVERIFY(!settings.syncFailed());
        // The last synchronisation is read again at once.
        QCOMPARE(m_chronycRuns, runsBefore + 1);
        QCOMPARE(settings.lastSync(), QStringLiteral("Today at 14:03, with ntp.example.org"));
    }

    void saysWhySyncingFailed()
    {
        DateTimeSettings settings(environment(), nullptr);
        settings.syncNow();
        m_done(1, { }, QStringLiteral("time-sync: no time server answered; check the internet connection"));
        QVERIFY(settings.syncFailed());
        QCOMPARE(settings.syncResult(), QStringLiteral("Couldn't synchronise: no time server answered; check the internet connection"));

        // A dismissed prompt clears the result rather than reporting it.
        settings.syncNow();
        m_done(126, { }, { });
        QVERIFY(settings.syncResult().isEmpty());
        QVERIFY(!settings.syncFailed());
    }

    void saysWhenTheClockWasLastSynchronised()
    {
        DateTimeSettings today(environment(), nullptr);
        QCOMPARE(today.lastSync(), QStringLiteral("Today at 13:59, with ntp.example.org"));

        m_tracking = synchronisedAt(november().toSecsSinceEpoch() - 86400);
        DateTimeSettings yesterday(environment(), nullptr);
        QVERIFY(yesterday.lastSync().endsWith(QStringLiteral(", with ntp.example.org")));
        QVERIFY(!yesterday.lastSync().startsWith(QStringLiteral("Today")));

        m_tracking = notSynchronised;
        DateTimeSettings notYet(environment(), nullptr);
        QCOMPARE(notYet.lastSync(), QStringLiteral("Not synchronised yet"));

        // chronyd isn't running.
        m_chronycExit = 1;
        DateTimeSettings stopped(environment(), nullptr);
        QCOMPARE(stopped.lastSync(), QStringLiteral("Not known, as network time isn't running"));
    }
};

QTEST_GUILESS_MAIN(DateTimeSettingsTest)

#include "datetimesettingstest.moc"
