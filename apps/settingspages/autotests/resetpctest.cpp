// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "resetpc.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

constexpr auto thisBoot = "11111111-2222-3333-4444-555555555555";

void writeFile(const QString &path, const QByteArray &contents)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(contents);
}

QByteArray state(const char *phase, const char *mode = "keep", const char *bootId = thisBoot, qint64 downloaded = 0, qint64 total = 0)
{
    return QStringLiteral(R"({"phase": "%1", "message": "Something went wrong.", "mode": "%2", "version": "v0.3.1",
        "downloaded": %3, "total": %4, "bootId": "%5"})")
        .arg(QLatin1String(phase), QLatin1String(mode))
        .arg(downloaded)
        .arg(total)
        .arg(QLatin1String(bootId))
        .toUtf8();
}

} // namespace

class ResetPCTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    QStringList m_lastRun;
    std::function<void(int, const QString &)> m_done;
    int m_restarts = 0;

    QString statePath() const { return m_dir.filePath(QStringLiteral("state.json")); }

    ResetPC::Environment environment()
    {
        writeFile(m_dir.filePath(QStringLiteral("boot_id")), QByteArray(thisBoot) + '\n');
        return ResetPC::Environment {
            statePath(),
            m_dir.filePath(QStringLiteral("boot_id")),
            [this](const QStringList &arguments, std::function<void(int, const QString &)> done) {
                m_lastRun = arguments;
                m_done = std::move(done);
            },
            [this] { ++m_restarts; },
        };
    }

private Q_SLOTS:
    void init()
    {
        QFile::remove(statePath());
        m_lastRun.clear();
        m_done = nullptr;
        m_restarts = 0;
    }

    void parsesTheState()
    {
        const ResetState parsed = ResetState::parse(state("downloading", "erase", thisBoot, 5, 10));
        QCOMPARE(parsed.phase, ResetState::Phase::Downloading);
        QCOMPARE(parsed.mode, QStringLiteral("erase"));
        QCOMPARE(parsed.version, QStringLiteral("v0.3.1"));
        QCOMPARE(parsed.downloaded, qint64(5));
        QCOMPARE(parsed.total, qint64(10));
        QCOMPARE(ResetState::parse("not json").phase, ResetState::Phase::Idle);
        QCOMPARE(ResetState::parse(R"({"phase": "something new"})").phase, ResetState::Phase::Idle);
    }

    void offersBothChoicesWithoutAState()
    {
        ResetPC reset(environment(), nullptr);
        QVERIFY(!reset.isWorking());
        QVERIFY(!reset.isReady());
        QVERIFY(reset.outcome().isEmpty());
        reset.reset(true);
        QCOMPARE(m_lastRun, (QStringList { QStringLiteral("start"), QStringLiteral("keep") }));
        QVERIFY(reset.isBusy());
        m_done(0, { });
        QVERIFY(!reset.isBusy());
        QVERIFY(reset.error().isEmpty());
    }

    void removingEverythingAsksForErase()
    {
        ResetPC reset(environment(), nullptr);
        reset.reset(false);
        QCOMPARE(m_lastRun, (QStringList { QStringLiteral("start"), QStringLiteral("erase") }));
    }

    void showsTheDownload()
    {
        writeFile(statePath(), state("downloading", "keep", thisBoot, 1200000000, 3700000000));
        ResetPC reset(environment(), nullptr);
        QVERIFY(reset.isWorking());
        QVERIFY(reset.keepsFiles());
        QVERIFY(qAbs(reset.progress() - 1200.0 / 3700.0) < 0.001);
        QCOMPARE(reset.progressText(), QStringLiteral("1.2 GB of 3.7 GB"));
        QVERIFY(reset.status().contains(QStringLiteral("v0.3.1")));
        // Starting another while one is being got ready does nothing.
        reset.reset(true);
        QVERIFY(m_lastRun.isEmpty());
    }

    void stepsWithoutAMeasureAreIndeterminate()
    {
        writeFile(statePath(), state("preparing"));
        ResetPC reset(environment(), nullptr);
        QVERIFY(reset.isWorking());
        QCOMPARE(reset.progress(), -1.0);
        QVERIFY(reset.progressText().isEmpty());
    }

    void readyOffersRestartAndCancel()
    {
        writeFile(statePath(), state("ready", "erase"));
        ResetPC reset(environment(), nullptr);
        QVERIFY(reset.isReady());
        QVERIFY(!reset.keepsFiles());
        QVERIFY(reset.status().contains(QStringLiteral("first-run setup")));
        reset.restart();
        QCOMPARE(m_restarts, 1);
        reset.cancel();
        QCOMPARE(m_lastRun, (QStringList { QStringLiteral("cancel") }));
    }

    void restartDoesNothingUntilReady()
    {
        ResetPC reset(environment(), nullptr);
        reset.restart();
        QCOMPARE(m_restarts, 0);
        reset.cancel();
        QVERIFY(m_lastRun.isEmpty());
    }

    void aStateFromAnotherStartIsOld()
    {
        // Preparing can't still be going after a restart; refresh at the start says what happened.
        writeFile(statePath(), state("downloading", "keep", "99999999-0000-0000-0000-000000000000", 1, 2));
        ResetPC reset(environment(), nullptr);
        QVERIFY(!reset.isWorking());
        QVERIFY(reset.status().isEmpty());
        QVERIFY(reset.outcome().isEmpty());
    }

    void saysWhatHappened()
    {
        writeFile(statePath(), state("failed"));
        ResetPC failed(environment(), nullptr);
        QCOMPARE(failed.outcome(), QStringLiteral("Something went wrong."));
        QVERIFY(failed.outcomeIsError());

        writeFile(statePath(), state("done"));
        ResetPC done(environment(), nullptr);
        QCOMPARE(done.outcome(), QStringLiteral("This PC was reset to OrielOS v0.3.1."));
        QVERIFY(!done.outcomeIsError());
    }

    void reportsAFailedCommandButNotADismissedPrompt()
    {
        ResetPC reset(environment(), nullptr);
        reset.reset(true);
        m_done(126, { });
        QVERIFY(reset.error().isEmpty());
        reset.reset(true);
        m_done(1, QStringLiteral("orielos-reset: a reset is already being prepared"));
        QCOMPARE(reset.error(), QStringLiteral("Couldn't start the reset: orielos-reset: a reset is already being prepared"));
    }

    void followsTheStateFile()
    {
        ResetPC reset(environment(), nullptr);
        QSignalSpy changed(&reset, &ResetPC::changed);
        writeFile(statePath(), state("checking"));
        QTRY_VERIFY(reset.isWorking());
        QVERIFY(!changed.isEmpty());
    }
};

QTEST_GUILESS_MAIN(ResetPCTest)

#include "resetpctest.moc"
