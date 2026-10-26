// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "storeapps.h"

#include <QSet>
#include <QSignalSpy>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

const QString solaar = QStringLiteral("io.github.pwr_solaar.solaar");
const QString piper = QStringLiteral("org.freedesktop.Piper");
const QString openrgb = QStringLiteral("org.openrgb.OpenRGB");

// A page whose installed apps are the ones in the set, recording what it starts and opens.
struct Page
{
    explicit Page(QSet<QString> initiallyInstalled = { })
        : installed(std::move(initiallyInstalled))
    {
        apps = std::make_unique<StoreApps>(StoreApps::Environment {
            [this](const QString &id) { return installed.contains(id); },
            [this](const QString &id) { launched.append(id); },
            [this](const QString &url) { opened.append(url); },
        });
    }

    QSet<QString> installed;
    QStringList launched;
    QStringList opened;
    std::unique_ptr<StoreApps> apps;
};

QVariantMap entry(const StoreApps &apps, int index)
{
    return apps.apps().at(index).toMap();
}

} // namespace

class StoreAppsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void listsTheThreeApps()
    {
        Page page;
        const QVariantList apps = page.apps->apps();
        QCOMPARE(apps.size(), 3);
        QCOMPARE(entry(*page.apps, 0).value(QStringLiteral("id")).toString(), solaar);
        QCOMPARE(entry(*page.apps, 1).value(QStringLiteral("name")).toString(), QStringLiteral("Piper"));
        QCOMPARE(entry(*page.apps, 2).value(QStringLiteral("id")).toString(), openrgb);
        for (const QVariant &app : apps) {
            QVERIFY(!app.toMap().value(QStringLiteral("description")).toString().isEmpty());
            QVERIFY(!app.toMap().value(QStringLiteral("installed")).toBool());
        }
        // Not installed: the icon comes with Flathub's catalogue.
        QCOMPARE(entry(*page.apps, 1).value(QStringLiteral("icon")).toString(),
            QStringLiteral("file:///var/lib/flatpak/appstream/flathub/x86_64/active/icons/128x128/org.freedesktop.Piper.png"));
    }

    void showsInstalledApps()
    {
        Page page({ solaar });
        QVERIFY(entry(*page.apps, 0).value(QStringLiteral("installed")).toBool());
        QCOMPARE(entry(*page.apps, 0).value(QStringLiteral("icon")).toString(), solaar);
        QVERIFY(!entry(*page.apps, 1).value(QStringLiteral("installed")).toBool());
    }

    void opensAnInstalledAppAndTheStoreForTheOthers()
    {
        Page page({ solaar });
        page.apps->open(solaar);
        page.apps->open(piper);
        QCOMPARE(page.launched, QStringList { solaar });
        QCOMPARE(page.opened, QStringList { QStringLiteral("appstream://org.freedesktop.Piper") });
    }

    void opensNothingElse()
    {
        Page page;
        page.apps->open(QStringLiteral("org.example.Other"));
        QVERIFY(page.launched.isEmpty());
        QVERIFY(page.opened.isEmpty());
    }

    void notices()
    {
        Page page;
        QSignalSpy changed(page.apps.get(), &StoreApps::changed);
        page.apps->refresh();
        QCOMPARE(changed.size(), 0);
        page.installed.insert(openrgb);
        page.apps->refresh();
        QCOMPARE(changed.size(), 1);
        QVERIFY(entry(*page.apps, 2).value(QStringLiteral("installed")).toBool());
        // Installed between the refresh and the click, it opens rather than going to the Store.
        page.installed.insert(piper);
        page.apps->open(piper);
        QCOMPARE(page.launched, QStringList { piper });
    }
};

QTEST_GUILESS_MAIN(StoreAppsTest)

#include "storeappstest.moc"
