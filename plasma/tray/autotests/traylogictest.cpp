// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "traylogic.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class TrayLogicTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void newIconsStartHidden()
    {
        const Tray::Split split = Tray::split({ QStringLiteral("steam"), QStringLiteral("discord") }, { }, { });
        QVERIFY(split.taskbar.isEmpty());
        QCOMPARE(split.pane, QStringList({ QStringLiteral("steam"), QStringLiteral("discord") }));
    }

    void shownIconsKeepTheirOrder()
    {
        const Tray::Split split = Tray::split(
            { QStringLiteral("steam"), QStringLiteral("discord"), QStringLiteral("obs") }, { }, { QStringLiteral("obs"), QStringLiteral("steam") });
        QCOMPARE(split.taskbar, QStringList({ QStringLiteral("obs"), QStringLiteral("steam") }));
        QCOMPARE(split.pane, QStringList({ QStringLiteral("discord") }));
    }

    void appsNotRunningAreLeftOut()
    {
        const Tray::Split split = Tray::split({ QStringLiteral("steam") }, { }, { QStringLiteral("discord"), QStringLiteral("steam") });
        QCOMPARE(split.taskbar, QStringList({ QStringLiteral("steam") }));
        QVERIFY(split.pane.isEmpty());
    }

    void passiveIconsStayInThePane()
    {
        const Tray::Split split = Tray::split(
            { QStringLiteral("updates"), QStringLiteral("steam") }, { QStringLiteral("updates") }, { QStringLiteral("updates"), QStringLiteral("steam") });
        QCOMPARE(split.taskbar, QStringList({ QStringLiteral("steam") }));
        QCOMPARE(split.pane, QStringList({ QStringLiteral("updates") }));
    }

    void droppingOnTheTaskbar()
    {
        const QStringList shown = { QStringLiteral("a"), QStringLiteral("b") };
        QCOMPARE(Tray::showAt(shown, QStringLiteral("c"), 1), QStringList({ QStringLiteral("a"), QStringLiteral("c"), QStringLiteral("b") }));
        QCOMPARE(Tray::showAt(shown, QStringLiteral("c"), 99), QStringList({ QStringLiteral("a"), QStringLiteral("b"), QStringLiteral("c") }));
        QCOMPARE(Tray::showAt(shown, QStringLiteral("c"), -3), QStringList({ QStringLiteral("c"), QStringLiteral("a"), QStringLiteral("b") }));
        // Moving an icon along the taskbar.
        QCOMPARE(Tray::showAt(shown, QStringLiteral("a"), 1), QStringList({ QStringLiteral("b"), QStringLiteral("a") }));
    }

    void droppingInThePane()
    {
        QCOMPARE(Tray::hide({ QStringLiteral("a"), QStringLiteral("b") }, QStringLiteral("a")), QStringList({ QStringLiteral("b") }));
        QCOMPARE(Tray::hide({ QStringLiteral("a") }, QStringLiteral("z")), QStringList({ QStringLiteral("a") }));
    }

    void driveNames()
    {
        QCOMPARE(Tray::driveName(QStringLiteral(" HOLIDAY "), QStringLiteral("SanDisk"), QStringLiteral("Ultra"), QStringLiteral("32 GB Removable Media")),
            QStringLiteral("HOLIDAY"));
        QCOMPARE(Tray::driveName(QString(), QStringLiteral("SanDisk"), QStringLiteral("Ultra"), QStringLiteral("32 GB Removable Media")),
            QStringLiteral("SanDisk Ultra"));
        QCOMPARE(Tray::driveName(QString(), QString(), QStringLiteral("Ultra"), QString()), QStringLiteral("Ultra"));
        QCOMPARE(Tray::driveName(QString(), QString(), QString(), QStringLiteral("32 GB Removable Media")), QStringLiteral("32 GB Removable Media"));
    }

    void processesUsingADrive()
    {
        // A stand-in /proc: Discord has a file open on the drive, a shell is in a folder on it,
        // Firefox has nothing there, and a second Discord process is named once.
        QTemporaryDir proc;
        QVERIFY(proc.isValid());
        const QString drive = QStringLiteral("/run/media/nathan/HOLIDAY");
        const auto process = [&proc](const QString &pid, const QString &comm, const QString &cwd, const QStringList &files) {
            QDir(proc.path()).mkpath(pid + QStringLiteral("/fd"));
            const QString base = proc.path() + QLatin1Char('/') + pid;
            QFile name(base + QStringLiteral("/comm"));
            QVERIFY(name.open(QIODevice::WriteOnly));
            name.write(comm.toUtf8() + '\n');
            name.close();
            QVERIFY(QFile::link(cwd, base + QStringLiteral("/cwd")));
            for (qsizetype i = 0; i < files.size(); ++i) {
                QVERIFY(QFile::link(files.at(i), base + QStringLiteral("/fd/") + QString::number(i)));
            }
        };
        process(QStringLiteral("100"), QStringLiteral("discord"), QStringLiteral("/home/nathan"),
            { QStringLiteral("/dev/null"), drive + QStringLiteral("/photo.jpg") });
        process(QStringLiteral("200"), QStringLiteral("bash"), drive + QStringLiteral("/Trips"), { });
        process(QStringLiteral("300"), QStringLiteral("firefox"), QStringLiteral("/home/nathan"), { QStringLiteral("/run/media/nathan/HOLIDAY2/x") });
        process(QStringLiteral("400"), QStringLiteral("discord"), drive, { });
        QDir(proc.path()).mkpath(QStringLiteral("self"));

        QCOMPARE(Tray::processesUsing({ drive }, proc.path()), (QStringList { QStringLiteral("discord"), QStringLiteral("bash") }));
        QVERIFY(Tray::processesUsing({ QStringLiteral("/run/media/nathan/OTHER") }, proc.path()).isEmpty());
        QVERIFY(Tray::processesUsing({ QString() }, proc.path()).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TrayLogicTest)

#include "traylogictest.moc"
