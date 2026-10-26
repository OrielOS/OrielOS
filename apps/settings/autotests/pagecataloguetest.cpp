// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pagecatalogue.h"

#include <QSet>
#include <QTest>

using namespace OrielOSSettings;

namespace {

QStringList ids(const QList<Page> &pages)
{
    QStringList out;
    for (const Page &page : pages) {
        out.append(page.id);
    }
    return out;
}

} // namespace

class PageCatalogueTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void categoriesComeInWindowsOrder()
    {
        QStringList categories;
        for (const Category &category : PageCatalogue::standard().categories()) {
            categories.append(category.id);
        }
        QCOMPARE(categories,
            (QStringList { QStringLiteral("system"), QStringLiteral("devices"), QStringLiteral("network"), QStringLiteral("personalisation"),
                QStringLiteral("apps"), QStringLiteral("accounts"), QStringLiteral("time"), QStringLiteral("update") }));
    }

    void everyPageIsUniqueAndInACategory()
    {
        const PageCatalogue catalogue = PageCatalogue::standard();
        QSet<QString> pageIds;
        QSet<QString> modules;
        for (const Category &category : catalogue.categories()) {
            const QList<Page> pages = catalogue.pages(category.id);
            QVERIFY2(!pages.isEmpty(), qPrintable(category.id));
            for (const Page &page : pages) {
                QVERIFY2(!pageIds.contains(page.id), qPrintable(page.id));
                QVERIFY2(!modules.contains(page.module), qPrintable(page.module));
                QVERIFY(!page.title.isEmpty());
                QVERIFY(!page.description.isEmpty());
                QVERIFY(page.module.startsWith(QLatin1String("kcm_")));
                pageIds.insert(page.id);
                modules.insert(page.module);
            }
        }
        // The Update page is OrielOS's own module.
        QCOMPARE(catalogue.page(QStringLiteral("update"))->module, QStringLiteral("kcm_orielos_update"));
    }

    void findsAPageByIdOrModule()
    {
        const PageCatalogue catalogue = PageCatalogue::standard();
        QCOMPARE(catalogue.page(QStringLiteral("display"))->module, QStringLiteral("kcm_kscreen"));
        QCOMPARE(catalogue.page(QStringLiteral("kcm_kscreen"))->id, QStringLiteral("display"));
        QVERIFY(!catalogue.page(QStringLiteral("kcm_colors")));
        QVERIFY(!catalogue.page(QString()));
    }

    void leavesOutPagesWhoseModuleIsMissing()
    {
        const PageCatalogue catalogue = PageCatalogue::standard().available([](const QString &module) {
            return module != QLatin1String("kcm_networkmanagement") && module != QLatin1String("kcm_proxy") && module != QLatin1String("kcm_touchpad");
        });
        QVERIFY(!catalogue.page(QStringLiteral("touchpad")));
        QVERIFY(catalogue.page(QStringLiteral("mouse")));
        // A category left with no pages goes too.
        QVERIFY(!catalogue.category(QStringLiteral("network")));
        QVERIFY(catalogue.category(QStringLiteral("devices")));
        QVERIFY(catalogue.search(QStringLiteral("wifi")).isEmpty());
    }

    void searchFindsWindowsTerms_data()
    {
        QTest::addColumn<QString>("query");
        QTest::addColumn<QString>("first");

        QTest::newRow("display") << QStringLiteral("display") << QStringLiteral("display");
        QTest::newRow("the start of a word") << QStringLiteral("disp") << QStringLiteral("display");
        QTest::newRow("upper case") << QStringLiteral("DISPLAY") << QStringLiteral("display");
        QTest::newRow("resolution") << QStringLiteral("resolution") << QStringLiteral("display");
        QTest::newRow("wifi") << QStringLiteral("wifi") << QStringLiteral("network");
        QTest::newRow("wi-fi") << QStringLiteral("wi-fi") << QStringLiteral("network");
        QTest::newRow("default apps") << QStringLiteral("default apps") << QStringLiteral("default-apps");
        QTest::newRow("default browser") << QStringLiteral("default browser") << QStringLiteral("default-apps");
        QTest::newRow("volume") << QStringLiteral("volume") << QStringLiteral("sound");
        QTest::newRow("dark mode") << QStringLiteral("dark mode") << QStringLiteral("themes");
        QTest::newRow("wallpaper") << QStringLiteral("wallpaper") << QStringLiteral("background");
        QTest::newRow("time zone") << QStringLiteral("time zone") << QStringLiteral("date-time");
        QTest::newRow("windows update") << QStringLiteral("windows update") << QStringLiteral("update");
        QTest::newRow("password") << QStringLiteral("password") << QStringLiteral("your-info");
        QTest::newRow("sleep") << QStringLiteral("sleep") << QStringLiteral("power");
        QTest::newRow("specs") << QStringLiteral("specs") << QStringLiteral("about");
    }

    void searchFindsWindowsTerms()
    {
        QFETCH(QString, query);
        QFETCH(QString, first);
        const QList<Page> results = PageCatalogue::standard().search(query);
        QVERIFY2(!results.isEmpty(), qPrintable(query));
        QCOMPARE(results.first().id, first);
    }

    void searchRanksTitlesFirst()
    {
        // Keyboard is the page's name; Language & region only lists "keyboard layout" among its words.
        const QStringList results = ids(PageCatalogue::standard().search(QStringLiteral("keyboard")));
        QCOMPARE(results.first(), QStringLiteral("keyboard"));
        QVERIFY(results.contains(QStringLiteral("language-region")));
        QVERIFY(results.indexOf(QStringLiteral("keyboard")) < results.indexOf(QStringLiteral("language-region")));
    }

    void searchNeedsEveryWord()
    {
        const PageCatalogue catalogue = PageCatalogue::standard();
        QVERIFY(catalogue.search(QStringLiteral("display wifi")).isEmpty());
        QVERIFY(catalogue.search(QStringLiteral("zzz")).isEmpty());
        QVERIFY(catalogue.search(QString()).isEmpty());
        QVERIFY(catalogue.search(QStringLiteral("  - ")).isEmpty());
    }

    void searchIgnoresAccents()
    {
        const PageCatalogue catalogue({ { QStringLiteral("system"), QStringLiteral("Système"), QString() } },
            { { QStringLiteral("display"), QStringLiteral("system"), QStringLiteral("Écran"), QStringLiteral("Résolution"), { }, QStringLiteral("kcm_kscreen"),
                QString() } });
        QCOMPARE(ids(catalogue.search(QStringLiteral("ecran"))), QStringList { QStringLiteral("display") });
        QCOMPARE(ids(catalogue.search(QStringLiteral("resolution"))), QStringList { QStringLiteral("display") });
        QCOMPARE(ids(catalogue.search(QStringLiteral("systeme"))), QStringList { QStringLiteral("display") });
    }
};

QTEST_GUILESS_MAIN(PageCatalogueTest)

#include "pagecataloguetest.moc"
