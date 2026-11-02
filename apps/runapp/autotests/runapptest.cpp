// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "runapp.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QtEndian>

#include <sys/xattr.h>

using namespace OrielOSRunApp;

namespace {

constexpr quint32 hasIdList = 0x01;
constexpr quint32 hasLinkInfo = 0x02;
constexpr quint32 hasRelativePath = 0x08;
constexpr quint32 hasArguments = 0x20;
constexpr quint32 isUnicode = 0x80;

// A shortcut's 76-byte header with the given flags.
QByteArray header(quint32 flags)
{
    QByteArray data(0x4C, '\0');
    qToLittleEndian<quint32>(0x4C, data.data());
    qToLittleEndian<quint32>(flags, data.data() + 0x14);
    return data;
}

// A LinkInfo block with a local base path and a common path suffix, as Windows and Wine write them.
QByteArray linkInfo(const QByteArray &base, const QByteArray &suffix)
{
    constexpr quint32 infoHeaderSize = 0x1C;
    const QByteArray volumeId(16, '\0');
    const quint32 baseOffset = infoHeaderSize + volumeId.size();
    const quint32 suffixOffset = baseOffset + base.size() + 1;
    QByteArray block(infoHeaderSize, '\0');
    block += volumeId + base + '\0' + suffix + '\0';
    qToLittleEndian<quint32>(block.size(), block.data());
    qToLittleEndian<quint32>(infoHeaderSize, block.data() + 4);
    qToLittleEndian<quint32>(0x01, block.data() + 8);
    qToLittleEndian<quint32>(infoHeaderSize, block.data() + 12);
    qToLittleEndian<quint32>(baseOffset, block.data() + 16);
    qToLittleEndian<quint32>(0, block.data() + 20);
    qToLittleEndian<quint32>(suffixOffset, block.data() + 24);
    return block;
}

// One of a shortcut's counted strings.
QByteArray counted(const QString &text, bool unicode)
{
    QByteArray data(2, '\0');
    qToLittleEndian<quint16>(text.size(), data.data());
    if (unicode) {
        for (const QChar c : text) {
            char unit[2];
            qToLittleEndian<quint16>(c.unicode(), unit);
            data.append(unit, 2);
        }
    } else {
        data += text.toLatin1();
    }
    return data;
}

// A shortcut to a Windows path, with arguments.
QByteArray shortcutTo(const QByteArray &windowsPath, const QString &arguments = QString())
{
    QByteArray data = header(hasLinkInfo | isUnicode | (arguments.isEmpty() ? 0 : hasArguments));
    data += linkInfo(windowsPath, QByteArray());
    if (!arguments.isEmpty()) {
        data += counted(arguments, true);
    }
    return data;
}

void writeFile(const QString &path, const QByteArray &data = QByteArray())
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(data);
}

QString readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromUtf8(file.readAll());
}

} // namespace

class RunAppTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void prefixName_data()
    {
        QTest::addColumn<QString>("file");
        QTest::addColumn<QString>("name");
        QTest::newRow("joined words") << QStringLiteral("SteamSetup.exe") << QStringLiteral("steam");
        QTest::newRow("dotted name") << QStringLiteral("Battle.net-Setup.exe") << QStringLiteral("battle-net");
        QTest::newRow("version and architecture") << QStringLiteral("npp.8.6.2.Installer.x64.exe") << QStringLiteral("npp");
        QTest::newRow("msi") << QStringLiteral("EpicInstaller-15.17.1.msi") << QStringLiteral("epic");
        QTest::newRow("platform") << QStringLiteral("vlc-3.0.20-win64.exe") << QStringLiteral("vlc");
        QTest::newRow("nothing left") << QStringLiteral("setup.exe") << QStringLiteral("app");
        QTest::newRow("spaces") << QStringLiteral("Discord Setup 1.0.9.exe") << QStringLiteral("discord");
        QTest::newRow("capitals") << QStringLiteral("VLCSetup.exe") << QStringLiteral("vlc");
        QTest::newRow("folder") << QStringLiteral("/home/a/Downloads/GOG Galaxy Setup.exe") << QStringLiteral("gog-galaxy");
        QTest::newRow("version joined to the name") << QStringLiteral("7z2605-x64.exe") << QStringLiteral("7z");
        QTest::newRow("older joined version") << QStringLiteral("7z1900.exe") << QStringLiteral("7z");
        QTest::newRow("short number in the name") << QStringLiteral("x264-r3191.exe") << QStringLiteral("x264");
        QTest::newRow("number ending a name") << QStringLiteral("Doom64-Setup.exe") << QStringLiteral("doom64");
    }

    void prefixName()
    {
        QFETCH(QString, file);
        QFETCH(QString, name);
        QCOMPARE(OrielOSRunApp::prefixName(file), name);
    }

    void installers()
    {
        QVERIFY(looksLikeInstaller(QStringLiteral("SteamSetup.exe")));
        QVERIFY(looksLikeInstaller(QStringLiteral("EpicGames.msi")));
        QVERIFY(looksLikeInstaller(QStringLiteral("ubisoft_connect_installer.exe")));
        QVERIFY(!looksLikeInstaller(QStringLiteral("Game.exe")));
        QVERIFY(!looksLikeInstaller(QStringLiteral("putty-0.81.exe")));
    }

    void paths()
    {
        QCOMPARE(prefixDir(QStringLiteral("/home/a/.local/share"), QStringLiteral("steam")),
            QStringLiteral("/home/a/.local/share/orielos/windows-apps/steam/prefix"));
        QCOMPARE(
            logFile(QStringLiteral("/home/a/.local/state"), QStringLiteral("steam")), QStringLiteral("/home/a/.local/state/orielos/windows-apps/steam.log"));
    }

    void command()
    {
        const Command exe = OrielOSRunApp::command(QStringLiteral("/p"), QStringLiteral("/d/Game.exe"), { QStringLiteral("-windowed") });
        QCOMPARE(exe.program, QStringLiteral("umu-run"));
        QCOMPARE(exe.arguments, (QStringList { QStringLiteral("/d/Game.exe"), QStringLiteral("-windowed") }));
        QCOMPARE(exe.environment.value(QStringLiteral("WINEPREFIX")), QStringLiteral("/p"));
        QCOMPARE(exe.environment.value(QStringLiteral("PROTONPATH")), QStringLiteral("GE-Proton"));
        QCOMPARE(exe.environment.value(QStringLiteral("GAMEID")), QStringLiteral("umu-default"));
        QCOMPARE(exe.environment.value(QStringLiteral("STORE")), QStringLiteral("none"));

        const Command msi = OrielOSRunApp::command(QStringLiteral("/p"), QStringLiteral("/d/App.MSI"));
        QCOMPARE(msi.arguments, (QStringList { QStringLiteral("msiexec"), QStringLiteral("/i"), QStringLiteral("/d/App.MSI") }));
    }

    void firstDownload()
    {
        QTemporaryDir data;
        QVERIFY(needsFirstDownload(data.path()));
        QVERIFY(QDir(data.path()).mkpath(QStringLiteral("Steam/compatibilitytools.d/GE-Proton10-25")));
        QVERIFY(needsFirstDownload(data.path()));
        QVERIFY(QDir(data.path()).mkpath(QStringLiteral("umu")));
        QVERIFY(!needsFirstDownload(data.path()));
    }

    void downloadSource()
    {
        QTemporaryDir dir;
        const QString file = QDir(dir.path()).filePath(QStringLiteral("Setup.exe"));
        writeFile(file);
        QCOMPARE(OrielOSRunApp::downloadSource(file).url, QString());

        const QByteArray url = "https://cdn.example.com/downloads/Setup.exe";
        if (setxattr(QFile::encodeName(file).constData(), "user.xdg.origin.url", url.constData(), url.size(), 0) != 0) {
            QSKIP("this file system doesn't keep user attributes");
        }
        const DownloadSource source = OrielOSRunApp::downloadSource(file);
        QCOMPARE(source.url, QString::fromLatin1(url));
        QCOMPARE(source.host, QStringLiteral("cdn.example.com"));
    }

    void readsLocalPath()
    {
        const QByteArray data = header(hasLinkInfo) + linkInfo("C:\\Program Files\\Foo\\", "foo.exe");
        const std::optional<LinkTarget> target = readShortcut(data);
        QVERIFY(target);
        QCOMPARE(target->windowsPath, QStringLiteral("C:\\Program Files\\Foo\\foo.exe"));
        QVERIFY(target->arguments.isEmpty());
    }

    void readsUnicodeRelativePathAfterIdList()
    {
        QByteArray data = header(hasIdList | hasRelativePath | isUnicode);
        // An item ID list of 4 bytes, which the reader skips.
        data += QByteArray("\x04\x00", 2) + QByteArray(4, '\0');
        data += counted(QStringLiteral("..\\..\\Café\\game.exe"), true);
        const std::optional<LinkTarget> target = readShortcut(data);
        QVERIFY(target);
        QVERIFY(target->windowsPath.isEmpty());
        QCOMPARE(target->relativePath, QStringLiteral("..\\..\\Café\\game.exe"));
    }

    void readsArguments()
    {
        const std::optional<LinkTarget> target = readShortcut(shortcutTo("C:\\Games\\launcher.exe", QStringLiteral("-silent \"two words\"")));
        QVERIFY(target);
        QCOMPARE(target->windowsPath, QStringLiteral("C:\\Games\\launcher.exe"));
        QCOMPARE(target->arguments, QStringLiteral("-silent \"two words\""));
        QCOMPARE(splitArguments(target->arguments), (QStringList { QStringLiteral("-silent"), QStringLiteral("two words") }));
    }

    void refusesBrokenShortcuts()
    {
        QVERIFY(!readShortcut(QByteArray()));
        QVERIFY(!readShortcut(QByteArray("not a shortcut at all, just text")));
        // A string that runs past the end of the file.
        QByteArray truncated = header(hasArguments);
        truncated += QByteArray("\xFF\x00", 2) + "short";
        QVERIFY(!readShortcut(truncated));
        // LinkInfo that claims to be larger than the file.
        QByteArray oversized = header(hasLinkInfo) + linkInfo("C:\\a.exe", "");
        qToLittleEndian<quint32>(0x10000, oversized.data() + 0x4C);
        QVERIFY(!readShortcut(oversized));
        // A header without a target.
        QVERIFY(!readShortcut(header(0)));
    }

    void linuxPaths()
    {
        QCOMPARE(linuxPath(QStringLiteral("/p"), QStringLiteral("C:\\Program Files\\Foo\\foo.exe")), QStringLiteral("/p/drive_c/Program Files/Foo/foo.exe"));
        QCOMPARE(linuxPath(QStringLiteral("/p"), QStringLiteral("c:\\a\\..\\b.exe")), QStringLiteral("/p/drive_c/b.exe"));
        QCOMPARE(linuxPath(QStringLiteral("/p"), QStringLiteral("Z:\\home\\a\\game.exe")), QStringLiteral("/home/a/game.exe"));
        QVERIFY(linuxPath(QStringLiteral("/p"), QStringLiteral("relative\\game.exe")).isEmpty());
    }

    void findsShortcuts()
    {
        QTemporaryDir dir;
        const QString prefix = dir.path();
        const QString drive = prefix + QStringLiteral("/drive_c");
        const QString menu = drive + QStringLiteral("/ProgramData/Microsoft/Windows/Start Menu/Programs");
        writeFile(drive + QStringLiteral("/Program Files/Foo/Foo.exe"));
        writeFile(drive + QStringLiteral("/Program Files/Foo/unins000.exe"));
        writeFile(drive + QStringLiteral("/Program Files/Foo/readme.txt"));

        // The shortcut's case differs from the files', as Windows allows.
        writeFile(menu + QStringLiteral("/Foo/Foo.lnk"), shortcutTo("C:\\program files\\foo\\foo.exe", QStringLiteral("--fast")));
        writeFile(menu + QStringLiteral("/Foo/Uninstall Foo.lnk"), shortcutTo("C:\\Program Files\\Foo\\unins000.exe"));
        writeFile(menu + QStringLiteral("/Foo/Read me.lnk"), shortcutTo("C:\\Program Files\\Foo\\readme.txt"));
        writeFile(menu + QStringLiteral("/Gone.lnk"), shortcutTo("C:\\Program Files\\Gone\\gone.exe"));
        writeFile(menu + QStringLiteral("/Broken.lnk"), QByteArray("junk"));
        // The same program again, on the desktop.
        writeFile(drive + QStringLiteral("/users/steamuser/Desktop/Foo.lnk"), shortcutTo("C:\\Program Files\\Foo\\Foo.exe"));

        const QList<Shortcut> shortcuts = findShortcuts(prefix);
        QCOMPARE(shortcuts.size(), 1);
        QCOMPARE(shortcuts.constFirst().name, QStringLiteral("Foo"));
        QCOMPARE(shortcuts.constFirst().target, drive + QStringLiteral("/Program Files/Foo/Foo.exe"));
        QCOMPARE(shortcuts.constFirst().arguments, QStringList { QStringLiteral("--fast") });
    }

    void execArguments()
    {
        QCOMPARE(execArgument(QStringLiteral("plain")), QStringLiteral("plain"));
        QCOMPARE(execArgument(QStringLiteral("with space")), QStringLiteral("\"with space\""));
        QCOMPARE(execArgument(QStringLiteral("100%")), QStringLiteral("100%%"));
        QCOMPARE(execArgument(QStringLiteral("a$b")), QStringLiteral("\"a\\\\$b\""));
        QCOMPARE(execArgument(QStringLiteral("say \"hi\"")), QStringLiteral("\"say \\\\\"hi\\\\\"\""));
        QCOMPARE(execArgument(QStringLiteral("C:\\dir")), QStringLiteral("\"C:\\\\\\\\dir\""));
        QCOMPARE(execArgument(QString()), QStringLiteral("\"\""));
    }

    void writesStartEntries()
    {
        QTemporaryDir dir;
        const QString applications = QDir(dir.path()).filePath(QStringLiteral("applications"));
        const Shortcut shortcut { QStringLiteral("Foo Game"), QStringLiteral("/p/drive_c/Program Files/Foo/Foo.exe"), { QStringLiteral("--fast") } };

        const QString path = writeStartEntry(applications, QStringLiteral("foo"), shortcut);
        QCOMPARE(path, applications + QStringLiteral("/orielos-windows-foo-foo.desktop"));
        const QString entry = readFile(path);
        QVERIFY(entry.startsWith(QStringLiteral("[Desktop Entry]\n")));
        QVERIFY(entry.contains(QStringLiteral("\nName=Foo Game\n")));
        QVERIFY(entry.contains(QStringLiteral("\nExec=orielos-run-app --launch foo \"/p/drive_c/Program Files/Foo/Foo.exe\" --fast\n")));
        QVERIFY(entry.contains(QStringLiteral("\nX-OrielOS-WindowsPrefix=foo\n")));

        // The same program again replaces its entry.
        QCOMPARE(writeStartEntry(applications, QStringLiteral("foo"), shortcut), path);
        QCOMPARE(QDir(applications).entryList(QDir::Files).size(), 1);
    }

    void knowsApps_data()
    {
        QTest::addColumn<QString>("fileName");
        QTest::addColumn<QString>("name");
        QTest::addColumn<QString>("store");
        QTest::addColumn<bool>("launcher");
        QTest::addColumn<bool>("package");
        QTest::newRow("discord") << QStringLiteral("DiscordSetup.exe") << QStringLiteral("Discord") << QStringLiteral("com.discordapp.Discord") << false << false;
        QTest::newRow("spotify") << QStringLiteral("SpotifyFullSetup.exe") << QStringLiteral("Spotify") << QStringLiteral("com.spotify.Client") << false << false;
        QTest::newRow("obs") << QStringLiteral("OBS-Studio-31.0-Windows-Installer.exe") << QStringLiteral("OBS Studio") << QStringLiteral("com.obsproject.Studio")
                             << false << false;
        QTest::newRow("epic") << QStringLiteral("EpicInstaller-18.4.0.msi") << QStringLiteral("Epic Games Launcher") << QString() << true << false;
        QTest::newRow("gog") << QStringLiteral("GOG_Galaxy_2.0.exe") << QStringLiteral("GOG Galaxy") << QString() << true << false;
        QTest::newRow("battle.net") << QStringLiteral("Battle.net-Setup.exe") << QStringLiteral("Battle.net") << QString() << true << false;
        QTest::newRow("ea") << QStringLiteral("EAappInstaller.exe") << QStringLiteral("EA app") << QString() << true << false;
        QTest::newRow("ubisoft") << QStringLiteral("UbisoftConnectInstaller.exe") << QStringLiteral("Ubisoft Connect") << QString() << true << false;
        QTest::newRow("rockstar") << QStringLiteral("Rockstar-Games-Launcher.exe") << QStringLiteral("Rockstar Games Launcher") << QString() << true << false;
        QTest::newRow("claude") << QStringLiteral("Claude Setup.exe") << QStringLiteral("Claude") << QString() << false << true;
        QTest::newRow("any msix") << QStringLiteral("SomeApp_1.2.msixbundle") << QString() << QString() << false << true;
    }

    void knowsApps()
    {
        QFETCH(QString, fileName);
        QFETCH(QString, name);
        QFETCH(QString, store);
        QFETCH(bool, launcher);
        QFETCH(bool, package);
        QFile list(QStringLiteral(KNOWN_APPS_JSON));
        QVERIFY(list.open(QIODevice::ReadOnly));
        const auto known = knownApp(list.readAll(), fileName);
        QVERIFY(known);
        QCOMPARE(known->name, name);
        QCOMPARE(known->store, store);
        QCOMPARE(known->launcher, launcher);
        QCOMPARE(known->package, package);
    }

    void doesntKnowOthers()
    {
        QFile list(QStringLiteral(KNOWN_APPS_JSON));
        QVERIFY(list.open(QIODevice::ReadOnly));
        const QByteArray data = list.readAll();
        QVERIFY(!knownApp(data, QStringLiteral("7z2605-x64.exe")));
        // A name that only starts like a known one isn't it.
        QVERIFY(!knownApp(data, QStringLiteral("SteamworksTool.exe")));
    }

    void choosesTheList()
    {
        QTemporaryDir dir;
        const QString bundled = dir.filePath(QStringLiteral("bundled.json"));
        const QString fetched = dir.filePath(QStringLiteral("fetched.json"));
        const auto write = [](const QString &path, const QByteArray &data) {
            QFile file(path);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(data);
        };
        write(bundled, R"({"version": 2, "apps": [{"name": "Bundled"}]})");
        // Nothing fetched yet, or a broken or older copy: the image's.
        QVERIFY(knownAppsList(fetched, bundled).contains("Bundled"));
        write(fetched, "not json");
        QVERIFY(knownAppsList(fetched, bundled).contains("Bundled"));
        write(fetched, R"({"version": 1, "apps": []})");
        QVERIFY(knownAppsList(fetched, bundled).contains("Bundled"));
        write(fetched, R"({"version": 3, "apps": [{"name": "Fetched"}]})");
        QVERIFY(knownAppsList(fetched, bundled).contains("Fetched"));
    }
};

QTEST_GUILESS_MAIN(RunAppTest)

#include "runapptest.moc"
