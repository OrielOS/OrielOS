// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "networkcheck.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantMap>

using namespace OrielOSNetwork;

namespace {

QByteArray line(const char *check, const char *result, const char *reason = "", const char *fix = "")
{
    return QStringLiteral(R"({"check": "%1", "result": "%2", "reason": "%3", "message": "In English.", "fix": "%4"})")
        .arg(QLatin1String(check), QLatin1String(result), QLatin1String(reason), QLatin1String(fix))
        .toUtf8();
}

QByteArray allGood()
{
    return line("adapter", "ok", "adapter-wifi") + '\n' + line("radio", "ok", "radio-ok") + '\n' + line("connected", "ok", "connected") + '\n'
        + line("address", "ok", "address-ok") + '\n' + line("gateway", "ok", "gateway-ok") + '\n' + line("dns", "ok", "dns-ok") + '\n'
        + line("internet", "ok", "internet-ok") + '\n';
}

QByteArray dnsDown()
{
    return line("adapter", "ok", "adapter-wifi") + '\n' + line("radio", "ok", "radio-ok") + '\n' + line("connected", "ok", "connected") + '\n'
        + line("address", "ok", "address-ok") + '\n' + line("gateway", "ok", "gateway-ok") + '\n' + line("dns", "problem", "dns-failed", "flush-dns") + '\n'
        + line("internet", "skipped") + '\n';
}

QString stateOf(const NetworkCheck &network, const QString &id)
{
    for (const QVariant &check : network.checks()) {
        const QVariantMap map = check.toMap();
        if (map.value(QStringLiteral("id")).toString() == id) {
            return map.value(QStringLiteral("state")).toString();
        }
    }
    return { };
}

QString detailOf(const NetworkCheck &network, const QString &id)
{
    for (const QVariant &check : network.checks()) {
        const QVariantMap map = check.toMap();
        if (map.value(QStringLiteral("id")).toString() == id) {
            return map.value(QStringLiteral("detail")).toString();
        }
    }
    return { };
}

} // namespace

class NetworkCheckTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    QString m_lastProgram;
    QStringList m_lastArguments;
    std::function<void(int, const QString &)> m_done;

    // A stand-in for network-check that prints these lines and exits with this code.
    QString fakeCheck(const QByteArray &output, int exitCode = 0)
    {
        const QString data = m_dir.filePath(QStringLiteral("output"));
        QFile out(data);
        if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            return { };
        }
        out.write(output);
        out.close();
        const QString path = m_dir.filePath(QStringLiteral("network-check"));
        QFile script(path);
        if (!script.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            return { };
        }
        script.write(QStringLiteral("#!/bin/sh\ncat '%1'\nexit %2\n").arg(data).arg(exitCode).toUtf8());
        script.close();
        script.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        return path;
    }

    NetworkCheck::Environment environment(const QByteArray &output, int exitCode = 0)
    {
        return NetworkCheck::Environment {
            fakeCheck(output, exitCode),
            [this](const QString &program, const QStringList &arguments, std::function<void(int, const QString &)> done) {
                m_lastProgram = program;
                m_lastArguments = arguments;
                m_done = std::move(done);
            },
        };
    }

private Q_SLOTS:
    void init()
    {
        m_lastProgram.clear();
        m_lastArguments.clear();
        m_done = nullptr;
    }

    void parsesALine()
    {
        const auto result = CheckResult::parse(line("radio", "problem", "wifi-off", "wifi-on"));
        QVERIFY(result.has_value());
        QCOMPARE(result->check, QStringLiteral("radio"));
        QCOMPARE(result->result, CheckResult::Result::Problem);
        QCOMPARE(result->reason, QStringLiteral("wifi-off"));
        QCOMPARE(result->message, QStringLiteral("In English."));
        QCOMPARE(result->fix, QStringLiteral("wifi-on"));
        QCOMPARE(CheckResult::parse(line("dns", "ok"))->result, CheckResult::Result::Ok);
        QCOMPARE(CheckResult::parse(line("dns", "skipped"))->result, CheckResult::Result::Skipped);
        QVERIFY(!CheckResult::parse("not json").has_value());
        QVERIFY(!CheckResult::parse(R"({"result": "ok"})").has_value());
    }

    void takesOnlyCompleteLines()
    {
        const QByteArray second = line("radio", "ok", "radio-ok");
        QByteArray buffer = line("adapter", "ok", "adapter-wifi") + '\n' + second.left(10);
        QList<CheckResult> results = CheckResult::takeLines(buffer);
        QCOMPARE(results.size(), 1);
        QCOMPARE(results.first().check, QStringLiteral("adapter"));
        QCOMPARE(buffer, second.left(10));

        buffer.append(second.mid(10) + "\n\nnoise\n");
        results = CheckResult::takeLines(buffer);
        QCOMPARE(results.size(), 1);
        QCOMPARE(results.first().check, QStringLiteral("radio"));
        QVERIFY(buffer.isEmpty());
    }

    void allPassing()
    {
        NetworkCheck network(environment(allGood()), nullptr);
        QVERIFY(network.isRunning());
        QCOMPARE(stateOf(network, QStringLiteral("adapter")), QStringLiteral("running"));
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(network.allPassed());
        QVERIFY(network.problem().isEmpty());
        QVERIFY(network.error().isEmpty());
        QCOMPARE(network.checks().size(), 7);
        QCOMPARE(detailOf(network, QStringLiteral("adapter")), QStringLiteral("Wi-Fi"));
    }

    void showsTheFirstProblemAndSkipsTheRest()
    {
        NetworkCheck network(environment(dnsDown()), nullptr);
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(!network.allPassed());
        QCOMPARE(stateOf(network, QStringLiteral("gateway")), QStringLiteral("ok"));
        QCOMPARE(stateOf(network, QStringLiteral("dns")), QStringLiteral("problem"));
        QCOMPARE(stateOf(network, QStringLiteral("internet")), QStringLiteral("skipped"));
        QCOMPARE(network.problem(), QStringLiteral("Website names can't be looked up, so websites won't open."));
        QCOMPARE(network.problemFix(), QStringLiteral("flush-dns"));
        QVERIFY(network.error().isEmpty());
    }

    void fallsBackToTheMessageForAnUnknownReason()
    {
        NetworkCheck network(environment(line("adapter", "problem", "something-new") + '\n'), nullptr);
        QTRY_VERIFY(!network.isRunning());
        QCOMPARE(network.problem(), QStringLiteral("In English."));
        QVERIFY(network.problemFix().isEmpty());
    }

    void reportsChecksThatStopEarly()
    {
        NetworkCheck network(environment(line("adapter", "ok", "adapter-wifi") + '\n', 1), nullptr);
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(!network.error().isEmpty());
        QCOMPARE(stateOf(network, QStringLiteral("adapter")), QStringLiteral("ok"));
        QCOMPARE(stateOf(network, QStringLiteral("radio")), QStringLiteral("pending"));
        QVERIFY(!network.allPassed());
    }

    void reportsAMissingProgram()
    {
        NetworkCheck network(NetworkCheck::Environment { m_dir.filePath(QStringLiteral("missing")), nullptr }, nullptr);
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(!network.error().isEmpty());
    }

    void fixesRunThroughNetworkCheck()
    {
        NetworkCheck network(environment(dnsDown()), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(network.problemFix());
        QVERIFY(network.isFixing());
        QCOMPARE(m_lastProgram, m_dir.filePath(QStringLiteral("network-check")));
        QCOMPARE(m_lastArguments, (QStringList { QStringLiteral("fix"), QStringLiteral("flush-dns") }));
        // A second fix while one runs does nothing.
        m_lastArguments.clear();
        network.fix(QStringLiteral("reconnect"));
        QVERIFY(m_lastArguments.isEmpty());
    }

    void restartingNetworkManagerGoesThroughPkexec()
    {
        NetworkCheck network(environment(line("adapter", "problem", "nm-not-running", "restart-networking") + '\n'), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(network.problemFix());
        QCOMPARE(m_lastProgram, QStringLiteral("pkexec"));
        QCOMPARE(m_lastArguments, (QStringList { QStringLiteral("/usr/libexec/orielos/restart-networking") }));
    }

    void checksAgainAfterAFix()
    {
        NetworkCheck network(environment(dnsDown()), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(QStringLiteral("flush-dns"));
        m_done(0, { });
        QVERIFY(!network.isFixing());
        QVERIFY(network.isRunning());
        QTRY_VERIFY(!network.isRunning());
        // The fake still finds the same problem, so the fix didn't help.
        QVERIFY(!network.notice().isEmpty());
        QVERIFY(network.error().isEmpty());
    }

    void aDismissedPasswordPromptChangesNothing()
    {
        NetworkCheck network(environment(line("adapter", "problem", "nm-not-running", "restart-networking") + '\n'), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(network.problemFix());
        m_done(126, { });
        QVERIFY(!network.isFixing());
        QVERIFY(!network.isRunning());
        QVERIFY(network.error().isEmpty());
        QVERIFY(network.notice().isEmpty());
    }

    void reportsAFailedFix()
    {
        NetworkCheck network(environment(dnsDown()), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(QStringLiteral("flush-dns"));
        m_done(1, QStringLiteral("network-check: couldn't clear the saved website names"));
        QCOMPARE(network.error(), QStringLiteral("That fix didn't work: network-check: couldn't clear the saved website names"));
        // It checks again anyway, and keeps saying what went wrong.
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(!network.error().isEmpty());
        QVERIFY(network.notice().isEmpty());
    }

    void theSignInPageNeedsTheUserFirst()
    {
        NetworkCheck network(environment(line("internet", "problem", "portal", "open-portal") + '\n'), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(network.problemFix());
        QCOMPARE(m_lastArguments, (QStringList { QStringLiteral("fix"), QStringLiteral("open-portal") }));
        m_done(0, { });
        QVERIFY(!network.isRunning());
        QVERIFY(!network.notice().isEmpty());
    }

    void checkAgainClearsWhatWasSaid()
    {
        NetworkCheck network(environment(dnsDown()), nullptr);
        QTRY_VERIFY(!network.isRunning());
        network.fix(QStringLiteral("flush-dns"));
        m_done(0, { });
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(!network.notice().isEmpty());
        network.run();
        QVERIFY(network.isRunning());
        QVERIFY(network.notice().isEmpty());
        QTRY_VERIFY(!network.isRunning());
        QVERIFY(network.notice().isEmpty());
    }
};

QTEST_GUILESS_MAIN(NetworkCheckTest)

#include "networkchecktest.moc"
