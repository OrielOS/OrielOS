// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "settingssearch.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QTest>

using namespace OrielOSSettings;

namespace {

// Two categories with a page each, as Settings would have them.
PageCatalogue settings()
{
    return PageCatalogue(
        {
            { QStringLiteral("system"), QStringLiteral("System"), { } },
            { QStringLiteral("personalisation"), QStringLiteral("Personalisation"), { } },
        },
        {
            { QStringLiteral("display"), QStringLiteral("system"), QStringLiteral("Display"), QStringLiteral("Screens, resolution and scale"),
                { QStringLiteral("monitor"), QStringLiteral("resolution") }, QStringLiteral("kcm_kscreen"), QStringLiteral("preferences-desktop-display") },
            { QStringLiteral("themes"), QStringLiteral("personalisation"), QStringLiteral("Themes"), QStringLiteral("Light and dark mode"),
                { QStringLiteral("dark mode"), QStringLiteral("colours") }, QStringLiteral("kcm_lookandfeel"), QStringLiteral("preferences-desktop-theme") },
        });
}

KPluginMetaData module(const QString &id, const QString &name, const QString &keywords)
{
    const QJsonObject json = QJsonDocument::fromJson(QStringLiteral(R"({
        "KPlugin": { "Id": "%1", "Name": "%2", "Description": "About %2", "Icon": "icon-%1" },
        "X-KDE-Keywords": "%3",
        "X-KDE-System-Settings-Parent-Category": "appearance"
    })")
                                                         .arg(id, name, keywords)
                                                         .toUtf8())
                                 .object();
    return KPluginMetaData(json, id + QStringLiteral(".so"));
}

QStringList ids(const QList<SettingsResult> &results)
{
    QStringList out;
    for (const SettingsResult &result : results) {
        out.append(result.id);
    }
    return out;
}

} // namespace

class SettingsSearchTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void leavesOutModulesSettingsHas()
    {
        const QList<Page> others = SettingsSearch::otherModules(settings(),
            { module(QStringLiteral("kcm_kscreen"), QStringLiteral("Display Configuration"), QStringLiteral("monitor")),
                module(QStringLiteral("kcm_fonts"), QStringLiteral("Fonts"), QStringLiteral("font size, anti-aliasing,hinting")) });
        QCOMPARE(others.size(), 1);
        const Page &fonts = others.first();
        QCOMPARE(fonts.id, QStringLiteral("kcm_fonts"));
        QCOMPARE(fonts.module, QStringLiteral("kcm_fonts"));
        QCOMPARE(fonts.title, QStringLiteral("Fonts"));
        QCOMPARE(fonts.description, QStringLiteral("About Fonts"));
        QCOMPARE(fonts.icon, QStringLiteral("icon-kcm_fonts"));
        QVERIFY(fonts.category.isEmpty());
        // Comma-separated in the module's metadata, trimmed.
        QCOMPARE(fonts.keywords, (QStringList { QStringLiteral("font size"), QStringLiteral("anti-aliasing"), QStringLiteral("hinting") }));
    }

    void opensSettingsPagesInSettings()
    {
        const SettingsSearch search(settings(), { });
        const QList<SettingsResult> results = search.search(QStringLiteral("disp"));
        QCOMPARE(ids(results), QStringList { QStringLiteral("display") });
        const SettingsResult &display = results.first();
        QCOMPARE(display.title, QStringLiteral("Display"));
        QCOMPARE(display.subtext, QStringLiteral("Settings › System"));
        QCOMPARE(display.icon, QStringLiteral("preferences-desktop-display"));
        QCOMPARE(display.command, (QStringList { QStringLiteral("orielos-settings"), QStringLiteral("display") }));
        QCOMPARE(display.rank, 0);
        QVERIFY(display.inSettings);
    }

    void opensOtherModulesInSystemSettings()
    {
        const SettingsSearch search(
            settings(), SettingsSearch::otherModules(settings(), { module(QStringLiteral("kcm_fonts"), QStringLiteral("Fonts"), QStringLiteral("hinting")) }));
        const QList<SettingsResult> results = search.search(QStringLiteral("hinting"));
        QCOMPARE(ids(results), QStringList { QStringLiteral("kcm_fonts") });
        const SettingsResult &fonts = results.first();
        QCOMPARE(fonts.title, QStringLiteral("Fonts"));
        QCOMPARE(fonts.subtext, QStringLiteral("System Settings"));
        QCOMPARE(fonts.command, (QStringList { QStringLiteral("systemsettings"), QStringLiteral("kcm_fonts") }));
        // Found by a keyword.
        QCOMPARE(fonts.rank, 2);
        QVERIFY(!fonts.inSettings);
    }

    void listsSettingsFirst()
    {
        // "Colours" is a keyword of Themes, and the name of a module only System Settings has.
        const SettingsSearch search(settings(),
            SettingsSearch::otherModules(settings(), { module(QStringLiteral("kcm_colors"), QStringLiteral("Colours"), QStringLiteral("colour scheme")) }));
        const QList<SettingsResult> results = search.search(QStringLiteral("colours"));
        QCOMPARE(ids(results), (QStringList { QStringLiteral("themes"), QStringLiteral("kcm_colors") }));
        QCOMPARE(results.at(0).rank, 2);
        QCOMPARE(results.at(1).rank, 0);
    }

    void findsNothingForNothing()
    {
        const SettingsSearch search(settings(), { });
        QVERIFY(search.search(QString()).isEmpty());
        QVERIFY(search.search(QStringLiteral("  ")).isEmpty());
        QVERIFY(search.search(QStringLiteral("bluetooth")).isEmpty());
    }

    void ranksLikeTheCatalogue()
    {
        const PageCatalogue catalogue = settings();
        const Page display = *catalogue.page(QStringLiteral("display"));
        QCOMPARE(catalogue.rank(display, QStringLiteral("Display")), 0);
        QCOMPARE(catalogue.rank(display, QStringLiteral("resolution")), 2);
        QCOMPARE(catalogue.rank(display, QStringLiteral("system")), 3);
        QCOMPARE(catalogue.rank(display, QStringLiteral("scale")), 3);
        QCOMPARE(catalogue.rank(display, QStringLiteral("sound")), -1);
        QCOMPARE(catalogue.rank(display, QString()), -1);
    }
};

QTEST_GUILESS_MAIN(SettingsSearchTest)

#include "settingssearchtest.moc"
