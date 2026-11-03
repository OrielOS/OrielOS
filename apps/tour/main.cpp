// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Set up this PC: a short tour after an account's first sign-in that changes the settings people
// usually want to change on the spot. first-sign-in opens it once; Start › All apps opens it again.
// --self-test loads the window without showing it and says whether that worked, for the tests.

#include "osrelease.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QApplication>
#include <QCommandLineParser>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QWindow>
#include <QtQml/qqmlextensionplugin.h>

#include <cstdio>

// The pages' models from Settings: the taskbar's, the update channel's and the Store's apps.
Q_IMPORT_QML_PLUGIN(org_orielos_taskbarPlugin)
Q_IMPORT_QML_PLUGIN(org_orielos_updatesettingsPlugin)
Q_IMPORT_QML_PLUGIN(org_orielos_accessoriesPlugin)

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-tour"), i18nc("@title", "Set up this PC"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "A few choices after the first sign-in"), KAboutLicense::GPL_V3, i18nc("@info:credit", "© 2026 OrielOS contributors"));
    about.setHomepage(QStringLiteral("https://orielos.org"));
    about.setDesktopFileName(QStringLiteral("org.orielos.Tour"));
    KAboutData::setApplicationData(about);
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("preferences-desktop")));

    QCommandLineParser parser;
    const QCommandLineOption selfTest(QStringLiteral("self-test"), i18nc("@info:shell", "Load the window off screen, report and quit."));
    parser.addOption(selfTest);
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);

    if (parser.isSet(selfTest)) {
        engine.loadFromModule("org.orielos.tour", "Main");
        if (engine.rootObjects().isEmpty()) {
            std::fprintf(stderr, "orielos-tour: the window couldn't be loaded\n");
            return 1;
        }
        std::printf("orielos-tour: self-test passed\n");
        return 0;
    }

    // One window: opening it again from Start while it's open brings it forward.
    KDBusService service(KDBusService::Unique);

    engine.loadFromModule("org.orielos.tour", "Main");
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
