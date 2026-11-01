// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Windows + .: the emoji panel. Picking an emoji, kaomoji, symbol or clipboard item copies it and
// closes the panel; a second Windows + . while it shows brings the same panel forward.

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

    KAboutData about(QStringLiteral("orielos-emoji"), i18nc("@title", "Emoji Panel"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Copy emoji, kaomoji, symbols and recent clipboard items"), KAboutLicense::GPL_V3);
    about.setDesktopFileName(QStringLiteral("org.orielos.EmojiPanel"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);

    KDBusService service(KDBusService::Unique);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("org.orielos.emojipanel", "Main");

    QObject::connect(&service, &KDBusService::activateRequested, &app, [&engine]() {
        if (!engine.rootObjects().isEmpty()) {
            if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
                window->requestActivate();
            }
        }
    });

    return QGuiApplication::exec();
}
