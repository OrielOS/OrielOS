// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "runtarget.h"

#include <QDir>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

using RunBox::Target;

namespace {

// Only these programs are installed.
QString findInstalled(const QString &program)
{
    static const QStringList installed = { QStringLiteral("konsole"), QStringLiteral("dolphin"), QStringLiteral("orielos-settings"),
        QStringLiteral("plasma-systemmonitor"), QStringLiteral("firefox") };
    return installed.contains(program) ? QStringLiteral("/usr/bin/") + program : QString();
}

Target resolve(const QString &text, const QString &home = QStringLiteral("/home/test"))
{
    return RunBox::resolve(text, home, findInstalled);
}

} // namespace

class RunTargetTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void nothingTyped() { QCOMPARE(resolve(QStringLiteral("   ")).kind, Target::Kind::Empty); }

    void addresses()
    {
        QCOMPARE(resolve(QStringLiteral("https://orielos.org")).kind, Target::Kind::Url);
        QCOMPARE(resolve(QStringLiteral(" https://orielos.org ")).value, QStringLiteral("https://orielos.org"));
        QCOMPARE(resolve(QStringLiteral("mailto:someone@example.org")).kind, Target::Kind::Url);
        const Target web = resolve(QStringLiteral("www.orielos.org"));
        QCOMPARE(web.kind, Target::Kind::Url);
        QCOMPARE(web.value, QStringLiteral("https://www.orielos.org"));
    }

    void pathsThatExist()
    {
        QTemporaryDir home;
        QVERIFY(QDir(home.path()).mkpath(QStringLiteral("My Documents")));
        const Target absolute = resolve(home.path(), home.path());
        QCOMPARE(absolute.kind, Target::Kind::Path);
        QCOMPARE(absolute.value, QUrl::fromLocalFile(home.path()).toString());

        const Target tilde = resolve(QStringLiteral("~/My Documents"), home.path());
        QCOMPARE(tilde.kind, Target::Kind::Path);
        QCOMPARE(QUrl(tilde.value).toLocalFile(), home.filePath(QStringLiteral("My Documents")));

        // As Browse puts it in the box.
        const Target quoted = resolve(QLatin1Char('"') + home.filePath(QStringLiteral("My Documents")) + QLatin1Char('"'), home.path());
        QCOMPARE(quoted.kind, Target::Kind::Path);

        QCOMPARE(resolve(QStringLiteral("~"), home.path()).kind, Target::Kind::Path);
        QCOMPARE(resolve(home.filePath(QStringLiteral("missing")), home.path()).kind, Target::Kind::NotFound);
    }

    void commands()
    {
        const Target plain = resolve(QStringLiteral("firefox"));
        QCOMPARE(plain.kind, Target::Kind::Command);
        QCOMPARE(plain.value, QStringLiteral("firefox"));

        const Target arguments = resolve(QStringLiteral("firefox --private-window \"https://orielos.org/a b\""));
        QCOMPARE(arguments.kind, Target::Kind::Command);
        QCOMPARE(arguments.value, QStringLiteral("firefox --private-window \"https://orielos.org/a b\""));

        QCOMPARE(resolve(QStringLiteral("notaprogram")).kind, Target::Kind::NotFound);
        QCOMPARE(resolve(QStringLiteral("notaprogram")).value, QStringLiteral("notaprogram"));
    }

    void windowsNames_data()
    {
        QTest::addColumn<QString>("typed");
        QTest::addColumn<QString>("command");
        QTest::newRow("cmd") << QStringLiteral("cmd") << QStringLiteral("konsole");
        QTest::newRow("cmd.exe") << QStringLiteral("CMD.EXE") << QStringLiteral("konsole");
        QTest::newRow("powershell") << QStringLiteral("powershell") << QStringLiteral("konsole");
        QTest::newRow("explorer with a folder") << QStringLiteral("explorer /tmp") << QStringLiteral("dolphin /tmp");
        QTest::newRow("control") << QStringLiteral("control") << QStringLiteral("orielos-settings");
        QTest::newRow("taskmgr") << QStringLiteral("taskmgr") << QStringLiteral("plasma-systemmonitor");
    }

    void windowsNames()
    {
        QFETCH(QString, typed);
        QFETCH(QString, command);
        const Target target = resolve(typed);
        QCOMPARE(target.kind, Target::Kind::Command);
        QCOMPARE(target.value, command);
    }

    void windowsProgramsWithoutAnEquivalent()
    {
        QCOMPARE(resolve(QStringLiteral("regedit")).kind, Target::Kind::NotFound);
        QCOMPARE(RunBox::equivalentProgram(QStringLiteral("regedit")), QStringLiteral("regedit"));
    }

    void history()
    {
        const QStringList history = { QStringLiteral("cmd"), QStringLiteral("firefox"), QStringLiteral("control") };
        QCOMPARE(RunBox::remember(history, QStringLiteral(" control ")),
            (QStringList { QStringLiteral("control"), QStringLiteral("cmd"), QStringLiteral("firefox") }));
        QCOMPARE(RunBox::remember(history, QStringLiteral("  ")), history);

        QStringList full;
        for (int i = 0; i < RunBox::HistoryLength; ++i) {
            full.append(QString::number(i));
        }
        const QStringList newest = RunBox::remember(full, QStringLiteral("new"));
        QCOMPARE(newest.size(), RunBox::HistoryLength);
        QCOMPARE(newest.first(), QStringLiteral("new"));
        QVERIFY(!newest.contains(QString::number(RunBox::HistoryLength - 1)));
    }
};

QTEST_GUILESS_MAIN(RunTargetTest)

#include "runtargettest.moc"
