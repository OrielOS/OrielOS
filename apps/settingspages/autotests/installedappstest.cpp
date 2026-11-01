// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "installedapps.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QTimeZone>

using namespace OrielOSSettingsPages;

class InstalledAppsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesFlatpaksList()
    {
        const QList<InstalledApp> apps = InstalledApp::parseList(QStringLiteral(
            "org.mozilla.firefox\tFirefox\t133.0\t250.1 MB\tsystem\n"
            "com.valvesoftware.Steam\tSteam\t1.0.0.81\t12.0 MB\tuser\n"
            "broken line\n"
            "\t\t\t\t\n"
            "org.example.NoName\t\t1.0\t1 MB\tsystem\n"));
        QCOMPARE(apps.size(), 3);
        QCOMPARE(apps.at(0).id, QStringLiteral("org.mozilla.firefox"));
        QCOMPARE(apps.at(0).name, QStringLiteral("Firefox"));
        QCOMPARE(apps.at(0).version, QStringLiteral("133.0"));
        QCOMPARE(apps.at(0).size, QStringLiteral("250.1 MB"));
        QCOMPARE(apps.at(1).installation, QStringLiteral("user"));
        // An app without a name shows its ID.
        QCOMPARE(apps.at(2).name, QStringLiteral("org.example.NoName"));
    }

    void listsAndKeepsTheSource()
    {
        QTemporaryDir dir;
        InstalledApps::Environment environment;
        environment.listApps = [](const QStringList &) {
            return QStringLiteral("org.b.Zed\tZed\t1\t1 MB\tsystem\norg.a.Alpha\talpha\t2\t2 MB\tuser\n");
        };
        environment.installedOn = [](const QString &, const QString &) { return QDateTime(QDate(2026, 11, 1), QTime(9, 0), QTimeZone::UTC); };
        environment.configPath = dir.filePath(QStringLiteral("config/orielos-appsrc"));
        environment.flatpakProgram = QStringLiteral("/nonexistent");
        InstalledApps installed(environment, nullptr);

        // Sorted by name, whatever the case.
        QCOMPARE(installed.apps().size(), 2);
        QCOMPARE(installed.apps().at(0).toMap().value(QStringLiteral("name")).toString(), QStringLiteral("alpha"));
        QVERIFY(!installed.apps().at(0).toMap().value(QStringLiteral("installedOn")).toString().isEmpty());

        QCOMPARE(installed.appSource(), 0);
        installed.setAppSource(2);
        QCOMPARE(installed.appSource(), 2);
        QFile config(environment.configPath);
        QVERIFY(config.open(QIODevice::ReadOnly));
        QVERIFY(config.readAll().contains("source=store"));
        installed.setAppSource(7);
        QCOMPARE(installed.appSource(), 2);
    }
};

QTEST_GUILESS_MAIN(InstalledAppsTest)

#include "installedappstest.moc"
