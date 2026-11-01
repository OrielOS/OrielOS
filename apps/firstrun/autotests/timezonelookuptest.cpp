// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "timezonelookup.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace std::chrono_literals;

class TimeZoneLookupTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void readsTheTimeZoneFromTheAnswer()
    {
        QCOMPARE(TimeZoneLookup::zoneFromReply(R"({"country_code": "GB", "time_zone": "Europe/London"})"), QStringLiteral("Europe/London"));
        QCOMPARE(TimeZoneLookup::zoneFromReply(R"({"time_zone": "America/Argentina/Buenos_Aires"})"),
            QStringLiteral("America/Argentina/Buenos_Aires"));
    }

    void leavesOutAnythingElse()
    {
        QCOMPARE(TimeZoneLookup::zoneFromReply(R"({"country_code": "GB"})"), QString());
        QCOMPARE(TimeZoneLookup::zoneFromReply(R"({"time_zone": null})"), QString());
        QCOMPARE(TimeZoneLookup::zoneFromReply(R"({"time_zone": "Atlantis/Lost_City"})"), QString());
        QCOMPARE(TimeZoneLookup::zoneFromReply(R"({"time_zone": "../../etc/passwd"})"), QString());
        QCOMPARE(TimeZoneLookup::zoneFromReply("<html>Service unavailable</html>"), QString());
        QCOMPARE(TimeZoneLookup::zoneFromReply(QByteArray()), QString());
    }

    void triesAgainUntilTheNetworkAnswers()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath(QStringLiteral("city"));

        // No answer yet, as without a network: the lookup waits and asks again.
        TimeZoneLookup lookup;
        lookup.setSourceForTesting(QUrl::fromLocalFile(path), 50ms);
        QSignalSpy found(&lookup, &TimeZoneLookup::zoneChanged);
        QTest::qWait(200);
        QCOMPARE(found.count(), 0);
        QVERIFY(lookup.zone().isEmpty());

        QFile city(path);
        QVERIFY(city.open(QIODevice::WriteOnly));
        city.write(R"({"time_zone": "Europe/Paris"})");
        city.close();
        QVERIFY(found.wait(2000));
        QCOMPARE(lookup.zone(), QStringLiteral("Europe/Paris"));

        // Found once, it stops asking.
        QVERIFY(city.open(QIODevice::WriteOnly | QIODevice::Truncate));
        city.write(R"({"time_zone": "Asia/Tokyo"})");
        city.close();
        QTest::qWait(200);
        QCOMPARE(found.count(), 1);
        QCOMPARE(lookup.zone(), QStringLiteral("Europe/Paris"));
    }
};

QTEST_GUILESS_MAIN(TimeZoneLookupTest)

#include "timezonelookuptest.moc"
