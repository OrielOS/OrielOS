// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "traylogic.h"

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
};

QTEST_GUILESS_MAIN(TrayLogicTest)

#include "traylogictest.moc"
