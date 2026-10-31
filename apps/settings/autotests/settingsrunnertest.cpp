// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Loads the built runner as Start and KRunner do, and searches with it.

#include <KPluginMetaData>
#include <KRunner/AbstractRunnerTest>

#include <QTest>

using namespace KRunner;

class SettingsRunnerTest : public AbstractRunnerTest
{
    Q_OBJECT

private:
    static const QueryMatch *find(const QList<QueryMatch> &matches, const QStringList &command)
    {
        for (const QueryMatch &match : matches) {
            if (match.data().toStringList() == command) {
                return &match;
            }
        }
        return nullptr;
    }

private Q_SLOTS:
    void initTestCase() { initProperties(); }

    void findsSettingsPages()
    {
        // OrielOS's own modules are in the build.
        const QList<QueryMatch> matches = launchQuery(QStringLiteral("accent colour"));
        const QueryMatch *accent = find(matches, { QStringLiteral("orielos-settings"), QStringLiteral("accent") });
        QVERIFY(accent);
        QCOMPARE(accent->text(), QStringLiteral("Accent colour"));
        QCOMPARE(accent->subtext(), QStringLiteral("Settings › Personalisation"));
        QCOMPARE(accent->iconName(), QStringLiteral("preferences-desktop-color"));
        QCOMPARE(accent->categoryRelevance(), qreal(QueryMatch::CategoryRelevance::High));

        const QList<QueryMatch> update = launchQuery(QStringLiteral("windows update"));
        QVERIFY(find(update, { QStringLiteral("orielos-settings"), QStringLiteral("update") }));
    }

    void opensOtherModulesInSettings()
    {
        // Plasma's Fonts module, when the system has it; Settings has no page for it.
        if (!KPluginMetaData::findPluginById(QStringLiteral("plasma/kcms/systemsettings"), QStringLiteral("kcm_fonts")).isValid()) {
            QSKIP("Plasma's Fonts module isn't installed");
        }
        const QList<QueryMatch> matches = launchQuery(QStringLiteral("fonts"));
        const QueryMatch *fonts = find(matches, { QStringLiteral("orielos-settings"), QStringLiteral("kcm_fonts") });
        QVERIFY(fonts);
        QCOMPARE(fonts->subtext(), QStringLiteral("Settings › More settings"));
        QVERIFY(fonts->categoryRelevance() < qreal(QueryMatch::CategoryRelevance::High));
    }

    void neverOpensASettingsPageInSystemSettings()
    {
        for (const QString &query : { QStringLiteral("update"), QStringLiteral("accent"), QStringLiteral("accessory"), QStringLiteral("themes") }) {
            for (const QueryMatch &match : launchQuery(query)) {
                const QStringList command = match.data().toStringList();
                QVERIFY2(command.value(1) != QLatin1String("kcm_orielos_update") && command.value(1) != QLatin1String("kcm_orielos_accent")
                        && command.value(1) != QLatin1String("kcm_orielos_accessories") && command.value(1) != QLatin1String("kcm_lookandfeel"),
                    qPrintable(command.join(QLatin1Char(' '))));
            }
        }
    }
};

QTEST_MAIN(SettingsRunnerTest)

#include "settingsrunnertest.moc"
