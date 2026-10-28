// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "displaylayout.h"

#include <QTest>

using namespace DisplayLayout;

class DisplayLayoutTest : public QObject
{
    Q_OBJECT

private:
    // A laptop's built-in screen (id 2, 1536 × 864 at 125 %) and a monitor (id 1, 2560 × 1440),
    // listed monitor first, as an id-ordered list would have them; only the laptop's is on.
    static QList<Screen> laptopAndMonitor()
    {
        Screen monitor;
        monitor.id = 1;
        monitor.logicalSize = QSize(2560, 1440);
        Screen laptop;
        laptop.id = 2;
        laptop.main = true;
        laptop.enabled = true;
        laptop.logicalSize = QSize(1536, 864);
        laptop.priority = 1;
        return { monitor, laptop };
    }

    static Screen byId(const QList<Screen> &screens, int id)
    {
        for (const Screen &screen : screens) {
            if (screen.id == id) {
                return screen;
            }
        }
        return { };
    }

private Q_SLOTS:
    void singleScreenIsAlwaysMainOnly()
    {
        Screen only;
        only.id = 7;
        only.enabled = true;
        only.logicalSize = QSize(1920, 1080);
        QCOMPARE(currentMode({ only }), Mode::MainOnly);
        const QList<Screen> arranged = arrange({ only }, Mode::OthersOnly);
        QCOMPARE(arranged.size(), 1);
        QVERIFY(arranged.first().enabled);
        QCOMPARE(arranged.first().priority, 1u);
        QCOMPARE(currentMode(arranged), Mode::MainOnly);
    }

    void startsMainOnly() { QCOMPARE(currentMode(laptopAndMonitor()), Mode::MainOnly); }

    void extendPutsTheMainScreenLeftOfTheOthers()
    {
        const QList<Screen> arranged = arrange(laptopAndMonitor(), Mode::Extend);
        const Screen laptop = byId(arranged, 2);
        const Screen monitor = byId(arranged, 1);
        QVERIFY(laptop.enabled);
        QVERIFY(monitor.enabled);
        QCOMPARE(laptop.position, QPoint(0, 0));
        QCOMPARE(monitor.position, QPoint(1536, 0));
        QCOMPARE(laptop.priority, 1u);
        QCOMPARE(monitor.priority, 2u);
        QCOMPARE(monitor.replicationSource, 0);
        QCOMPARE(currentMode(arranged), Mode::Extend);
    }

    void duplicateMirrorsTheMainScreen()
    {
        const QList<Screen> arranged = arrange(laptopAndMonitor(), Mode::Duplicate);
        const Screen monitor = byId(arranged, 1);
        QVERIFY(monitor.enabled);
        QCOMPARE(monitor.replicationSource, 2);
        QCOMPARE(monitor.position, QPoint(0, 0));
        QCOMPARE(byId(arranged, 2).replicationSource, 0);
        QCOMPARE(currentMode(arranged), Mode::Duplicate);
    }

    void othersOnlyTurnsTheMainScreenOff()
    {
        const QList<Screen> arranged = arrange(laptopAndMonitor(), Mode::OthersOnly);
        const Screen laptop = byId(arranged, 2);
        const Screen monitor = byId(arranged, 1);
        QVERIFY(!laptop.enabled);
        QCOMPARE(laptop.priority, 0u);
        QVERIFY(monitor.enabled);
        QCOMPARE(monitor.position, QPoint(0, 0));
        QCOMPARE(monitor.priority, 1u);
        QCOMPARE(currentMode(arranged), Mode::OthersOnly);
    }

    void mainOnlyAfterExtendTurnsTheOthersOffAndClearsMirroring()
    {
        const QList<Screen> duplicated = arrange(laptopAndMonitor(), Mode::Duplicate);
        const QList<Screen> arranged = arrange(duplicated, Mode::MainOnly);
        QVERIFY(byId(arranged, 2).enabled);
        QVERIFY(!byId(arranged, 1).enabled);
        QCOMPARE(byId(arranged, 1).replicationSource, 0);
        QCOMPARE(currentMode(arranged), Mode::MainOnly);
    }

    void withoutABuiltInScreenTheFirstIsMain()
    {
        QList<Screen> screens = laptopAndMonitor();
        screens[1].main = false;
        const QList<Screen> arranged = arrange(screens, Mode::OthersOnly);
        QVERIFY(!byId(arranged, 1).enabled);
        QVERIFY(byId(arranged, 2).enabled);
    }

    void threeScreensExtendInARow()
    {
        QList<Screen> screens = laptopAndMonitor();
        Screen third;
        third.id = 3;
        third.logicalSize = QSize(1920, 1080);
        screens.append(third);
        const QList<Screen> arranged = arrange(screens, Mode::Extend);
        QCOMPARE(byId(arranged, 2).position, QPoint(0, 0));
        QCOMPARE(byId(arranged, 1).position, QPoint(1536, 0));
        QCOMPARE(byId(arranged, 3).position, QPoint(1536 + 2560, 0));
        QCOMPARE(byId(arranged, 3).priority, 3u);
    }
};

QTEST_GUILESS_MAIN(DisplayLayoutTest)

#include "displaylayouttest.moc"
