// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "osrelease.h"

#include <KAboutData>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QStringList>
#include <QTimer>
#include <QWindow>

#include <cstdio>
#include <cstring>

namespace {

constexpr char selfTestOption[] = "--self-test";

QStringList s_problems;
QtMessageHandler s_defaultHandler = nullptr;

// Records every warning, critical and fatal message while the self-test loads the QML,
// and still prints it.
void recordProblem(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (type != QtDebugMsg && type != QtInfoMsg) {
        s_problems.append(qFormatLogMessage(type, context, message));
    }
    s_defaultHandler(type, context, message);
}

// The option has to be known before the application object exists, so look for it directly.
bool wantsSelfTest(int argc, char **argv)
{
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], selfTestOption) == 0) {
            return true;
        }
    }
    return false;
}

// Loads the main window off screen, lets it settle, and reports whether it loaded cleanly.
int runSelfTest(QGuiApplication &app, QQmlApplicationEngine &engine)
{
    s_defaultHandler = qInstallMessageHandler(recordProblem);
    engine.loadFromModule("org.orielos.buildcheck", "Main");
    if (!engine.rootObjects().isEmpty()) {
        QTimer::singleShot(500, &app, &QCoreApplication::quit);
        app.exec();
    }
    qInstallMessageHandler(s_defaultHandler);

    if (engine.rootObjects().isEmpty()) {
        s_problems.append(QStringLiteral("the main window was not created"));
    }
    if (!s_problems.isEmpty()) {
        std::fprintf(stderr, "orielos-buildcheck: self-test failed\n");
        for (const QString &problem : std::as_const(s_problems)) {
            std::fprintf(stderr, "  %s\n", qUtf8Printable(problem));
        }
        return 1;
    }
    std::printf("orielos-buildcheck: self-test passed (%s)\n", qUtf8Printable(OrielOS::OsRelease::fromSystem().prettyName()));
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    const bool selfTest = wantsSelfTest(argc, argv);
    if (selfTest && !qEnvironmentVariableIsSet("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", "offscreen");
    }

    QGuiApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-buildcheck"), i18nc("@title", "OrielOS Build Check"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Checks that OrielOS apps build, install and start."), KAboutLicense::GPL_V3, i18nc("@info:credit", "© 2026 OrielOS contributors"));
    about.setDesktopFileName(QStringLiteral("org.orielos.BuildCheck"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.addOption(QCommandLineOption(
        QString::fromLatin1(selfTestOption + 2), i18nc("@info:shell", "Load the main window off screen, report any QML warnings or errors, and exit.")));
    parser.process(app);
    about.processCommandLine(&parser);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);

    if (selfTest) {
        return runSelfTest(app, engine);
    }

    engine.loadFromModule("org.orielos.buildcheck", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst())) {
        window->show();
    }
    return app.exec();
}
