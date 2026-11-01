// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "storageusage.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <unistd.h>

using OrielOSSettingsPages::StorageUsage;

class StorageUsageTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    static bool write(const QString &path, qsizetype bytes)
    {
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly)) {
            return false;
        }
        file.write(QByteArray(bytes, 'x'));
        return true;
    }

    static QString read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QString();
    }

    // Waits for the background measuring to finish.
    static bool measured(StorageUsage &storage)
    {
        return QTest::qWaitFor([&storage]() { return !storage.isCalculating(); });
    }

private Q_SLOTS:
    void hardLinksCountOnce()
    {
        const QString folder = m_dir.filePath(QStringLiteral("links"));
        QVERIFY(QDir().mkpath(folder));
        const QString file = folder + QStringLiteral("/one");
        QVERIFY(write(file, 64 * 1024));
        const qint64 alone = StorageUsage::diskUsage(folder);
        QVERIFY(alone >= 64 * 1024);
        QCOMPARE(link(QFile::encodeName(file).constData(), QFile::encodeName(folder + QStringLiteral("/two")).constData()), 0);
        QCOMPARE(StorageUsage::diskUsage(folder), alone);
    }

    void measuresEachPart()
    {
        const QString documents = m_dir.filePath(QStringLiteral("Documents"));
        const QString pictures = m_dir.filePath(QStringLiteral("Pictures"));
        QVERIFY(QDir().mkpath(documents));
        QVERIFY(QDir().mkpath(pictures + QStringLiteral("/holiday")));
        QVERIFY(write(documents + QStringLiteral("/letter"), 16 * 1024));
        QVERIFY(write(pictures + QStringLiteral("/holiday/beach"), 256 * 1024));

        StorageUsage storage;
        QVERIFY(measured(storage));
        storage.setForTesting({ { QStringLiteral("documents"), { documents } }, { QStringLiteral("pictures"), { pictures } } },
            m_dir.filePath(QStringLiteral("sense-measures")), { });
        storage.refresh();
        QVERIFY(storage.isCalculating());
        QVERIFY(measured(storage));

        const QVariantList parts = storage.categories();
        QCOMPARE(parts.size(), 3);
        // Largest first, then System and other.
        QCOMPARE(parts.at(0).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("pictures"));
        QCOMPARE(parts.at(0).toMap().value(QStringLiteral("bytes")).toLongLong(), StorageUsage::diskUsage(pictures));
        QCOMPARE(parts.at(1).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("documents"));
        QCOMPARE(parts.at(2).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("other"));
        QVERIFY(storage.total() > 0);
        QVERIFY(storage.used() > 0);
    }

    void keepsStorageSensesSettings()
    {
        const QString config = m_dir.filePath(QStringLiteral("sense-settings"));
        StorageUsage storage;
        QVERIFY(measured(storage));
        storage.setForTesting({ { QStringLiteral("documents"), { m_dir.path() } } }, config, { });
        QVERIFY(!storage.isSenseEnabled());
        QCOMPARE(storage.binDays(), 30);

        QSignalSpy changed(&storage, &StorageUsage::senseChanged);
        storage.setSenseEnabled(true);
        storage.setBinDays(14);
        QCOMPARE(changed.count(), 2);
        QVERIFY(storage.isSenseEnabled());
        QCOMPARE(storage.binDays(), 14);
        const QString contents = read(config);
        QVERIFY2(contents.contains(QLatin1String("[StorageSense]")), qPrintable(contents));
        QVERIFY2(contents.contains(QLatin1String("Enabled=true")), qPrintable(contents));
        QVERIFY2(contents.contains(QLatin1String("BinDays=14")), qPrintable(contents));

        // A negative age is refused.
        storage.setBinDays(-1);
        QCOMPARE(storage.binDays(), 14);
    }

    void runsStorageSense_data()
    {
        QTest::addColumn<bool>("everything");
        QTest::addColumn<int>("exitCode");
        QTest::addColumn<QString>("arguments");
        QTest::newRow("run now") << false << 0 << QStringLiteral("--now --config");
        QTest::newRow("clean up now") << true << 0 << QStringLiteral("--now --all --config");
        QTest::newRow("files in use") << true << 1 << QStringLiteral("--now --all --config");
    }

    void runsStorageSense()
    {
        QFETCH(bool, everything);
        QFETCH(int, exitCode);
        QFETCH(QString, arguments);
        const QString config = m_dir.filePath(QStringLiteral("sense-run"));
        const QString record
            = m_dir.filePath(QStringLiteral("args-%1").arg(QString::fromLatin1(QTest::currentDataTag()).replace(QLatin1Char(' '), QLatin1Char('-'))));
        const QString program = m_dir.filePath(QStringLiteral("sense-%1.sh").arg(exitCode));
        QFile script(program);
        QVERIFY(script.open(QIODevice::WriteOnly));
        script.write(QStringLiteral("#!/bin/sh\necho \"$@\" > \"$RECORD\"\nexit %1\n").arg(exitCode).toUtf8());
        script.close();
        QVERIFY(script.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        qputenv("RECORD", record.toUtf8());

        StorageUsage storage;
        QVERIFY(measured(storage));
        storage.setForTesting({ { QStringLiteral("documents"), { m_dir.path() } } }, config, program);
        QSignalSpy cleaned(&storage, &StorageUsage::cleaned);
        storage.cleanUp(everything);
        QVERIFY(storage.isCleaning());
        QVERIFY(cleaned.wait());
        QCOMPARE(cleaned.at(0).at(0).toBool(), exitCode == 0);
        QCOMPARE(read(record), arguments + QLatin1Char(' ') + config);
        QCOMPARE(storage.error().isEmpty(), exitCode == 0);
        QVERIFY(measured(storage));
    }
};

QTEST_GUILESS_MAIN(StorageUsageTest)

#include "storageusagetest.moc"
