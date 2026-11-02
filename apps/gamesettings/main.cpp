// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Game Settings: the games in Steam from the Store, each with its compatibility tool and switches.
// --self-test loads the window without showing it and says whether that worked, for the tests.

#include <KAboutData>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QApplication>
#include <QCommandLineParser>
#include <QIcon>
#include <QQmlApplicationEngine>

#include <cstdio>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("orielos-game-settings");
    KAboutData about(QStringLiteral("orielos-game-settings"), i18nc("@title", "Game Settings"), QStringLiteral("1.0"),
        i18nc("@info", "Settings for each game in Steam"), KAboutLicense::GPL_V3);
    about.setDesktopFileName(QStringLiteral("org.orielos.GameSettings"));
    KAboutData::setApplicationData(about);
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("input-gaming")));

    QCommandLineParser parser;
    const QCommandLineOption selfTest(QStringLiteral("self-test"), QStringLiteral("Load the window, report and quit"));
    parser.addOption(selfTest);
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    engine.loadFromModule("org.orielos.gamesettings", "Main");
    if (engine.rootObjects().isEmpty()) {
        std::fprintf(stderr, "orielos-game-settings: the window couldn't be loaded\n");
        return 1;
    }
    if (parser.isSet(selfTest)) {
        std::printf("orielos-game-settings: self-test passed\n");
        return 0;
    }
    return app.exec();
}
