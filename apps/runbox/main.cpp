// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Windows + R: the Run box. Typing a program, folder, document or website opens it; a second
// Windows + R while it shows brings the same box forward.

#include "osrelease.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QWindow>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-run"), i18nc("@title", "Run"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Open a program, folder, document or website by typing its name"), KAboutLicense::GPL_V3);
    about.setDesktopFileName(QStringLiteral("org.orielos.Run"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);

    KDBusService service(KDBusService::Unique);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("org.orielos.runbox", "Main");

    QObject::connect(&service, &KDBusService::activateRequested, &app, [&engine]() {
        if (!engine.rootObjects().isEmpty()) {
            if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
                window->requestActivate();
            }
        }
    });

    return QGuiApplication::exec();
}
