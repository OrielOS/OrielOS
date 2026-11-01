// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "setupcorner.h"

#include <QTest>

class SetupCornerTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void readsWirePlumbersVolume_data()
    {
        QTest::addColumn<QString>("output");
        QTest::addColumn<int>("volume");
        QTest::addColumn<bool>("muted");
        QTest::newRow("plain") << QStringLiteral("Volume: 0.40\n") << 40 << false;
        QTest::newRow("muted") << QStringLiteral("Volume: 0.75 [MUTED]\n") << 75 << true;
        QTest::newRow("louder than full") << QStringLiteral("Volume: 1.20\n") << 100 << false;
        QTest::newRow("no speakers") << QStringLiteral("Couldn't find the node\n") << 0 << false;
    }

    void readsWirePlumbersVolume()
    {
        QFETCH(QString, output);
        QFETCH(int, volume);
        QFETCH(bool, muted);
        const auto [readVolume, readMuted] = SetupCorner::parseVolume(output);
        QCOMPARE(readVolume, volume);
        QCOMPARE(readMuted, muted);
    }
};

QTEST_GUILESS_MAIN(SetupCornerTest)

#include "setupcornertest.moc"
