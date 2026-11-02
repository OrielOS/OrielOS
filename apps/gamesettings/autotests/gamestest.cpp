// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixit.h"
#include "launchoptions.h"
#include "steamlibrary.h"
#include "vdf.h"
#include "willitrun.h"
#include "windowsprograms.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QTest>
#include <QTimeZone>

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
        QTest::newRow("all") << QStringLiteral(
            "PROTON_DLSS_UPGRADE=1 PROTON_ENABLE_WAYLAND=1 MANGOHUD=1 VKD3D_CONFIG=descriptor_heap gamemoderun gamescope -f -- %command%")
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
            QStringLiteral("\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"%1\"\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\"%2\"\n\t}\n}\n")
                .arg(root, second)
                .toUtf8());
        write(root + QStringLiteral("/steamapps/appmanifest_570.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"570\"\n\t\"name\"\t\t\"Dota 2\"\n}\n");
        write(root + QStringLiteral("/steamapps/appmanifest_1493710.acf"),
            "\"AppState\"\n{\n\t\"appid\"\t\t\"1493710\"\n\t\"name\"\t\t\"Proton Experimental\"\n}\n");
        write(root + QStringLiteral("/steamapps/appmanifest_2805730.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"2805730\"\n\t\"name\"\t\t\"Proton 10.0\"\n}\n");
        write(second + QStringLiteral("/steamapps/appmanifest_730.acf"), "\"AppState\"\n{\n\t\"appid\"\t\t\"730\"\n\t\"name\"\t\t\"Counter-Strike 2\"\n}\n");
        write(root + QStringLiteral("/appcache/librarycache/730/library_600x900.jpg"), "jpg");
        write(dir.filePath(QStringLiteral("ge/files/compatibilitytool.vdf")),
            "\"compatibilitytools\"\n{\n\t\"compat_tools\"\n\t{\n\t\t\"GE-Proton\"\n\t\t{\n\t\t\t\"display_name\"\t\t\"GE-Proton (Flatpak)\"\n\t\t}\n\t}\n}\n");
        write(root + QStringLiteral("/config/config.vdf"),
            "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{"
            "\n\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"GE-Proton\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n");
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

    void willItRun()
    {
        QFile list(QStringLiteral(ANTICHEAT_JSON));
        QVERIFY(list.open(QIODevice::ReadOnly));
        const QByteArray data = list.readAll();
        const WillItRun answers = WillItRun::fromJson(data);
        QVERIFY(!answers.isEmpty());
        QVERIFY(!answers.fetched().isEmpty());
        const QList<Verdict> valorant = answers.search(QStringLiteral("valorant"));
        QVERIFY(!valorant.isEmpty());
        QCOMPARE(valorant.first().status, Verdict::Status::Blocked);
        QVERIFY(!valorant.first().reason.isEmpty());
        const QList<Verdict> cs2 = answers.search(QStringLiteral("Counter-Strike 2"));
        QVERIFY(!cs2.isEmpty());
        QCOMPARE(cs2.first().name, QStringLiteral("Counter-Strike 2"));
        QCOMPARE(cs2.first().status, Verdict::Status::Works);
        QVERIFY(answers.search(QStringLiteral("  ")).isEmpty());

        // OrielOS's own verdict wins, and adds games the list doesn't have.
        const WillItRun ours = WillItRun::fromJson(
            data, R"({"games": [{"name": "Valorant", "status": "Running", "reason": "Tested."}, {"name": "Our Game", "status": "Supported"}]})");
        QCOMPARE(ours.search(QStringLiteral("valorant")).first().status, Verdict::Status::Works);
        QCOMPARE(ours.search(QStringLiteral("valorant")).first().reason, QStringLiteral("Tested."));
        QCOMPARE(ours.search(QStringLiteral("our game")).first().status, Verdict::Status::Works);

        // The cache keeps only what's shown, and reads back the same.
        const QByteArray upstream = R"([{"name": "A Game", "status": "Denied", "anticheats": ["BattlEye"], "notes": [["x", "https://www.protondb.com/"]]}])";
        const QByteArray copy = WillItRun::trimmed(upstream, QStringLiteral("2026-11-02"));
        QVERIFY(!copy.contains("protondb"));
        const WillItRun cached = WillItRun::fromJson(copy);
        QCOMPARE(cached.fetched(), QStringLiteral("2026-11-02"));
        QCOMPARE(cached.search(QStringLiteral("a game")).first().antiCheats, QStringList { QStringLiteral("BattlEye") });
        QVERIFY(WillItRun::trimmed("not json", QStringLiteral("x")).isEmpty());
    }

    void readsWindowsPrograms()
    {
        QTemporaryDir dir;
        const QString apps = dir.filePath(QStringLiteral("applications"));
        write(apps + QStringLiteral("/orielos-epic-1.desktop"),
            "[Desktop Entry]\nName=Epic Games Launcher\nIcon=epic\nExec=orielos-run-app --launch epic x\nX-OrielOS-WindowsPrefix=epic\n");
        write(apps + QStringLiteral("/orielos-epic-2.desktop"), "[Desktop Entry]\nName=Fortnite\nX-OrielOS-WindowsPrefix=epic\n");
        write(apps + QStringLiteral("/orielos-7z.desktop"), "[Desktop Entry]\nName=7-Zip\nX-OrielOS-WindowsPrefix=7z\n");
        write(apps + QStringLiteral("/firefox.desktop"), "[Desktop Entry]\nName=Firefox\n");
        const QList<WindowsProgram> programs = windowsPrograms(apps);
        QCOMPARE(programs.size(), 2);
        QCOMPARE(programs.at(0).name, QStringLiteral("7-Zip"));
        QCOMPARE(programs.at(1).prefix, QStringLiteral("epic"));
        QCOMPARE(programs.at(1).icon, QStringLiteral("epic"));

        const QString data = dir.filePath(QStringLiteral("data"));
        QVERIFY(windowsLaunchOptions(data, QStringLiteral("epic")).isEmpty());
        QVERIFY(setWindowsLaunchOptions(data, QStringLiteral("epic"), QStringLiteral("MANGOHUD=1 %command%")));
        QCOMPARE(windowsLaunchOptions(data, QStringLiteral("epic")), QStringLiteral("MANGOHUD=1 %command%"));
        QVERIFY(QFile::exists(data + QStringLiteral("/orielos/windows-apps/epic/launch-options")));
        QVERIFY(setWindowsLaunchOptions(data, QStringLiteral("epic"), QString()));
        QVERIFY(!QFile::exists(data + QStringLiteral("/orielos/windows-apps/epic/launch-options")));
    }

    // Every signature in data/fix-it.json matches a line like the one Proton, DXVK or VKD3D-Proton
    // writes for that failure, with every Game Settings switch on so the "when" ones apply.
    void fixItSignatures()
    {
        QFile file(QStringLiteral(FIXIT_JSON));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray json = file.readAll();
        const FixItRules rules = FixItRules::fromJson(json);
        QVERIFY(!rules.isEmpty());
        const QHash<QString, QString> logs = {
            { QStringLiteral("wayland-driver"), QStringLiteral("0124:err:waylanddrv:wayland_surface_create failed to create surface") },
            { QStringLiteral("gamescope"), QStringLiteral("sh: line 1: gamescope: command not found") },
            { QStringLiteral("dlss-upgrade"), QStringLiteral("nvngx: err: failed to load nvngx_dlss.dll") },
            { QStringLiteral("dx12"), QStringLiteral("0154:err:d3d12_device_create: D3D12CreateDevice failed, hr 0x80004005") },
            { QStringLiteral("vulkan"), QStringLiteral("err:   DxvkInstance: Failed to create Vulkan instance") },
            { QStringLiteral("shader-cache"), QStringLiteral("warn:  DXVK: State cache file is corrupt, discarding") },
            { QStringLiteral("video"), QStringLiteral("00f8:err:mfplat:resolver_create_gstreamer_handler Failed to create handler") },
            { QStringLiteral("easy-anti-cheat"), QStringLiteral("EasyAntiCheat: error: the anti-cheat runtime is not installed") },
            { QStringLiteral("battleye"), QStringLiteral("BattlEye: Failed to initialize BEService") },
            { QStringLiteral("missing-files"),
                QStringLiteral("0024:err:module:import_dll Library steam_api64.dll (which is needed by L\"C:\\Game\\game.exe\") not found") },
            { QStringLiteral("crash"), QStringLiteral("wine: Unhandled page fault on read access to 0000000000000000 at address 00000001400A1B2C") },
        };
        GameOptions all;
        all.dlssUpgrade = all.waylandHdr = all.gamescope = all.descriptorHeap = true;
        const QString options = all.apply(QString());
        const QStringList tools = { QStringLiteral("proton_experimental"), QStringLiteral("GE-Proton") };
        const QJsonArray signatures = QJsonDocument::fromJson(json).object().value(QLatin1String("signatures")).toArray();
        QCOMPARE(signatures.size(), logs.size());
        for (const QJsonValue &signature : signatures) {
            const QString id = signature.toObject().value(QLatin1String("id")).toString();
            QVERIFY2(logs.contains(id), qPrintable(id));
            QStringList found;
            for (const Diagnosis &diagnosis : rules.diagnose(logs.value(id), options, QString(), tools)) {
                found.append(diagnosis.id);
            }
            QVERIFY2(found.contains(id), qPrintable(id + QStringLiteral(" matched: ") + found.join(QLatin1Char(' '))));
        }
        QVERIFY(rules.diagnose(QStringLiteral("fsync: up and running.\nProtonFixes[1234] INFO: Running protonfixes"), options, QString(), tools).isEmpty());
    }

    void fixItLeavesOutFixesThatChangeNothing()
    {
        QFile file(QStringLiteral(FIXIT_JSON));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const FixItRules rules = FixItRules::fromJson(file.readAll());
        const QString crash = QStringLiteral("wine: Unhandled page fault on read access");
        // Already on Proton Experimental, and GE-Proton isn't installed: only Steam's default is left.
        QList<Diagnosis> found = rules.diagnose(crash, QString(), QStringLiteral("proton_experimental"), { QStringLiteral("proton_experimental") });
        QCOMPARE(found.size(), 1);
        QCOMPARE(found.first().fixes.size(), 1);
        QCOMPARE(found.first().fixes.first().id, QStringLiteral("steam-default"));
        // HDR off: the Wayland driver's signature doesn't apply.
        QVERIFY(rules.diagnose(QStringLiteral("err:waylanddrv:x"), QString(), QString(), { }).isEmpty());
        // Descriptor heaps off: DX12's first fix, turning them off, is left out.
        found = rules.diagnose(QStringLiteral("err:d3d12_device_create: failed"), QString(), QString(), { QStringLiteral("proton_experimental") });
        QCOMPARE(found.size(), 1);
        QCOMPARE(found.first().fixes.first().id, QStringLiteral("proton-experimental"));
        // PROTON_USE_WINED3D=1 already set and no other tool installed: nothing is left to suggest.
        found = rules.diagnose(QStringLiteral("No adapters found"), QStringLiteral("PROTON_USE_WINED3D=1 %command%"), QString(), { });
        QVERIFY(found.isEmpty());
    }

    void fixItRanksByWhatWorkedHere()
    {
        const QList<Fix> fixes = { { QStringLiteral("a"), Fix::Kind::Tool, { }, { } }, { QStringLiteral("b"), Fix::Kind::Tool, { }, { } },
            { QStringLiteral("c"), Fix::Kind::Tool, { }, { } } };
        const SystemFacts here { QStringLiteral("NVIDIA GeForce RTX 4050 Laptop GPU"), QStringLiteral("580.95.05"), QStringLiteral("7.2.9") };
        const SystemFacts other { QStringLiteral("NVIDIA GeForce RTX 3080"), QStringLiteral("580.95.05"), QStringLiteral("7.2.9") };
        const auto attempt = [](const QString &fix, const SystemFacts &system, bool worked, const QString &diagnosis = QStringLiteral("crash")) {
            return Attempt { QStringLiteral("1"), diagnosis, fix, { }, system, worked, { } };
        };
        // With no history the file's order stays.
        QCOMPARE(rankFixes(fixes, QStringLiteral("crash"), { }, here).first().id, QStringLiteral("a"));
        // c worked here (in the same driver series), a only failed here, b is untried here. Another
        // PC's and another cause's results don't count.
        const QList<Attempt> history = { attempt(QStringLiteral("c"), here, true), attempt(QStringLiteral("a"), here, false),
            attempt(QStringLiteral("b"), other, false), attempt(QStringLiteral("b"), here, false, QStringLiteral("video")),
            attempt(QStringLiteral("c"), { here.gpu, QStringLiteral("580.82.09"), { } }, true) };
        QStringList order;
        for (const Fix &fix : rankFixes(fixes, QStringLiteral("crash"), history, here)) {
            order.append(fix.id);
        }
        QCOMPARE(order, (QStringList { QStringLiteral("c"), QStringLiteral("b"), QStringLiteral("a") }));
    }

    void fixItLaunchOptionsAndUndo()
    {
        const QString log = QStringLiteral("PROTON_LOG=1");
        QCOMPARE(withVariable(QString(), log), QStringLiteral("PROTON_LOG=1 %command%"));
        QCOMPARE(withoutVariable(withVariable(QString(), log), log), QString());
        QCOMPARE(withVariable(QStringLiteral("gamemoderun %command% -novid"), log), QStringLiteral("gamemoderun PROTON_LOG=1 %command% -novid"));
        QCOMPARE(withoutVariable(QStringLiteral("gamemoderun PROTON_LOG=1 %command% -novid"), log), QStringLiteral("gamemoderun %command% -novid"));
        QCOMPARE(withVariable(QStringLiteral("-novid"), log), QStringLiteral("PROTON_LOG=1 %command% -novid"));
        QCOMPARE(withVariable(QStringLiteral("PROTON_LOG=1 %command%"), log), QStringLiteral("PROTON_LOG=1 %command%"));

        QTemporaryDir dir;
        const QString attempts = dir.filePath(QStringLiteral("fix-it/attempts.json"));
        QVERIFY(readAttempts(attempts).isEmpty());
        const Attempt first { QStringLiteral("730"), QStringLiteral("crash"), QStringLiteral("ge-proton"), QStringLiteral("GE-Proton"),
            { QStringLiteral("RTX"), QStringLiteral("580.95.05"), QStringLiteral("7.2.9") }, true,
            QDateTime(QDate(2026, 11, 2), QTime(20, 0), QTimeZone::UTC) };
        QVERIFY(appendAttempt(attempts, first));
        QVERIFY(appendAttempt(attempts, first));
        const QList<Attempt> back = readAttempts(attempts);
        QCOMPARE(back.size(), 2);
        QCOMPARE(back.first().fix, QStringLiteral("ge-proton"));
        QCOMPARE(back.first().system.driver, QStringLiteral("580.95.05"));
        QVERIFY(back.first().worked);
        QCOMPARE(back.first().when, first.when);

        const QString undoPath = dir.filePath(QStringLiteral("fix-it/undo-730.json"));
        QVERIFY(!Undo::read(undoPath).isValid());
        const Undo undo { QStringLiteral("730"), QStringLiteral("wined3d"), QString(), QStringLiteral("  -novid   %command%"), QString(), QString() };
        QVERIFY(undo.write(undoPath));
        const Undo again = Undo::read(undoPath);
        QCOMPARE(again.appId, QStringLiteral("730"));
        // Launch options come back exactly as they were typed, spaces and all.
        QCOMPARE(again.launchOptions, QStringLiteral("  -novid   %command%"));
        QCOMPARE(again.tool, QString());
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
