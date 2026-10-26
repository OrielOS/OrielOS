// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatestate.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QTimeZone>

using namespace OrielOSUpdates;

namespace {

const QString bootId = QStringLiteral("boot-1");
const QString running = QStringLiteral("sha256:") + QString(64, QLatin1Char('a'));
const QString newer = QStringLiteral("sha256:") + QString(64, QLatin1Char('b'));
const QString older = QStringLiteral("sha256:") + QString(64, QLatin1Char('c'));
// 2026-10-25T12:00:00Z, the "now" of every test.
const QDateTime now = QDateTime(QDate(2026, 10, 25), QTime(12, 0), QTimeZone::UTC);

// A state file as orielos-update writes it, with the given staged digest and pause.
QByteArray stateJson(const QString &staged = QString(), const QString &pausedUntil = QString(), const QString &channel = QStringLiteral("stable"))
{
    const QString stagedJson = staged.isEmpty() ? QStringLiteral("null") : QStringLiteral(R"({"version": "44.2", "digest": "%1"})").arg(staged);
    const QString pausedJson = pausedUntil.isEmpty() ? QStringLiteral("null") : QStringLiteral(R"("%1")").arg(pausedUntil);
    return QStringLiteral(R"({
        "bootId": "boot-1",
        "channel": "%1",
        "pausedUntil": %2,
        "checkedAt": "2026-10-25T11:00:00Z",
        "result": "up-to-date",
        "message": "OrielOS 44.1 is the newest build on the stable channel.",
        "running": {"version": "44.1", "digest": "%3"},
        "staged": %4
    })")
        .arg(channel, pausedJson, running, stagedJson)
        .toUtf8();
}

// The same state with a previous build, 44.0, which going back would start. removedAfter is the
// field's JSON value, or empty to leave the field out.
QByteArray withPrevious(QByteArray json, bool rejected = false, bool queued = false, const QString &removedAfter = QString())
{
    const auto flag = [](bool value) { return value ? QStringLiteral("true") : QStringLiteral("false"); };
    const QString removal = removedAfter.isEmpty() ? QString() : QStringLiteral(R"(, "removedAfter": %1)").arg(removedAfter);
    const QString fields = QStringLiteral(R"("previous": {"version": "44.0", "digest": "%1", "rejected": %2%3}, "rollbackQueued": %4, "staged":)")
                               .arg(older, flag(rejected), removal, flag(queued));
    json.replace("\"staged\":", fields.toUtf8());
    return json;
}

} // namespace

class UpdateStateTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesAFullState()
    {
        const UpdateState state = UpdateState::fromJson(stateJson(newer, QStringLiteral("2026-11-01T12:00:00Z"), QStringLiteral("testing")));
        QVERIFY(state.isValid());
        QCOMPARE(state.bootId(), bootId);
        QCOMPARE(state.channel(), Channel::Testing);
        QCOMPARE(state.result(), QStringLiteral("up-to-date"));
        QCOMPARE(state.checkedAt(), QDateTime(QDate(2026, 10, 25), QTime(11, 0), QTimeZone::UTC));
        QCOMPARE(state.pausedUntil(), QDateTime(QDate(2026, 11, 1), QTime(12, 0), QTimeZone::UTC));
        QCOMPARE(state.running(), (Build { QStringLiteral("44.1"), running }));
        QVERIFY(state.staged());
        QCOMPARE(*state.staged(), (Build { QStringLiteral("44.2"), newer }));
    }

    void readsNullsAsAbsent()
    {
        const UpdateState state = UpdateState::fromJson(stateJson());
        QVERIFY(state.isValid());
        QVERIFY(!state.staged());
        QVERIFY(!state.pausedUntil().isValid());
    }

    void ignoresUnknownFields()
    {
        QByteArray json = stateJson();
        json.replace("\"bootId\"", "\"future\": [1, 2], \"bootId\"");
        QVERIFY(UpdateState::fromJson(json).isValid());
    }

    void rejectsBadData_data()
    {
        QTest::addColumn<QByteArray>("json");
        QTest::newRow("empty") << QByteArray();
        QTest::newRow("not JSON") << QByteArray("{bootId");
        QTest::newRow("an array") << QByteArray("[]");
        QTest::newRow("no running build") << QByteArray(R"({"bootId": "boot-1", "result": "up-to-date"})");
        QTest::newRow("no boot ID") << QByteArray(R"({"result": "up-to-date", "running": {"version": "44.1", "digest": "sha256:a"}})");
        QTest::newRow("no result") << QByteArray(R"({"bootId": "boot-1", "running": {"version": "44.1", "digest": "sha256:a"}})");
    }

    void rejectsBadData()
    {
        QFETCH(QByteArray, json);
        const UpdateState state = UpdateState::fromJson(json);
        QVERIFY(!state.isValid());
        QVERIFY(!state.updateWaiting(bootId));
        QVERIFY(!state.isPaused(now));
    }

    void readsAMissingFileAsInvalid()
    {
        QTemporaryDir dir;
        QVERIFY(!UpdateState::fromFile(dir.filePath(QStringLiteral("state.json"))).isValid());
    }

    void readsAFile()
    {
        QTemporaryDir dir;
        QFile file(dir.filePath(QStringLiteral("state.json")));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(stateJson(newer));
        file.close();
        QVERIFY(UpdateState::fromFile(file.fileName()).updateWaiting(bootId));
    }

    void anUpdateWaitsOnlyForThisBoot()
    {
        const UpdateState state = UpdateState::fromJson(stateJson(newer));
        QVERIFY(state.updateWaiting(bootId));
        // After a restart the file is stale until orielos-update writes it again.
        QVERIFY(!state.updateWaiting(QStringLiteral("boot-2")));
        QVERIFY(!state.updateWaiting(QString()));
    }

    void noUpdateWaitsWithoutAStagedBuild() { QVERIFY(!UpdateState::fromJson(stateJson()).updateWaiting(bootId)); }

    void noUpdateWaitsWhenTheStagedBuildIsRunning() { QVERIFY(!UpdateState::fromJson(stateJson(running)).updateWaiting(bootId)); }

    void isPausedUntilThePauseEnds()
    {
        const UpdateState state = UpdateState::fromJson(stateJson(QString(), QStringLiteral("2026-11-01T12:00:00Z")));
        QVERIFY(state.isPaused(now));
        QVERIFY(state.isPaused(now.addDays(6)));
        QVERIFY(!state.isPaused(now.addDays(7)));
        QVERIFY(!state.isPaused(now.addDays(8)));
        QVERIFY(!UpdateState::fromJson(stateJson()).isPaused(now));
    }

    void offersOneToFiveWeeks()
    {
        QCOMPARE(pauseChoices(), (QList<int> { 1, 2, 3, 4, 5 }));
        QCOMPARE(pauseChoiceLabel(1), QStringLiteral("1 week"));
        QCOMPARE(pauseChoiceLabel(5), QStringLiteral("5 weeks"));
    }

    void mapsChannels()
    {
        QCOMPARE(channelFromName(QStringLiteral("stable")), Channel::Stable);
        QCOMPARE(channelFromName(QStringLiteral("testing")), Channel::Testing);
        QCOMPARE(channelFromName(QStringLiteral("beta")), Channel::Stable);
        QCOMPARE(channelFromName(QString()), Channel::Stable);
        QCOMPARE(channelName(Channel::Stable), QStringLiteral("stable"));
        QCOMPARE(channelName(Channel::Testing), QStringLiteral("testing"));
        QCOMPARE(UpdateState::fromJson(stateJson(QString(), QString(), QStringLiteral("nightly"))).channel(), Channel::Stable);
    }

    void readsThePreviousBuild()
    {
        const UpdateState state = UpdateState::fromJson(withPrevious(stateJson()));
        QVERIFY(state.previous());
        QCOMPARE(*state.previous(), (Build { QStringLiteral("44.0"), older }));
        QVERIFY(!state.previousRejected());
        QVERIFY(!state.rollbackQueued());
        QVERIFY(UpdateState::fromJson(withPrevious(stateJson(), true)).previousRejected());
        QVERIFY(UpdateState::fromJson(withPrevious(stateJson(), false, true)).rollbackQueued());
    }

    void readsAStateWithoutAPreviousBuild()
    {
        // State files from before going back existed have neither field.
        const UpdateState state = UpdateState::fromJson(stateJson());
        QVERIFY(state.isValid());
        QVERIFY(!state.previous());
        QVERIFY(!state.rollbackQueued());
        QVERIFY(!state.canGoBack(bootId));
        QVERIFY(!state.goingBack(bootId));
    }

    void canGoBackOnlyToABuildThatWasntRolledBack()
    {
        const UpdateState state = UpdateState::fromJson(withPrevious(stateJson()));
        QVERIFY(state.canGoBack(bootId));
        QVERIFY(!state.canGoBack(QStringLiteral("boot-2")));
        QVERIFY(!UpdateState::fromJson(withPrevious(stateJson(), true)).canGoBack(bootId));
    }

    void readsWhenThePreviousBuildIsRemoved_data()
    {
        QTest::addColumn<QString>("removedAfter");
        QTest::addColumn<QDateTime>("expected");
        QTest::newRow("a time") << QStringLiteral(R"("2026-11-08T12:00:00Z")") << QDateTime(QDate(2026, 11, 8), QTime(12, 0), QTimeZone::UTC);
        QTest::newRow("null") << QStringLiteral("null") << QDateTime();
        QTest::newRow("absent") << QString() << QDateTime();
        QTest::newRow("not a time") << QStringLiteral(R"("soon")") << QDateTime();
        QTest::newRow("a number") << QStringLiteral("14") << QDateTime();
    }

    void readsWhenThePreviousBuildIsRemoved()
    {
        QFETCH(QString, removedAfter);
        QFETCH(QDateTime, expected);
        const UpdateState state = UpdateState::fromJson(withPrevious(stateJson(), false, false, removedAfter));
        QVERIFY(state.previous());
        QCOMPARE(state.previousRemovedAfter(), expected);
    }

    void removesThePreviousBuildOnlyWhenNothingWaits()
    {
        QVERIFY(UpdateState::fromJson(withPrevious(stateJson())).canRemovePrevious(bootId));
        // A build that was rolled back can be removed too, though it isn't offered for going back.
        QVERIFY(UpdateState::fromJson(withPrevious(stateJson(), true)).canRemovePrevious(bootId));
        QVERIFY(!UpdateState::fromJson(stateJson()).canRemovePrevious(bootId));
        QVERIFY(!UpdateState::fromJson(withPrevious(stateJson(newer))).canRemovePrevious(bootId));
        QVERIFY(!UpdateState::fromJson(withPrevious(stateJson(), false, true)).canRemovePrevious(bootId));
        QVERIFY(!UpdateState::fromJson(withPrevious(stateJson())).canRemovePrevious(QStringLiteral("boot-2")));
        // A staged build that is the running one isn't waiting for anything.
        QVERIFY(UpdateState::fromJson(withPrevious(stateJson(running))).canRemovePrevious(bootId));
    }

    void goingBackReplacesAWaitingUpdate()
    {
        const UpdateState state = UpdateState::fromJson(withPrevious(stateJson(newer), false, true));
        QVERIFY(state.goingBack(bootId));
        QVERIFY(!state.goingBack(QStringLiteral("boot-2")));
        QVERIFY(!state.canGoBack(bootId));
        QVERIFY(!state.updateWaiting(bootId));
    }

    void goingBackNeedsAPreviousBuild()
    {
        QByteArray json = stateJson();
        json.replace("\"staged\":", "\"rollbackQueued\": true, \"staged\":");
        QVERIFY(!UpdateState::fromJson(json).goingBack(bootId));
    }

    void tellsWhenAnUpdateWasUndone()
    {
        QByteArray json = withPrevious(stateJson());
        json.replace("\"up-to-date\"", "\"went-back\"");
        const UpdateState state = UpdateState::fromJson(json);
        QVERIFY(state.updateUndone(bootId));
        QVERIFY(!state.updateUndone(QStringLiteral("boot-2")));
        QVERIFY(!UpdateState::fromJson(stateJson()).updateUndone(bootId));
        QCOMPARE(statusText(state, bootId, now), QStringLiteral("The last update didn't start, so OrielOS went back to the previous version"));
    }

    void describesTheState()
    {
        QCOMPARE(statusText(UpdateState::fromJson(stateJson(newer)), bootId, now), QStringLiteral("Restart to finish updating to OrielOS 44.2"));
        QCOMPARE(statusText(UpdateState::fromJson(stateJson()), bootId, now), QStringLiteral("OrielOS is up to date"));
        QCOMPARE(statusText(UpdateState::fromJson(stateJson()), QStringLiteral("boot-2"), now), QStringLiteral("Not checked for updates yet"));
        QCOMPARE(statusText(UpdateState(), bootId, now), QStringLiteral("Not checked for updates yet"));
        const UpdateState paused = UpdateState::fromJson(stateJson(QString(), QStringLiteral("2026-11-01T12:00:00Z")));
        QVERIFY(statusText(paused, bootId, now).startsWith(QStringLiteral("Updates are paused until ")));

        QByteArray unreachable = stateJson();
        unreachable.replace("\"up-to-date\"", "\"unreachable\"");
        QCOMPARE(statusText(UpdateState::fromJson(unreachable), bootId, now), QStringLiteral("Couldn't check for updates"));
        QByteArray metered = stateJson();
        metered.replace("\"up-to-date\"", "\"metered\"");
        QCOMPARE(statusText(UpdateState::fromJson(metered), bootId, now), QStringLiteral("Updates are skipped on a metered connection"));

        const UpdateState goingBack = UpdateState::fromJson(withPrevious(stateJson(newer), false, true));
        QCOMPARE(statusText(goingBack, bootId, now), QStringLiteral("Restart to go back to OrielOS 44.0"));
        QByteArray queuedResult = stateJson();
        queuedResult.replace("\"up-to-date\"", "\"rollback-queued\"");
        QCOMPARE(statusText(UpdateState::fromJson(queuedResult), bootId, now), QStringLiteral("OrielOS is up to date"));
    }
};

QTEST_GUILESS_MAIN(UpdateStateTest)

#include "updatestatetest.moc"
