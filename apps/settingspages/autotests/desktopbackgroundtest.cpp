// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "desktopbackground.h"

#include <QDir>
#include <QFile>
#include <QJSEngine>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

// Plasma's desktop scripting, as much as the scripts use: two desktops (two displays) with their
// wallpaper settings. The URLs are built so that moc, which doesn't read raw strings, sees no
// comment in them.
const QString fakeDesktops = QStringLiteral(R"JS(
function makeDesktop(plugin, image) {
    return {
        wallpaperPlugin: plugin, currentConfigGroup: [], reloads: 0,
        config: { "Wallpaper/org.kde.image/General": { Image: image, FillMode: 1 } },
        group: function () { var key = this.currentConfigGroup.join("/"); this.config[key] = this.config[key] || {}; return this.config[key]; },
        readConfig: function (key, fallback) { var g = this.group(); return key in g ? g[key] : fallback; },
        writeConfig: function (key, value) { this.group()[key] = value; },
        reloadConfig: function () { this.reloads += 1; },
    };
}
var first = makeDesktop("org.kde.color", "");
var second = makeDesktop("org.kde.image", "file:" + "/".repeat(3) + "home/someone/Pictures/lake.jpg");
function desktops() { return [first, second]; }
var printed = "";
function print(text) { printed += text; }
)JS");

QJSValue run(QJSEngine &engine, const QString &script)
{
    const QJSValue result = engine.evaluate(fakeDesktops + script);
    if (result.isError()) {
        qWarning() << result.toString();
    }
    return result;
}

void writeFile(const QString &path, const QByteArray &contents)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(contents);
}

// A runner that answers the read with answer and keeps every script.
struct FakeShell
{
    QString answer = QStringLiteral("{\"image\":\"/tmp/none.jpg\",\"fillMode\":2}");
    QStringList scripts;

    DesktopBackground::Runner runner()
    {
        return [this](const QString &script, std::function<void(bool, const QString &)> done) {
            scripts.append(script);
            done(true, script.contains(QLatin1String("JSON.stringify")) ? answer : QString());
        };
    }
};

} // namespace

class DesktopBackgroundTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void readsTheFirstPictureDesktop()
    {
        QJSEngine engine;
        QVERIFY(!run(engine, DesktopBackground::readScript()).isError());
        QCOMPARE(
            engine.evaluate(QStringLiteral("printed")).toString(), QStringLiteral("{\"image\":\"file:///home/someone/Pictures/lake.jpg\",\"fillMode\":1}"));
    }

    void setsThePictureOnEveryDesktop()
    {
        QJSEngine engine;
        const QString path = QStringLiteral("/home/someone/Pictures/it's \"here\" \\ now.png");
        QVERIFY(!run(engine, DesktopBackground::imageScript(path)).isError());
        for (const QString &desktop : { QStringLiteral("first"), QStringLiteral("second") }) {
            QCOMPARE(engine.evaluate(desktop + QStringLiteral(".wallpaperPlugin")).toString(), QStringLiteral("org.kde.image"));
            QCOMPARE(engine.evaluate(desktop + QStringLiteral(".config[\"Wallpaper/org.kde.image/General\"].Image")).toString(),
                QUrl::fromLocalFile(path).toString());
            QCOMPARE(engine.evaluate(desktop + QStringLiteral(".reloads")).toInt(), 1);
        }
    }

    void givesAPackageFolderItsSlash()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QJSEngine engine;
        QVERIFY(!run(engine, DesktopBackground::imageScript(dir.path())).isError());
        QCOMPARE(engine.evaluate(QStringLiteral("second.config[\"Wallpaper/org.kde.image/General\"].Image")).toString(),
            QUrl::fromLocalFile(dir.path()).toString() + QLatin1Char('/'));
    }

    void setsTheFit()
    {
        QJSEngine engine;
        QVERIFY(!run(engine, DesktopBackground::fillModeScript(DesktopBackground::Tile)).isError());
        QCOMPARE(engine.evaluate(QStringLiteral("first.config[\"Wallpaper/org.kde.image/General\"].FillMode")).toInt(), 3);
        QCOMPARE(engine.evaluate(QStringLiteral("second.config[\"Wallpaper/org.kde.image/General\"].FillMode")).toInt(), 3);
    }

    void readsPlasmasImageValues()
    {
        QCOMPARE(DesktopBackground::localPath(QStringLiteral("file:///home/someone/My%20Pictures/a.jpg")), QStringLiteral("/home/someone/My Pictures/a.jpg"));
        QCOMPARE(DesktopBackground::localPath(QStringLiteral("file:///usr/share/wallpapers/OrielOS/")), QStringLiteral("/usr/share/wallpapers/OrielOS"));
        QCOMPARE(DesktopBackground::localPath(QStringLiteral("/home/someone/b.png")), QStringLiteral("/home/someone/b.png"));
        QCOMPARE(DesktopBackground::localPath(QString()), QString());
        QCOMPARE(DesktopBackground::localPath(QStringLiteral("NoSuchWallpaperPackage")), QString());
    }

    void keepsTheLastFive()
    {
        const QStringList five = { QStringLiteral("/a"), QStringLiteral("/b"), QStringLiteral("/c"), QStringLiteral("/d"), QStringLiteral("/e") };
        QCOMPARE(DesktopBackground::withRecent(five, QStringLiteral("/f")),
            (QStringList { QStringLiteral("/f"), QStringLiteral("/a"), QStringLiteral("/b"), QStringLiteral("/c"), QStringLiteral("/d") }));
        QCOMPARE(DesktopBackground::withRecent(five, QStringLiteral("/c")),
            (QStringList { QStringLiteral("/c"), QStringLiteral("/a"), QStringLiteral("/b"), QStringLiteral("/d"), QStringLiteral("/e") }));
        QCOMPARE(DesktopBackground::withRecent({ QStringLiteral("/a"), QStringLiteral("/a") }, QString()), QStringList { QStringLiteral("/a") });
    }

    void listsAndRecordsRecentPictures()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString one = dir.filePath(QStringLiteral("one.jpg"));
        const QString two = dir.filePath(QStringLiteral("two.jpg"));
        const QString three = dir.filePath(QStringLiteral("three.jpg"));
        for (const QString &picture : { one, two, three }) {
            writeFile(picture, "picture");
        }
        const QString state = dir.filePath(QStringLiteral("state/recent-backgrounds"));
        QDir().mkpath(dir.filePath(QStringLiteral("state")));
        // A picture since deleted is left out.
        writeFile(state, (one + QStringLiteral("\n/gone/picture.jpg\n") + two + QStringLiteral("\n")).toUtf8());

        FakeShell shell;
        shell.answer = QStringLiteral(R"({"image":"%1","fillMode":3})").arg(QUrl::fromLocalFile(one).toString());
        DesktopBackground background(shell.runner(), state);
        QVERIFY(background.available());
        QCOMPARE(background.image(), one);
        QCOMPARE(background.fillMode(), 3);
        QCOMPARE(background.recent(), (QStringList { one, two }));

        // Choosing a picture puts it first, in the list and the file, and sets it on the desktop.
        background.setImage(QUrl::fromLocalFile(three).toString());
        QCOMPARE(background.recent(), (QStringList { three, one, two }));
        QFile file(state);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(QString::fromUtf8(file.readAll()), three + QLatin1Char('\n') + one + QLatin1Char('\n') + two + QLatin1Char('\n'));
        QVERIFY(shell.scripts.join(QString()).contains(QUrl::fromLocalFile(three).toString()));

        // A picture chosen from the desktop's menu, written by recent-backgrounds, shows up.
        QSignalSpy changed(&background, &DesktopBackground::recentChanged);
        file.close();
        writeFile(state, (two + QLatin1Char('\n') + three + QLatin1Char('\n')).toUtf8());
        QVERIFY(changed.wait(2000));
        QCOMPARE(background.recent(), (QStringList { two, three }));
    }

    void startsWithThePictureInUse()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString picture = dir.filePath(QStringLiteral("now.jpg"));
        writeFile(picture, "picture");
        FakeShell shell;
        shell.answer = QStringLiteral(R"({"image":"%1","fillMode":2})").arg(picture);
        DesktopBackground background(shell.runner(), dir.filePath(QStringLiteral("none/recent-backgrounds")));
        QVERIFY(!background.recent().isEmpty());
        QCOMPARE(background.recent().first(), picture);
    }

    void saysWhenTheDesktopDoesntAnswer()
    {
        QTemporaryDir dir;
        DesktopBackground background(
            [](const QString &, std::function<void(bool, const QString &)> done) { done(false, QStringLiteral("org.kde.plasmashell isn't running")); },
            dir.filePath(QStringLiteral("recent-backgrounds")));
        QVERIFY(!background.available());
    }
};

QTEST_MAIN(DesktopBackgroundTest)

#include "desktopbackgroundtest.moc"
