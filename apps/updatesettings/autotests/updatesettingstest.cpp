// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatesettings.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QTest>
#include <QTimeZone>

#include <memory>

using namespace OrielOSUpdates;
using namespace std::chrono_literals;

namespace {

const QString running = QStringLiteral("sha256:") + QString(64, QLatin1Char('a'));
const QString newer = QStringLiteral("sha256:") + QString(64, QLatin1Char('b'));
const QString older = QStringLiteral("sha256:") + QString(64, QLatin1Char('c'));
// 2026-10-25T12:00:00Z, the "now" of every test.
const QDateTime now = QDateTime(QDate(2026, 10, 25), QTime(12, 0), QTimeZone::UTC);

// A state file as orielos-update writes it: up to date on the stable channel, nothing staged and no
// previous build. Tests change fields as they need.
QJsonObject upToDate()
{
    return QJsonObject {
        { QStringLiteral("bootId"), QStringLiteral("boot-1") },
        { QStringLiteral("channel"), QStringLiteral("stable") },
        { QStringLiteral("pausedUntil"), QJsonValue::Null },
        { QStringLiteral("checkedAt"), QStringLiteral("2026-10-25T11:00:00Z") },
        { QStringLiteral("result"), QStringLiteral("up-to-date") },
        { QStringLiteral("message"), QStringLiteral("OrielOS 44.1 is the newest build on the stable channel.") },
        { QStringLiteral("running"), QJsonObject { { QStringLiteral("version"), QStringLiteral("44.1") }, { QStringLiteral("digest"), running } } },
        { QStringLiteral("staged"), QJsonValue::Null },
        { QStringLiteral("previous"), QJsonValue::Null },
        { QStringLiteral("rollbackQueued"), false },
    };
}

QJsonObject build(const QString &version, const QString &digest)
{
    return QJsonObject { { QStringLiteral("version"), version }, { QStringLiteral("digest"), digest } };
}

// The same state with 44.0 as the previous build, removed after the given time (or null).
QJsonObject withPrevious(QJsonObject state, bool rejected = false, const QJsonValue &removedAfter = QStringLiteral("2026-11-08T12:00:00Z"))
{
    QJsonObject previous = build(QStringLiteral("44.0"), older);
    previous.insert(QStringLiteral("rejected"), rejected);
    previous.insert(QStringLiteral("removedAfter"), removedAfter);
    state.insert(QStringLiteral("previous"), previous);
    return state;
}

class FakeRunner : public CommandRunner
{
    Q_OBJECT

public:
    using CommandRunner::CommandRunner;

    void run(const QStringList &arguments) override { calls.append(arguments); }
    void finish(Outcome outcome, const QString &detail = QString()) { Q_EMIT finished(calls.last(), outcome, detail); }

    QList<QStringList> calls;
};

class FakeMonitor : public CheckMonitor
{
    Q_OBJECT

public:
    using CheckMonitor::CheckMonitor;

    bool isRunning() const override { return m_running; }
    void setRunning(bool running)
    {
        m_running = running;
        Q_EMIT runningChanged();
    }

private:
    bool m_running = false;
};

// A page over a scratch state file, with the fakes and a fixed clock.
struct Page
{
    explicit Page(const QJsonObject &state, std::chrono::milliseconds checkStartTimeout = 30s)
    {
        QFile bootId(dir.filePath(QStringLiteral("boot_id")));
        if (bootId.open(QIODevice::WriteOnly)) {
            bootId.write("boot-1\n");
            bootId.close();
        }
        write(state);
        UpdateSettings::Environment environment;
        environment.statePath = dir.filePath(QStringLiteral("state.json"));
        environment.bootIdPath = bootId.fileName();
        environment.runner = &runner;
        environment.monitor = &monitor;
        environment.now = [] { return now; };
        environment.restart = [this] { ++restarts; };
        environment.checkStartTimeout = checkStartTimeout;
        settings = std::make_unique<UpdateSettings>(environment);
    }

    // Replaces the state file in one step, as orielos-update does.
    void write(const QJsonObject &state)
    {
        QSaveFile file(dir.filePath(QStringLiteral("state.json")));
        if (file.open(QIODevice::WriteOnly)) {
            file.write(QJsonDocument(state).toJson());
            file.commit();
        }
    }

    QTemporaryDir dir;
    FakeRunner runner;
    FakeMonitor monitor;
    int restarts = 0;
    std::unique_ptr<UpdateSettings> settings;
};

} // namespace

class UpdateSettingsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void readsAnUpToDateState()
    {
        Page page(upToDate());
        UpdateSettings &settings = *page.settings;
        QVERIFY(settings.isValid());
        QCOMPARE(settings.headline(), QStringLiteral("OrielOS is up to date"));
        QCOMPARE(settings.detail(), QStringLiteral("OrielOS 44.1 is the newest build on the stable channel."));
        QVERIFY(settings.lastChecked().startsWith(QStringLiteral("Last checked: ")));
        QCOMPARE(settings.runningVersion(), QStringLiteral("44.1"));
        QVERIFY(!settings.isChecking());
        QVERIFY(!settings.isBusy());
        QVERIFY(!settings.updateWaiting());
        QVERIFY(!settings.goingBack());
        QVERIFY(!settings.isPaused());
        QCOMPARE(settings.pausedUntil(), QString());
        QCOMPARE(settings.channel(), 0);
        QVERIFY(!settings.hasPrevious());
        QVERIFY(!settings.canGoBack());
        QVERIFY(!settings.canRemovePrevious());
        QCOMPARE(settings.error(), QString());
        QCOMPARE(settings.pauseChoices(),
            (QStringList {
                QStringLiteral("1 week"), QStringLiteral("2 weeks"), QStringLiteral("3 weeks"), QStringLiteral("4 weeks"), QStringLiteral("5 weeks") }));
        QCOMPARE(settings.minPauseWeeks(), 1);
    }

    void ignoresAStateFromAnotherBoot()
    {
        QJsonObject state = withPrevious(upToDate());
        state.insert(QStringLiteral("bootId"), QStringLiteral("boot-0"));
        Page page(state);
        UpdateSettings &settings = *page.settings;
        QVERIFY(!settings.isValid());
        QCOMPARE(settings.headline(), QStringLiteral("Not checked for updates yet"));
        QCOMPARE(settings.detail(), QString());
        QCOMPARE(settings.lastChecked(), QString());
        QCOMPARE(settings.runningVersion(), QString());
        QVERIFY(!settings.hasPrevious());
        QVERIFY(!settings.canGoBack());
    }

    void readsAMissingFile()
    {
        Page page(upToDate());
        QFile::remove(page.dir.filePath(QStringLiteral("state.json")));
        UpdateSettings::Environment environment;
        environment.statePath = page.dir.filePath(QStringLiteral("state.json"));
        environment.bootIdPath = page.dir.filePath(QStringLiteral("boot_id"));
        environment.runner = &page.runner;
        environment.monitor = &page.monitor;
        environment.now = [] { return now; };
        environment.restart = [] { };
        UpdateSettings settings(environment);
        QVERIFY(!settings.isValid());
        QCOMPARE(settings.headline(), QStringLiteral("Not checked for updates yet"));
        // Checking works without a state; it writes one.
        settings.checkForUpdates();
        QCOMPARE(page.runner.calls.size(), 1);
        QCOMPARE(page.runner.calls.first(), QStringList { QStringLiteral("check-now") });
    }

    void readsAWaitingUpdate()
    {
        QJsonObject state = withPrevious(upToDate());
        state.insert(QStringLiteral("staged"), build(QStringLiteral("44.2"), newer));
        state.insert(QStringLiteral("result"), QStringLiteral("staged"));
        Page page(state);
        UpdateSettings &settings = *page.settings;
        QVERIFY(settings.updateWaiting());
        QCOMPARE(settings.stagedVersion(), QStringLiteral("44.2"));
        QCOMPARE(settings.headline(), QStringLiteral("Restart to finish updating to OrielOS 44.2"));
        QCOMPARE(settings.detail(), QString());
        // orielos-update keeps the previous build while another one waits.
        QVERIFY(settings.canGoBack());
        QVERIFY(!settings.canRemovePrevious());
    }

    void readsAPause()
    {
        QJsonObject state = upToDate();
        state.insert(QStringLiteral("pausedUntil"), QStringLiteral("2026-11-01T12:00:00Z"));
        Page page(state);
        UpdateSettings &settings = *page.settings;
        QVERIFY(settings.isPaused());
        QCOMPARE(settings.pausedUntil(), displayDate(QDateTime(QDate(2026, 11, 1), QTime(12, 0), QTimeZone::UTC)));
        QVERIFY(settings.headline().startsWith(QStringLiteral("Updates are paused until ")));

        // A pause that has ended isn't shown.
        state.insert(QStringLiteral("pausedUntil"), QStringLiteral("2026-10-25T11:59:00Z"));
        Page ended(state);
        QVERIFY(!ended.settings->isPaused());
        QCOMPARE(ended.settings->pausedUntil(), QString());
    }

    void readsTheTestingChannel()
    {
        QJsonObject state = upToDate();
        state.insert(QStringLiteral("channel"), QStringLiteral("testing"));
        Page page(state);
        QCOMPARE(page.settings->channel(), 1);
    }

    void readsThePreviousBuild()
    {
        Page page(withPrevious(upToDate()));
        UpdateSettings &settings = *page.settings;
        QVERIFY(settings.hasPrevious());
        QCOMPARE(settings.previousVersion(), QStringLiteral("44.0"));
        QCOMPARE(settings.previousAvailableUntil(), displayDate(QDateTime(QDate(2026, 11, 8), QTime(12, 0), QTimeZone::UTC)));
        QVERIFY(settings.canGoBack());
        QVERIFY(settings.canRemovePrevious());

        Page unknown(withPrevious(upToDate(), false, QJsonValue::Null));
        QVERIFY(unknown.settings->hasPrevious());
        QCOMPARE(unknown.settings->previousAvailableUntil(), QString());
    }

    void offersNoGoingBackToARejectedBuild()
    {
        Page page(withPrevious(upToDate(), true));
        UpdateSettings &settings = *page.settings;
        QVERIFY(settings.hasPrevious());
        QVERIFY(!settings.canGoBack());
        QVERIFY(settings.canRemovePrevious());
        settings.goBack();
        QVERIFY(page.runner.calls.isEmpty());
    }

    void readsGoingBack()
    {
        QJsonObject state = withPrevious(upToDate());
        state.insert(QStringLiteral("rollbackQueued"), true);
        Page page(state);
        UpdateSettings &settings = *page.settings;
        QVERIFY(settings.goingBack());
        QCOMPARE(settings.headline(), QStringLiteral("Restart to go back to OrielOS 44.0"));
        QCOMPARE(settings.detail(), QString());
        QVERIFY(!settings.canGoBack());
        QVERIFY(!settings.canRemovePrevious());
        settings.removePrevious();
        QVERIFY(page.runner.calls.isEmpty());
    }

    void followsTheFile()
    {
        Page page(upToDate());
        QJsonObject state = withPrevious(upToDate());
        state.insert(QStringLiteral("channel"), QStringLiteral("testing"));
        page.write(state);
        QTRY_COMPARE(page.settings->channel(), 1);
        QVERIFY(page.settings->hasPrevious());
    }

    void runsOrielosUpdate_data()
    {
        QTest::addColumn<QJsonObject>("state");
        QTest::addColumn<QString>("invocation");
        QTest::addColumn<QStringList>("arguments");

        QJsonObject paused = upToDate();
        paused.insert(QStringLiteral("pausedUntil"), QStringLiteral("2026-11-01T12:00:00Z"));
        QTest::newRow("check") << upToDate() << QStringLiteral("check") << QStringList { QStringLiteral("check-now") };
        QTest::newRow("pause") << upToDate() << QStringLiteral("pause 3") << QStringList { QStringLiteral("pause"), QStringLiteral("3") };
        QTest::newRow("resume") << paused << QStringLiteral("resume") << QStringList { QStringLiteral("resume") };
        QTest::newRow("channel") << upToDate() << QStringLiteral("testing") << QStringList { QStringLiteral("channel"), QStringLiteral("testing") };
        QTest::newRow("go back") << withPrevious(upToDate()) << QStringLiteral("go back") << QStringList { QStringLiteral("rollback") };
        QTest::newRow("remove") << withPrevious(upToDate()) << QStringLiteral("remove") << QStringList { QStringLiteral("remove-previous") };
        QTest::newRow("app updates off") << upToDate() << QStringLiteral("apps off") << QStringList { QStringLiteral("app-updates"), QStringLiteral("off") };
        QJsonObject appsOff = upToDate();
        appsOff.insert(QStringLiteral("appUpdates"), false);
        QTest::newRow("app updates on") << appsOff << QStringLiteral("apps on") << QStringList { QStringLiteral("app-updates"), QStringLiteral("on") };
        QTest::newRow("active hours") << upToDate() << QStringLiteral("hours 9 18")
                                      << QStringList { QStringLiteral("active-hours"), QStringLiteral("9"), QStringLiteral("18") };
        QTest::newRow("auto restart") << upToDate() << QStringLiteral("auto on") << QStringList { QStringLiteral("auto-restart"), QStringLiteral("on") };
        QJsonObject staged = upToDate();
        staged.insert(QStringLiteral("staged"), build(QStringLiteral("44.2"), newer));
        const QString tomorrowAtThree = QDateTime(now.toLocalTime().date().addDays(1), QTime(3, 0)).toUTC().toString(Qt::ISODate);
        QTest::newRow("schedule") << staged << QStringLiteral("schedule") << QStringList { QStringLiteral("restart-at"), tomorrowAtThree };
        QJsonObject scheduled = staged;
        scheduled.insert(QStringLiteral("restartAt"), QStringLiteral("2026-10-26T03:00:00Z"));
        QTest::newRow("cancel") << scheduled << QStringLiteral("cancel") << QStringList { QStringLiteral("restart-at"), QStringLiteral("cancel") };
    }

    void runsOrielosUpdate()
    {
        QFETCH(QJsonObject, state);
        QFETCH(QString, invocation);
        QFETCH(QStringList, arguments);
        Page page(state);
        invoke(*page.settings, invocation);
        QCOMPARE(page.runner.calls.size(), 1);
        QCOMPARE(page.runner.calls.first(), arguments);
        QVERIFY(page.settings->isBusy());
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QVERIFY(!page.settings->isBusy());
        QCOMPARE(page.settings->error(), QString());
    }

    void runsNothingThatIsntAllowed()
    {
        Page page(upToDate());
        UpdateSettings &settings = *page.settings;
        settings.pause(0);
        settings.pause(6);
        settings.resume();
        settings.setChannel(0);
        settings.setChannel(2);
        settings.goBack();
        settings.removePrevious();
        // App updates are on already.
        settings.setAppUpdates(true);
        // Nothing waits for a restart, the hours are already 8 to 17 or can't be, and automatic
        // restarts are already off.
        settings.scheduleRestart(1, 3, 0);
        settings.cancelRestart();
        settings.setActiveHours(8, 17);
        settings.setActiveHours(5, 5);
        settings.setActiveHours(0, 24);
        settings.setAutoRestart(false);
        QVERIFY(page.runner.calls.isEmpty());

        QJsonObject staged = withPrevious(upToDate());
        staged.insert(QStringLiteral("staged"), build(QStringLiteral("44.2"), newer));
        Page waiting(staged);
        waiting.settings->removePrevious();
        QVERIFY(waiting.runner.calls.isEmpty());
    }

    void runsOneCommandAtATime()
    {
        Page page(withPrevious(upToDate()));
        UpdateSettings &settings = *page.settings;
        settings.pause(1);
        QVERIFY(settings.isBusy());
        // Still offered, so the page doesn't change while a command runs, but nothing else starts.
        QVERIFY(settings.canGoBack());
        QVERIFY(settings.canRemovePrevious());
        settings.pause(2);
        settings.checkForUpdates();
        settings.goBack();
        settings.removePrevious();
        QCOMPARE(page.runner.calls.size(), 1);
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QVERIFY(!settings.isBusy());
        settings.goBack();
        QCOMPARE(page.runner.calls.size(), 2);
    }

    void reportsFailures_data()
    {
        QTest::addColumn<QJsonObject>("state");
        QTest::addColumn<QString>("invocation");
        QTest::addColumn<QString>("message");

        QTest::newRow("check") << upToDate() << QStringLiteral("check") << QStringLiteral("Couldn't check for updates: %1");
        QTest::newRow("pause") << upToDate() << QStringLiteral("pause 3") << QStringLiteral("Couldn't change the update settings: %1");
        QTest::newRow("channel") << upToDate() << QStringLiteral("testing") << QStringLiteral("Couldn't change the update settings: %1");
        QTest::newRow("go back") << withPrevious(upToDate()) << QStringLiteral("go back") << QStringLiteral("Couldn't go back to the previous version: %1");
        QTest::newRow("remove") << withPrevious(upToDate()) << QStringLiteral("remove") << QStringLiteral("Couldn't remove the previous version: %1");
        QTest::newRow("app updates") << upToDate() << QStringLiteral("apps off") << QStringLiteral("Couldn't change the update settings: %1");
    }

    void reportsFailures()
    {
        QFETCH(QJsonObject, state);
        QFETCH(QString, invocation);
        QFETCH(QString, message);
        Page page(state);
        invoke(*page.settings, invocation);
        page.runner.finish(CommandRunner::Outcome::Failed, QStringLiteral("orielos-update: the disk is full"));
        QCOMPARE(page.settings->error(), message.arg(QStringLiteral("orielos-update: the disk is full")));
        page.settings->clearError();
        QCOMPARE(page.settings->error(), QString());

        invoke(*page.settings, invocation);
        page.runner.finish(CommandRunner::Outcome::Failed);
        QCOMPARE(page.settings->error(), message.arg(QStringLiteral("orielos-update stopped with an error.")));
        // The next command starts with no error shown.
        invoke(*page.settings, invocation);
        QCOMPARE(page.settings->error(), QString());
        page.runner.finish(CommandRunner::Outcome::Cancelled);
        QCOMPARE(page.settings->error(), QString());
    }

    void showsTheChosenChannelWhileItChanges()
    {
        Page page(upToDate());
        UpdateSettings &settings = *page.settings;
        settings.setChannel(1);
        QCOMPARE(settings.channel(), 1);
        page.runner.finish(CommandRunner::Outcome::Cancelled);
        QCOMPARE(settings.channel(), 0);

        settings.setChannel(1);
        QJsonObject testing = upToDate();
        testing.insert(QStringLiteral("channel"), QStringLiteral("testing"));
        page.write(testing);
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QCOMPARE(settings.channel(), 1);
    }

    void readsRestartsAndHistory()
    {
        QJsonObject state = upToDate();
        state.insert(QStringLiteral("staged"), build(QStringLiteral("44.2"), newer));
        state.insert(QStringLiteral("restartAt"), QStringLiteral("2026-10-26T03:00:00Z"));
        state.insert(QStringLiteral("activeHours"), QJsonObject { { QStringLiteral("start"), 9 }, { QStringLiteral("end"), 18 } });
        state.insert(QStringLiteral("autoRestart"), true);
        state.insert(QStringLiteral("history"),
            QJsonArray { QJsonObject { { QStringLiteral("version"), QStringLiteral("44.1") }, { QStringLiteral("startedAt"), QStringLiteral("2026-10-24T08:00:00Z") } } });
        Page page(state);
        QVERIFY(page.settings->restartScheduled());
        QVERIFY(!page.settings->restartAt().isEmpty());
        QCOMPARE(page.settings->activeHoursStart(), 9);
        QCOMPARE(page.settings->activeHoursEnd(), 18);
        QVERIFY(page.settings->autoRestart());
        QCOMPARE(page.settings->history().size(), 1);
        QCOMPARE(page.settings->history().first().toMap().value(QStringLiteral("version")).toString(), QStringLiteral("44.1"));
        QCOMPARE(page.settings->restartDays().size(), 7);
        QCOMPARE(page.settings->hourChoices().size(), 24);

        // Once nothing waits for it, a scheduled restart isn't shown.
        state.insert(QStringLiteral("staged"), QJsonValue::Null);
        Page done(state);
        QVERIFY(!done.settings->restartScheduled());
    }

    void readsAppUpdates()
    {
        Page page(upToDate());
        // A state file from before the setting existed: app updates are on, and none has run yet.
        QVERIFY(page.settings->appUpdates());
        QCOMPARE(page.settings->appsUpdated(), QString());

        QJsonObject state = upToDate();
        state.insert(QStringLiteral("appUpdates"), false);
        state.insert(QStringLiteral("appsUpdatedAt"), QStringLiteral("2026-10-25T09:00:00Z"));
        page.write(state);
        QTRY_VERIFY(!page.settings->appUpdates());
        QVERIFY(page.settings->appsUpdated().startsWith(QStringLiteral("Apps last updated: ")));
    }

    void showsTheChosenAppUpdatesWhileTheyChange()
    {
        Page page(upToDate());
        UpdateSettings &settings = *page.settings;
        settings.setAppUpdates(false);
        QVERIFY(!settings.appUpdates());
        page.runner.finish(CommandRunner::Outcome::Cancelled);
        QVERIFY(settings.appUpdates());

        settings.setAppUpdates(false);
        QJsonObject off = upToDate();
        off.insert(QStringLiteral("appUpdates"), false);
        page.write(off);
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QVERIFY(!settings.appUpdates());
    }

    void checksUntilTheCheckUnitStops()
    {
        Page page(upToDate());
        UpdateSettings &settings = *page.settings;
        settings.checkForUpdates();
        QVERIFY(settings.isChecking());
        QCOMPARE(settings.headline(), QStringLiteral("Checking for updates…"));
        QCOMPARE(settings.detail(), QString());
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QVERIFY(settings.isChecking());
        page.monitor.setRunning(true);
        QVERIFY(settings.isChecking());
        settings.checkForUpdates();
        QCOMPARE(page.runner.calls.size(), 1);
        page.monitor.setRunning(false);
        QVERIFY(!settings.isChecking());
        QCOMPARE(settings.headline(), QStringLiteral("OrielOS is up to date"));
    }

    void stopsCheckingOnANewResult()
    {
        // A check can end before pkexec returns, so the unit is never seen running.
        Page page(upToDate());
        page.settings->checkForUpdates();
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QVERIFY(page.settings->isChecking());
        QJsonObject state = upToDate();
        state.insert(QStringLiteral("checkedAt"), QStringLiteral("2026-10-25T12:00:00Z"));
        page.write(state);
        QTRY_VERIFY(!page.settings->isChecking());
    }

    void stopsCheckingWhenTheCheckCouldntStart()
    {
        Page page(upToDate());
        page.settings->checkForUpdates();
        page.runner.finish(CommandRunner::Outcome::Failed, QStringLiteral("orielos-update: couldn't start orielos-update-check.service"));
        QVERIFY(!page.settings->isChecking());
        QVERIFY(!page.settings->error().isEmpty());

        page.settings->checkForUpdates();
        page.runner.finish(CommandRunner::Outcome::Cancelled);
        QVERIFY(!page.settings->isChecking());
    }

    void stopsWaitingForACheckThatNeverStarts()
    {
        Page page(upToDate(), 50ms);
        page.settings->checkForUpdates();
        page.runner.finish(CommandRunner::Outcome::Succeeded);
        QVERIFY(page.settings->isChecking());
        QTRY_VERIFY_WITH_TIMEOUT(!page.settings->isChecking(), 2000);
    }

    void showsABackgroundCheck()
    {
        Page page(upToDate());
        page.monitor.setRunning(true);
        QVERIFY(page.settings->isChecking());
        page.settings->checkForUpdates();
        QVERIFY(page.runner.calls.isEmpty());
    }

    void restarts()
    {
        Page page(upToDate());
        page.settings->restart();
        QCOMPARE(page.restarts, 1);
    }

private:
    static void invoke(UpdateSettings &settings, const QString &invocation)
    {
        if (invocation == QLatin1String("check")) {
            settings.checkForUpdates();
        } else if (invocation == QLatin1String("pause 3")) {
            settings.pause(3);
        } else if (invocation == QLatin1String("resume")) {
            settings.resume();
        } else if (invocation == QLatin1String("testing")) {
            settings.setChannel(1);
        } else if (invocation == QLatin1String("go back")) {
            settings.goBack();
        } else if (invocation == QLatin1String("remove")) {
            settings.removePrevious();
        } else if (invocation == QLatin1String("apps off")) {
            settings.setAppUpdates(false);
        } else if (invocation == QLatin1String("apps on")) {
            settings.setAppUpdates(true);
        } else if (invocation == QLatin1String("hours 9 18")) {
            settings.setActiveHours(9, 18);
        } else if (invocation == QLatin1String("auto on")) {
            settings.setAutoRestart(true);
        } else if (invocation == QLatin1String("schedule")) {
            settings.scheduleRestart(1, 3, 0);
        } else if (invocation == QLatin1String("cancel")) {
            settings.cancelRestart();
        }
    }
};

QTEST_GUILESS_MAIN(UpdateSettingsTest)

#include "updatesettingstest.moc"
