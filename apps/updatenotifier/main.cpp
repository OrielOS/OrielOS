// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatenotifier.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedString>

#include <QApplication>
#include <QCommandLineParser>

int main(int argc, char *argv[])
{
    // QApplication rather than QGuiApplication: the tray icon's menu is a QMenu.
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-update-notifier"), i18nc("@title", "OrielOS updates"), QStringLiteral(ORIELOS_VERSION_STRING),
        i18nc("@info", "Tells you when an OrielOS update is ready or was undone, and opens the update settings."), KAboutLicense::GPL_V3,
        i18nc("@info:credit", "© 2026 OrielOS contributors"));
    about.setDesktopFileName(QStringLiteral("org.orielos.UpdateNotifier"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    const QCommandLineOption stateOption(QStringLiteral("state"), i18nc("@info:shell", "Read the update state from <file>."), QStringLiteral("file"),
        QStringLiteral("/var/lib/orielos/update/state.json"));
    const QCommandLineOption bootIdOption(QStringLiteral("boot-id-file"), i18nc("@info:shell", "Read this boot's ID from <file>."), QStringLiteral("file"),
        QStringLiteral("/proc/sys/kernel/random/boot_id"));
    parser.addOption(stateOption);
    parser.addOption(bootIdOption);
    parser.process(app);
    about.processCommandLine(&parser);

    // One notifier per session: a second start, for example from autostart after a crash
    // restart, just exits.
    KDBusService service(KDBusService::Unique);

    UpdateNotifier::Notifier notifier(parser.value(stateOption), parser.value(bootIdOption));
    return app.exec();
}
