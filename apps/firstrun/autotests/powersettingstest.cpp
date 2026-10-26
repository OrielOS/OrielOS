// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "powersettings.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <algorithm>

class PowerSettingsTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    QString logPath() const { return m_dir.filePath(QStringLiteral("runs.log")); }

    // Each run appends its arguments as a line to runs.log, waits the given time and exits with
    // the given status.
    void useRecorder(PowerSettings &settings, int exitCode = 0, const QString &delay = QStringLiteral("0"))
    {
        const QString script = QStringLiteral("sleep %1; echo \"$*\" >>'%2'; exit %3").arg(delay, logPath()).arg(exitCode);
        settings.setCommandForTesting(QStringLiteral("/bin/sh"), { QStringLiteral("-c"), script, QStringLiteral("first-run-power") });
    }

    QStringList runs() const
    {
        QFile file(logPath());
        if (!file.open(QIODevice::ReadOnly)) {
            return { };
        }
        return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    }

private Q_SLOTS:
    void init() { QFile::remove(logPath()); }

    void defaultsArePowerDevils()
    {
        PowerSettings settings;
        QVERIFY(settings.sleepWhenIdle());
        QCOMPARE(settings.sleepAfterMinutes(), 15);
        QCOMPARE(settings.screenOffAfterMinutes(), 10);
        QCOMPARE(settings.helperArguments(), (QStringList { QStringLiteral("15"), QStringLiteral("10") }));
    }

    void savingTheDefaultsRunsNothing()
    {
        PowerSettings settings;
        useRecorder(settings);
        settings.save();
        QVERIFY(!settings.saving());
        QVERIFY(runs().isEmpty());
    }

    void savesAChangeOnce()
    {
        PowerSettings settings;
        useRecorder(settings);
        QSignalSpy saved(&settings, &PowerSettings::saved);
        settings.setSleepAfterMinutes(30);
        settings.save();
        QVERIFY(settings.saving());
        QVERIFY(saved.wait());
        QCOMPARE(saved.first().first().toBool(), true);
        QVERIFY(!settings.saving());
        QCOMPARE(runs(), QStringList { QStringLiteral("30 10") });
        settings.save();
        QVERIFY(!settings.saving());
        QCOMPARE(runs().size(), 1);
    }

    void neverIsZero()
    {
        PowerSettings settings;
        settings.setSleepWhenIdle(false);
        settings.setScreenOffAfterMinutes(0);
        QCOMPARE(settings.helperArguments(), (QStringList { QStringLiteral("0"), QStringLiteral("0") }));
        settings.setSleepWhenIdle(true);
        QCOMPARE(settings.helperArguments(), (QStringList { QStringLiteral("15"), QStringLiteral("0") }));
    }

    void minutesStayInRange()
    {
        PowerSettings settings;
        settings.setSleepAfterMinutes(0);
        QCOMPARE(settings.sleepAfterMinutes(), 1);
        settings.setSleepAfterMinutes(5000);
        QCOMPARE(settings.sleepAfterMinutes(), PowerSettings::maxMinutes);
        settings.setScreenOffAfterMinutes(-3);
        QCOMPARE(settings.screenOffAfterMinutes(), 0);
        settings.setScreenOffAfterMinutes(5000);
        QCOMPARE(settings.screenOffAfterMinutes(), PowerSettings::maxMinutes);
    }

    void aFailureIsReportedAndRetried()
    {
        PowerSettings settings;
        useRecorder(settings, 1);
        QSignalSpy saved(&settings, &PowerSettings::saved);
        settings.setScreenOffAfterMinutes(5);
        settings.save();
        QVERIFY(saved.wait());
        QCOMPARE(saved.last().first().toBool(), false);
        QVERIFY(!settings.error().isEmpty());

        // The same choices weren't saved, so the next call tries again.
        useRecorder(settings, 0);
        settings.save();
        QVERIFY(saved.wait());
        QCOMPARE(saved.last().first().toBool(), true);
        QVERIFY(settings.error().isEmpty());
        QCOMPARE(runs(), (QStringList { QStringLiteral("15 5"), QStringLiteral("15 5") }));
    }

    void aHelperThatDoesntStartIsAFailure()
    {
        PowerSettings settings;
        settings.setCommandForTesting(m_dir.filePath(QStringLiteral("missing")), { });
        QSignalSpy saved(&settings, &PowerSettings::saved);
        settings.setSleepWhenIdle(false);
        settings.save();
        QTRY_COMPARE(saved.size(), 1);
        QCOMPARE(saved.first().first().toBool(), false);
        QVERIFY(!settings.error().isEmpty());
        QVERIFY(!settings.saving());
    }

    void aChangeDuringASaveIsSavedAfterIt()
    {
        PowerSettings settings;
        useRecorder(settings, 0, QStringLiteral("0.5"));
        QSignalSpy saved(&settings, &PowerSettings::saved);
        settings.setSleepAfterMinutes(60);
        settings.save();
        settings.setSleepAfterMinutes(120);
        settings.save();
        settings.setScreenOffAfterMinutes(30);
        settings.save();
        QTRY_COMPARE_WITH_TIMEOUT(saved.size(), 2, 5000);
        QCOMPARE(runs(), (QStringList { QStringLiteral("60 10"), QStringLiteral("120 30") }));
    }

    void choices()
    {
        PowerSettings settings;
        const QVariantList sleep = settings.sleepChoices();
        QCOMPARE(sleep.size(), 6);
        QCOMPARE(sleep.first().toMap().value(QStringLiteral("minutes")).toInt(), 5);
        QCOMPARE(sleep.first().toMap().value(QStringLiteral("text")).toString(), QStringLiteral("5 minutes"));
        QCOMPARE(sleep.last().toMap().value(QStringLiteral("text")).toString(), QStringLiteral("2 hours"));
        const QVariantList screen = settings.screenOffChoices();
        QCOMPARE(screen.first().toMap().value(QStringLiteral("text")).toString(), QStringLiteral("1 minute"));
        QCOMPARE(screen.last().toMap().value(QStringLiteral("minutes")).toInt(), 0);
        QCOMPARE(screen.last().toMap().value(QStringLiteral("text")).toString(), QStringLiteral("Never"));
        // The defaults are among the choices, so the lists can show them.
        const auto hasMinutes = [](const QVariantList &list, int minutes) {
            return std::any_of(
                list.cbegin(), list.cend(), [minutes](const QVariant &item) { return item.toMap().value(QStringLiteral("minutes")).toInt() == minutes; });
        };
        QVERIFY(hasMinutes(sleep, PowerSettings::defaultSleepAfterMinutes));
        QVERIFY(hasMinutes(screen, PowerSettings::defaultScreenOffAfterMinutes));
    }
};

QTEST_GUILESS_MAIN(PowerSettingsTest)

#include "powersettingstest.moc"
