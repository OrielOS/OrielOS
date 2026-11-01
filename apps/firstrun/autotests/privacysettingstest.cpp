// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "privacysettings.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class PrivacySettingsTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    // A stand-in for pkexec first-run-privacy that appends its arguments to a record and exits
    // with exitCode.
    QString setUp(PrivacySettings &privacy, int exitCode = 0)
    {
        const QString record = m_dir.filePath(QStringLiteral("calls-%1").arg(QLatin1String(QTest::currentTestFunction())));
        privacy.setCommandForTesting(QStringLiteral("sh"),
            { QStringLiteral("-c"), QStringLiteral("echo \"$@\" >> %1; exit %2").arg(record).arg(exitCode), QStringLiteral("helper") });
        return record;
    }

    static QStringList read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed().split(QLatin1Char('\n'), Qt::SkipEmptyParts) : QStringList();
    }

private Q_SLOTS:
    void locationStartsOnAndSavesNothing()
    {
        PrivacySettings privacy;
        const QString record = setUp(privacy);
        QVERIFY(privacy.location());
        privacy.save();
        QVERIFY(!privacy.saving());
        QVERIFY(read(record).isEmpty());
    }

    void savesAChange()
    {
        PrivacySettings privacy;
        const QString record = setUp(privacy);
        QSignalSpy saved(&privacy, &PrivacySettings::saved);
        privacy.setLocation(false);
        privacy.save();
        QVERIFY(saved.wait());
        QCOMPARE(saved.at(0).at(0).toBool(), true);
        QCOMPARE(read(record), QStringList { QStringLiteral("location off") });

        // Saving again with nothing changed does nothing; turning it back on saves that.
        privacy.save();
        QVERIFY(!privacy.saving());
        privacy.setLocation(true);
        privacy.save();
        QVERIFY(saved.wait());
        QCOMPARE(read(record), (QStringList { QStringLiteral("location off"), QStringLiteral("location on") }));
    }

    void reportsAFailure()
    {
        PrivacySettings privacy;
        setUp(privacy, 1);
        QSignalSpy saved(&privacy, &PrivacySettings::saved);
        privacy.setLocation(false);
        privacy.save();
        QVERIFY(saved.wait());
        QCOMPARE(saved.at(0).at(0).toBool(), false);
        QVERIFY(!privacy.error().isEmpty());
    }
};

QTEST_GUILESS_MAIN(PrivacySettingsTest)

#include "privacysettingstest.moc"
