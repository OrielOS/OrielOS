// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The network troubleshooter: checks each part of the network connection in turn, from the network
// adapter to the internet, and fixes the first problem it finds. Quick Settings' menu on the
// taskbar opens it, and so does Start. --self-test loads the window without showing it and says
// whether that worked, for the tests.

#include "osrelease.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QWindow>

#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-network-troubleshooter"), i18nc("@title", "Network troubleshooter"),
        OrielOS::OsRelease::fromSystem().imageVersion(), i18nc("@info", "Find and fix network problems"), KAboutLicense::GPL_V3,
        i18nc("@info:credit", "© 2026 OrielOS contributors"));
    about.setHomepage(QStringLiteral("https://orielos.org"));
    about.setDesktopFileName(QStringLiteral("org.orielos.NetworkTroubleshooter"));
    KAboutData::setApplicationData(about);
    QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("network-wireless")));

    QCommandLineParser parser;
    const QCommandLineOption selfTest(QStringLiteral("self-test"), i18nc("@info:shell", "Load the window off screen, report and quit."));
    parser.addOption(selfTest);
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);

    if (parser.isSet(selfTest)) {
        engine.loadFromModule("org.orielos.networktroubleshooter", "Main");
        if (engine.rootObjects().isEmpty()) {
            std::fprintf(stderr, "orielos-network-troubleshooter: the window couldn't be loaded\n");
            return 1;
        }
        std::printf("orielos-network-troubleshooter: self-test passed\n");
        return 0;
    }

    // One window: opening it again while it's open brings it forward.
    KDBusService service(KDBusService::Unique);

    engine.loadFromModule("org.orielos.networktroubleshooter", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    if (window) {
        QObject::connect(&service, &KDBusService::activateRequested, window, [window]() {
            window->show();
            window->requestActivate();
        });
        window->show();
    }
    return app.exec();
}
