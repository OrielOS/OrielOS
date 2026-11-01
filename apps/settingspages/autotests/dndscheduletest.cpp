// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "dndschedule.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using OrielOSSettingsPages::DndSchedule;

class DndScheduleTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    static QString read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
    }

    // Settings in a file of their own, and a stand-in for systemctl that appends its arguments to a
    // record, one call to a line.
    struct Setup
    {
        QString config;
        QString dropIn;
        QString record;
    };

    Setup setUp(DndSchedule &schedule, const QByteArray &contents = { })
    {
        const QString name = QString::fromLatin1(QTest::currentTestFunction());
        Setup setup { m_dir.filePath(name + QStringLiteral("-rc")), m_dir.filePath(name + QStringLiteral("-timer.d")),
            m_dir.filePath(name + QStringLiteral("-calls")) };
        QFile file(setup.config);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(contents);
        }
        file.close();
        schedule.setForTesting(setup.config, setup.dropIn, QStringLiteral("sh"),
            { QStringLiteral("-c"), QStringLiteral("echo \"$@\" >> %1").arg(setup.record), QStringLiteral("systemctl") });
        return setup;
    }

private Q_SLOTS:
    void calendars()
    {
        QCOMPARE(DndSchedule::calendar(DndSchedule::EveryDay, 22 * 60), QStringLiteral("*-*-* 22:00:00"));
        QCOMPARE(DndSchedule::calendar(DndSchedule::Weekdays, 7 * 60 + 30), QStringLiteral("Mon..Fri *-*-* 07:30:00"));
        QCOMPARE(DndSchedule::calendar(DndSchedule::Weekends, 0), QStringLiteral("Sat,Sun *-*-* 00:00:00"));
    }

    void readsTheSettings()
    {
        DndSchedule schedule;
        setUp(schedule, "[Schedule]\nEnabled=true\nFrom=23:15\nTo=6:45\nDays=weekends\n");
        QVERIFY(schedule.isEnabled());
        QCOMPARE(schedule.from(), 23 * 60 + 15);
        QCOMPARE(schedule.to(), 6 * 60 + 45);
        QCOMPARE(schedule.days(), DndSchedule::Weekends);
    }

    void startsWithWindowsHours()
    {
        DndSchedule schedule;
        setUp(schedule);
        QVERIFY(!schedule.isEnabled());
        QCOMPARE(schedule.from(), 22 * 60);
        QCOMPARE(schedule.to(), 7 * 60);
        QCOMPARE(schedule.days(), DndSchedule::EveryDay);
    }

    void turningOnSchedulesTheTimer()
    {
        DndSchedule schedule;
        const Setup setup = setUp(schedule);
        QSignalSpy changed(&schedule, &DndSchedule::changed);
        schedule.setDays(DndSchedule::Weekdays);
        schedule.setFrom(21 * 60 + 30);
        schedule.setEnabled(true);
        QCOMPARE(changed.count(), 3);

        const QString config = read(setup.config);
        QVERIFY2(config.contains(QLatin1String("Enabled=true")), qPrintable(config));
        QVERIFY2(config.contains(QLatin1String("From=21:30")), qPrintable(config));
        QVERIFY2(config.contains(QLatin1String("To=07:00")), qPrintable(config));
        QVERIFY2(config.contains(QLatin1String("Days=weekdays")), qPrintable(config));
        const QString dropIn = read(setup.dropIn + QStringLiteral("/schedule.conf"));
        QVERIFY2(dropIn.contains(QLatin1String("OnCalendar=\nOnCalendar=Mon..Fri *-*-* 21:30:00\n")), qPrintable(dropIn));
        const QStringList calls = read(setup.record).trimmed().split(QLatin1Char('\n'));
        QCOMPARE(calls.mid(calls.size() - 3),
            (QStringList { QStringLiteral("daemon-reload"), QStringLiteral("enable --now orielos-dnd-schedule.timer"),
                QStringLiteral("start orielos-dnd-schedule.service") }));

        schedule.setEnabled(false);
        const QStringList after = read(setup.record).trimmed().split(QLatin1Char('\n'));
        QCOMPARE(after.constLast(), QStringLiteral("disable --now orielos-dnd-schedule.timer"));
    }

    void keepsTimesInADay()
    {
        DndSchedule schedule;
        setUp(schedule);
        schedule.setTo(-5);
        QCOMPARE(schedule.to(), 0);
        schedule.setFrom(24 * 60 + 10);
        QCOMPARE(schedule.from(), 24 * 60 - 1);
    }
};

QTEST_GUILESS_MAIN(DndScheduleTest)

#include "dndscheduletest.moc"
