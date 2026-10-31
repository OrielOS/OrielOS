// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "multitaskingoptions.h"

#include <KConfigGroup>

#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using OrielOSSettingsPages::MultitaskingOptions;

class MultitaskingOptionsTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    KSharedConfig::Ptr m_config;
    int m_reconfigures = 0;

    void useFreshConfig(MultitaskingOptions &options, const QString &contents = { })
    {
        const QString path = m_dir.filePath(QStringLiteral("kwinrc-%1").arg(QTest::currentTestFunction()));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents.toUtf8());
        file.close();
        m_config = KSharedConfig::openConfig(path, KConfig::SimpleConfig);
        m_reconfigures = 0;
        options.setConfigForTesting(m_config, [this]() { ++m_reconfigures; });
    }

    QString entry(const QString &group, const QString &key)
    {
        const KConfig written(m_config->name(), KConfig::SimpleConfig);
        return KConfigGroup(&written, group).readEntry(key, QString());
    }

private Q_SLOTS:
    void defaultsAreWindows()
    {
        MultitaskingOptions options;
        useFreshConfig(options, QStringLiteral("[TabBox]\nDesktopMode=1\n"));
        QVERIFY(options.snapWindows());
        QVERIFY(options.snapLayoutsOnMaximise());
        QVERIFY(options.suggestNextSnap());
        QVERIFY(!options.altTabAllDesktops());
    }

    void writesEachSwitch()
    {
        MultitaskingOptions options;
        useFreshConfig(options);
        QSignalSpy changed(&options, &MultitaskingOptions::changed);

        options.setSnapWindows(false);
        QCOMPARE(entry(QStringLiteral("Windows"), QStringLiteral("ElectricBorderMaximize")), QStringLiteral("false"));
        QCOMPARE(entry(QStringLiteral("Windows"), QStringLiteral("ElectricBorderTiling")), QStringLiteral("false"));
        QVERIFY(!options.snapWindows());

        options.setSnapLayoutsOnMaximise(false);
        QCOMPARE(entry(QStringLiteral("org.kde.kdecoration2"), QStringLiteral("SnapLayoutsOnHover")), QStringLiteral("false"));

        options.setSuggestNextSnap(false);
        QCOMPARE(entry(QStringLiteral("Plugins"), QStringLiteral("orielos-snapassistEnabled")), QStringLiteral("false"));

        options.setAltTabAllDesktops(true);
        QCOMPARE(entry(QStringLiteral("TabBox"), QStringLiteral("DesktopMode")), QStringLiteral("0"));
        QVERIFY(options.altTabAllDesktops());

        QCOMPARE(m_reconfigures, 4);
        QVERIFY(changed.count() >= 4);
    }

    void unchangedWritesNothing()
    {
        MultitaskingOptions options;
        useFreshConfig(options);
        options.setSnapWindows(true);
        options.setSuggestNextSnap(true);
        options.setAltTabAllDesktops(false);
        QCOMPARE(m_reconfigures, 0);
        QVERIFY(entry(QStringLiteral("Windows"), QStringLiteral("ElectricBorderMaximize")).isEmpty());
    }

    void readsSnappingOffWhenEitherIsOff()
    {
        MultitaskingOptions options;
        useFreshConfig(options, QStringLiteral("[Windows]\nElectricBorderTiling=false\n"));
        QVERIFY(!options.snapWindows());
        options.setSnapWindows(true);
        QCOMPARE(entry(QStringLiteral("Windows"), QStringLiteral("ElectricBorderTiling")), QStringLiteral("true"));
    }
};

QTEST_GUILESS_MAIN(MultitaskingOptionsTest)

#include "multitaskingoptionstest.moc"
