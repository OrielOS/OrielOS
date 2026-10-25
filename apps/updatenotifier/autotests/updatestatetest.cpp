// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatestate.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QTimeZone>

using namespace UpdateNotifier;

namespace {

const QString bootId = QStringLiteral("boot-1");
const QString running = QStringLiteral("sha256:") + QString(64, QLatin1Char('a'));
const QString newer = QStringLiteral("sha256:") + QString(64, QLatin1Char('b'));
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
        QCOMPARE(pauseChoiceLabel(1), QStringLiteral("Pause for 1 week"));
        QCOMPARE(pauseChoiceLabel(5), QStringLiteral("Pause for 5 weeks"));
    }

    void mapsChannels()
    {
        QCOMPARE(channelFromName(QStringLiteral("stable")), Channel::Stable);
        QCOMPARE(channelFromName(QStringLiteral("testing")), Channel::Testing);
        QCOMPARE(channelFromName(QStringLiteral("beta")), Channel::Stable);
        QCOMPARE(channelFromName(QString()), Channel::Stable);
        QCOMPARE(channelName(Channel::Stable), QStringLiteral("stable"));
        QCOMPARE(channelName(Channel::Testing), QStringLiteral("testing"));
        QCOMPARE(channelLabel(Channel::Stable), QStringLiteral("Stable (recommended)"));
        QCOMPARE(UpdateState::fromJson(stateJson(QString(), QString(), QStringLiteral("nightly"))).channel(), Channel::Stable);
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
    }
};

QTEST_GUILESS_MAIN(UpdateStateTest)

#include "updatestatetest.moc"
