// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "powermode.h"

#include <QSignalSpy>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

// A power profiles daemon that answers when the test says so, and records what it's asked to set.
class FakeDaemon : public PowerProfilesBackend
{
    Q_OBJECT

public:
    int reads = 0;
    QStringList sets;

    void read() override { ++reads; }
    void setActive(const QString &profile) override { sets.append(profile); }

    void answer(const QString &active,
        const QStringList &profiles = { QStringLiteral("power-saver"), QStringLiteral("balanced"), QStringLiteral("performance") },
        const QString &degraded = { })
    {
        PowerProfilesState state;
        state.available = true;
        state.active = active;
        state.profiles = profiles;
        state.degraded = degraded;
        Q_EMIT stateRead(state);
    }
};

QStringList ids(const PowerMode &power)
{
    QStringList out;
    for (const QVariant &mode : power.modes()) {
        out.append(mode.toMap().value(QStringLiteral("id")).toString());
    }
    return out;
}

} // namespace

class PowerModeTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void readsTheDaemonsProperties()
    {
        // As tuned-ppd reports them over D-Bus, with Profiles already unmarshalled.
        const PowerProfilesState state = PowerProfilesState::fromProperties({
            { QStringLiteral("ActiveProfile"), QStringLiteral("performance") },
            { QStringLiteral("PerformanceDegraded"), QString() },
            { QStringLiteral("Profiles"),
                QVariantList {
                    QVariantMap { { QStringLiteral("Profile"), QStringLiteral("power-saver") }, { QStringLiteral("Driver"), QStringLiteral("tuned") } },
                    QVariantMap { { QStringLiteral("Profile"), QStringLiteral("balanced") }, { QStringLiteral("Driver"), QStringLiteral("tuned") } },
                    QVariantMap { { QStringLiteral("Profile"), QStringLiteral("performance") }, { QStringLiteral("Driver"), QStringLiteral("tuned") } },
                } },
        });
        QVERIFY(state.available);
        QCOMPARE(state.active, QStringLiteral("performance"));
        QCOMPARE(state.profiles, (QStringList { QStringLiteral("power-saver"), QStringLiteral("balanced"), QStringLiteral("performance") }));
        QVERIFY(state.degraded.isEmpty());
    }

    void listsPerformanceFirst()
    {
        auto *daemon = new FakeDaemon;
        PowerMode power(daemon);
        QCOMPARE(daemon->reads, 1);
        QVERIFY(!power.isReady());
        daemon->answer(QStringLiteral("performance"));
        QVERIFY(power.isReady());
        QVERIFY(power.isAvailable());
        QCOMPARE(ids(power), (QStringList { QStringLiteral("performance"), QStringLiteral("balanced"), QStringLiteral("power-saver") }));
        QCOMPARE(power.modes().first().toMap().value(QStringLiteral("name")).toString(), QStringLiteral("Performance"));
        QCOMPARE(power.active(), QStringLiteral("performance"));

        // A daemon without Performance, as on some computers, doesn't offer it.
        daemon->answer(QStringLiteral("balanced"), { QStringLiteral("power-saver"), QStringLiteral("balanced") });
        QCOMPARE(ids(power), (QStringList { QStringLiteral("balanced"), QStringLiteral("power-saver") }));
    }

    void setsAMode()
    {
        auto *daemon = new FakeDaemon;
        PowerMode power(daemon);
        daemon->answer(QStringLiteral("performance"));
        QSignalSpy changed(&power, &PowerMode::changed);

        power.setActive(QStringLiteral("balanced"));
        QCOMPARE(daemon->sets, QStringList { QStringLiteral("balanced") });
        // Shown while the daemon switches.
        QCOMPARE(power.active(), QStringLiteral("balanced"));
        // Nothing else is asked for meanwhile.
        power.setActive(QStringLiteral("power-saver"));
        QCOMPARE(daemon->sets.size(), 1);

        Q_EMIT daemon->setFinished(true);
        // It reads the daemon again, which reports the new mode.
        QCOMPARE(daemon->reads, 2);
        daemon->answer(QStringLiteral("balanced"));
        QCOMPARE(power.active(), QStringLiteral("balanced"));
        QVERIFY(power.error().isEmpty());
        QVERIFY(changed.size() >= 3);
    }

    void goesBackWhenRefused()
    {
        auto *daemon = new FakeDaemon;
        PowerMode power(daemon);
        daemon->answer(QStringLiteral("performance"));
        power.setActive(QStringLiteral("power-saver"));
        Q_EMIT daemon->setFinished(false);
        QCOMPARE(power.active(), QStringLiteral("performance"));
        QCOMPARE(power.error(), QStringLiteral("The power mode couldn't be changed."));
    }

    void ignoresWhatItCantSet()
    {
        auto *daemon = new FakeDaemon;
        PowerMode power(daemon);
        // Before the first answer.
        power.setActive(QStringLiteral("balanced"));
        daemon->answer(QStringLiteral("performance"), { QStringLiteral("balanced"), QStringLiteral("performance") });
        // The mode it already has, and one the daemon doesn't offer.
        power.setActive(QStringLiteral("performance"));
        power.setActive(QStringLiteral("power-saver"));
        power.setActive(QStringLiteral("turbo"));
        QVERIFY(daemon->sets.isEmpty());
    }

    void saysWhenTheDaemonIsMissing()
    {
        auto *daemon = new FakeDaemon;
        PowerMode power(daemon);
        Q_EMIT daemon->stateRead({ });
        QVERIFY(power.isReady());
        QVERIFY(!power.isAvailable());
        QVERIFY(power.modes().isEmpty());
        power.setActive(QStringLiteral("balanced"));
        QVERIFY(daemon->sets.isEmpty());
    }

    void explainsHeldBackPerformance()
    {
        auto *daemon = new FakeDaemon;
        PowerMode power(daemon);
        daemon->answer(
            QStringLiteral("performance"), { QStringLiteral("balanced"), QStringLiteral("performance") }, QStringLiteral("high-operating-temperature"));
        QCOMPARE(power.degraded(), QStringLiteral("Performance is held back because the computer is too hot."));
        daemon->answer(QStringLiteral("performance"), { QStringLiteral("balanced"), QStringLiteral("performance") }, QStringLiteral("lap-detected"));
        QVERIFY(power.degraded().contains(QLatin1String("lap")));
        daemon->answer(QStringLiteral("performance"), { QStringLiteral("balanced"), QStringLiteral("performance") }, QStringLiteral("something-new"));
        QVERIFY(power.degraded().contains(QLatin1String("something-new")));
        daemon->answer(QStringLiteral("performance"));
        QVERIFY(power.degraded().isEmpty());
    }
};

QTEST_GUILESS_MAIN(PowerModeTest)

#include "powermodetest.moc"
