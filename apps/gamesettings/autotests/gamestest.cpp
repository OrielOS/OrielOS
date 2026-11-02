// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "launchoptions.h"
#include "steamlibrary.h"
#include "vdf.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSGames;

Q_DECLARE_METATYPE(OrielOSGames::GameOptions)

namespace {

void write(const QString &path, const QByteArray &text)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(text);
}

QString read(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
}

} // namespace

class GamesTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesAndWritesVdf()
    {
        const auto root = parseVdf(QStringLiteral("// a comment\n\"AppState\"\n{\n\t\"appid\"\t\t\"570\"\n\t\"name\"\t\t\"Dota \\\"2\\\"\"\n"
                                                  "\t\"Nested\" [$WIN32]\n\t{\n\t\tbare value\n\t}\n}\n"));
        QVERIFY(root);
        const VdfNode *state = root->child(QStringLiteral("appstate"));
        QVERIFY(state);
        QCOMPARE(state->valueOf(QStringLiteral("APPID")), QStringLiteral("570"));
        QCOMPARE(state->valueOf(QStringLiteral("name")), QStringLiteral("Dota \"2\""));
        QCOMPARE(state->find({ QStringLiteral("Nested") })->valueOf(QStringLiteral("bare")), QStringLiteral("value"));
        // Written and read again, it's the same.
        const auto again = parseVdf(writeVdf(*root));
        QVERIFY(again);
        QCOMPARE(again->find({ QStringLiteral("AppState") })->valueOf(QStringLiteral("name")), QStringLiteral("Dota \"2\""));
        QVERIFY(!parseVdf(QStringLiteral("\"a\" { \"b\" \"c\"")));
        QVERIFY(!parseVdf(QStringLiteral("\"unterminated")));
    }

    void ensuresAndRemoves()
    {
        VdfNode root;
        root.block = true;
        root.ensure({ QStringLiteral("a"), QStringLiteral("b") }).set(QStringLiteral("k"), QStringLiteral("v"));
        QCOMPARE(root.find({ QStringLiteral("A"), QStringLiteral("B") })->valueOf(QStringLiteral("k")), QStringLiteral("v"));
        QVERIFY(root.ensure({ QStringLiteral("a"), QStringLiteral("b") }).remove(QStringLiteral("K")));
        QVERIFY(root.find({ QStringLiteral("a"), QStringLiteral("b") })->children.isEmpty());
    }

    void readsLaunchOptions_data()
    {
        QTest::addColumn<QString>("options");
        QTest::addColumn<GameOptions>("expected");
        QTest::newRow("none") << QString() << GameOptions { };
        QTest::newRow("all") << QStringLiteral("PROTON_DLSS_UPGRADE=1 PROTON_ENABLE_WAYLAND=1 MANGOHUD=1 VKD3D_CONFIG=descriptor_heap gamemoderun gamescope -f -- %command%")
                             << GameOptions { true, true, true, true, true, true };
        QTest::newRow("arguments only") << QStringLiteral("-novid -high") << GameOptions { };
    }

    void readsLaunchOptions()
    {
        QFETCH(QString, options);
        QFETCH(GameOptions, expected);
        QCOMPARE(GameOptions::read(options), expected);
    }

    void writesLaunchOptions()
    {
        GameOptions options;
        options.fpsOverlay = true;
        options.gameMode = true;
        QCOMPARE(options.apply(QString()), QStringLiteral("MANGOHUD=1 gamemoderun %command%"));
        // The user's own variables and the game's arguments stay where they were.
        QCOMPARE(options.apply(QStringLiteral("DXVK_HUD=1 %command% -novid")), QStringLiteral("DXVK_HUD=1 MANGOHUD=1 gamemoderun %command% -novid"));
        // Arguments without %command% get one once something goes before the game.
        QCOMPARE(options.apply(QStringLiteral("-novid")), QStringLiteral("MANGOHUD=1 gamemoderun %command% -novid"));
        options.gamescope = true;
        QCOMPARE(options.apply(QString()), QStringLiteral("MANGOHUD=1 gamemoderun gamescope -f -- %command%"));
    }

    void turningOffTakesOutOnlyItsPart()
    {
        const QString before = QStringLiteral("DXVK_HUD=1 %command% -novid");
        GameOptions on;
        on.dlssUpgrade = on.waylandHdr = on.fpsOverlay = on.gameMode = on.descriptorHeap = true;
        const QString withAll = on.apply(before);
        QCOMPARE(GameOptions::read(withAll), on);
        QCOMPARE(GameOptions { }.apply(withAll), before);
        // With nothing before the game, the options go back to exactly the arguments.
        QCOMPARE(GameOptions { }.apply(on.apply(QStringLiteral("-novid"))), QStringLiteral("%command% -novid"));
        QCOMPARE(GameOptions { }.apply(QStringLiteral("-novid")), QStringLiteral("-novid"));
        // A gamescope line the user wrote themselves isn't OrielOS's to remove.
        QCOMPARE(GameOptions { }.apply(QStringLiteral("gamescope -W 2560 -- %command%")), QStringLiteral("gamescope -W 2560 -- %command%"));
    }

    void readsSteam()
    {
        QTemporaryDir dir;
        const QString root = dir.filePath(QStringLiteral("Steam"));
        const QString second = dir.filePath(QStringLiteral("Games"));
        write(root + QStringLiteral("/steamapps/libraryfolders.vdf"),
            QStringLiteral("\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"%1\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"%2\"\n\t}\n}\n").arg(root, second).toUtf8());
        write(root + QStringLiteral("/steamapps/appmanifest_570.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"570\"\n\t\"name\"\t\t\"Dota 2\"\n}\n");
        write(root + QStringLiteral("/steamapps/appmanifest_1493710.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"1493710\"\n\t\"name\"\t\t\"Proton Experimental\"\n}\n");
        write(root + QStringLiteral("/steamapps/appmanifest_2805730.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"2805730\"\n\t\"name\"\t\t\"Proton 10.0\"\n}\n");
        write(second + QStringLiteral("/steamapps/appmanifest_730.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"730\"\n\t\"name\"\t\t\"Counter-Strike 2\"\n}\n");
        write(root + QStringLiteral("/appcache/librarycache/730/library_600x900.jpg"), "jpg");
        write(dir.filePath(QStringLiteral("ge/files/compatibilitytool.vdf")),
            "\"compatibilitytools\"\n{\n\t\"compat_tools\"\n\t{\n\t\t\"GE-Proton\"\n\t\t{\n\t\t\t\"display_name\"\t\t\"GE-Proton (Flatpak)\"\n\t\t}\n\t}\n}\n");
        write(root + QStringLiteral("/config/config.vdf"),
            "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"GE-Proton\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n");
        write(root + QStringLiteral("/userdata/1234/config/localconfig.vdf"), "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t}\n}\n");

        const SteamLibrary steam(root);
        QVERIFY(steam.installed());
        QCOMPARE(steam.libraries(), (QStringList { root, second }));
        const QList<SteamGame> games = steam.games();
        QCOMPARE(games.size(), 2);
        QCOMPARE(games.at(0).name, QStringLiteral("Counter-Strike 2"));
        QVERIFY(games.at(0).art.endsWith(QLatin1String("730/library_600x900.jpg")));
        QCOMPARE(games.at(1).name, QStringLiteral("Dota 2"));
        QVERIFY(games.at(1).art.isEmpty());

        const QList<CompatTool> tools = steam.compatTools({ dir.filePath(QStringLiteral("ge")) });
        QCOMPARE(tools.size(), 3);
        QCOMPARE(tools.at(0).id, QStringLiteral("GE-Proton"));
        QStringList ids;
        for (const CompatTool &tool : tools) {
            ids.append(tool.id);
        }
        QVERIFY(ids.contains(QStringLiteral("proton_experimental")));
        QVERIFY(ids.contains(QStringLiteral("proton_10")));

        QVERIFY(steam.compatTool(QStringLiteral("730")).isEmpty());
        QVERIFY(steam.setCompatTool(QStringLiteral("730"), QStringLiteral("proton_experimental")));
        QCOMPARE(steam.compatTool(QStringLiteral("730")), QStringLiteral("proton_experimental"));
        // Steam's own default stays.
        QVERIFY(read(root + QStringLiteral("/config/config.vdf")).contains(QLatin1String("\"GE-Proton\"")));
        QVERIFY(QFile::exists(root + QStringLiteral("/config/config.vdf.orielos-before-game-settings")));
        QVERIFY(steam.setCompatTool(QStringLiteral("730"), QString()));
        QVERIFY(steam.compatTool(QStringLiteral("730")).isEmpty());

        QVERIFY(steam.setLaunchOptions(QStringLiteral("730"), QStringLiteral("MANGOHUD=1 %command%")));
        QCOMPARE(steam.launchOptions(QStringLiteral("730")), QStringLiteral("MANGOHUD=1 %command%"));
        QVERIFY(steam.setLaunchOptions(QStringLiteral("730"), QString()));
        QVERIFY(steam.launchOptions(QStringLiteral("730")).isEmpty());
    }

    void withoutSteam()
    {
        QTemporaryDir dir;
        const SteamLibrary steam(dir.filePath(QStringLiteral("none")));
        QVERIFY(!steam.installed());
        QVERIFY(steam.games().isEmpty());
        QVERIFY(!steam.setLaunchOptions(QStringLiteral("730"), QStringLiteral("x")));
    }
};

QTEST_GUILESS_MAIN(GamesTest)

#include "gamestest.moc"
