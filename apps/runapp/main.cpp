// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Run this app: opens a Windows program (.exe or .msi) the user double-clicked, asks first, then
// runs it through umu-launcher with GE-Proton in its own prefix. Start entries it makes run
// "orielos-run-app --launch NAME PATH [ARGUMENTS...]", which starts the program with no window.

#include "osrelease.h"
#include "runapp.h"
#include "runner.h"

#include <KAboutData>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QStandardPaths>
#include <QStringList>
#include <QTemporaryDir>
#include <QTimer>
#include <QWindow>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <unistd.h>
#include <vector>

namespace {

constexpr char launchOption[] = "--launch";
constexpr char selfTestOption[] = "--self-test";

QStringList s_problems;
QtMessageHandler s_defaultHandler = nullptr;

// Records every warning, critical and fatal message while the self-test loads the QML, and still
// prints it.
void recordProblem(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (type != QtDebugMsg && type != QtInfoMsg) {
        s_problems.append(qFormatLogMessage(type, context, message));
    }
    s_defaultHandler(type, context, message);
}

// The options that need no window have to be known before the application object exists.
bool hasOption(int argc, char **argv, const char *option)
{
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], option) == 0) {
            return true;
        }
    }
    return false;
}

QString stateHome()
{
    const QString state = qEnvironmentVariable("XDG_STATE_HOME");
    return state.isEmpty() ? QDir::home().filePath(QStringLiteral(".local/state")) : state;
}

// --launch NAME PATH [ARGUMENTS...]: replaces this process with umu-launcher running the program
// in NAME's prefix, so the Start entry's program is the one that runs.
int launch(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QStringList arguments = app.arguments().mid(1);
    arguments.removeOne(QString::fromLatin1(launchOption));
    if (arguments.size() < 2) {
        std::fprintf(stderr, "orielos-run-app: --launch needs a prefix name and a program\n");
        return 2;
    }
    const QString name = arguments.takeFirst();
    const QString program = arguments.takeFirst();
    const QString dataHome = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    const OrielOSRunApp::Command cmd = OrielOSRunApp::command(OrielOSRunApp::prefixDir(dataHome, name), program, arguments);
    for (auto it = cmd.environment.cbegin(); it != cmd.environment.cend(); ++it) {
        qputenv(it.key().toUtf8().constData(), it.value().toUtf8());
    }
    std::vector<QByteArray> storage;
    storage.push_back(QFile::encodeName(cmd.program));
    for (const QString &argument : cmd.arguments) {
        storage.push_back(argument.toUtf8());
    }
    std::vector<char *> execArgs;
    for (QByteArray &item : storage) {
        execArgs.push_back(item.data());
    }
    execArgs.push_back(nullptr);
    ::execvp(execArgs.front(), execArgs.data());
    std::fprintf(stderr, "orielos-run-app: can't start %s: %s\n", execArgs.front(), std::strerror(errno));
    return 127;
}

// Loads the window off screen for a made-up download, lets it settle, and reports whether it
// loaded cleanly.
int runSelfTest(QGuiApplication &app, QQmlApplicationEngine &engine)
{
    const QTemporaryDir dir;
    const QString file = QDir(dir.path()).filePath(QStringLiteral("ExampleSetup.exe"));
    QFile example(file);
    if (!example.open(QIODevice::WriteOnly)) {
        std::fprintf(stderr, "orielos-run-app: self-test can't make an example file\n");
        return 1;
    }
    example.close();
    Runner runner(file, dir.path(), dir.path(), dir.path());

    s_defaultHandler = qInstallMessageHandler(recordProblem);
    engine.setInitialProperties({ { QStringLiteral("runner"), QVariant::fromValue(&runner) } });
    engine.loadFromModule("org.orielos.runapp", "Main");
    if (!engine.rootObjects().isEmpty()) {
        QTimer::singleShot(500, &app, &QCoreApplication::quit);
        app.exec();
    }
    qInstallMessageHandler(s_defaultHandler);

    if (engine.rootObjects().isEmpty()) {
        s_problems.append(QStringLiteral("the window was not created"));
    }
    if (!s_problems.isEmpty()) {
        std::fprintf(stderr, "orielos-run-app: self-test failed\n");
        for (const QString &problem : std::as_const(s_problems)) {
            std::fprintf(stderr, "  %s\n", qUtf8Printable(problem));
        }
        return 1;
    }
    std::printf("orielos-run-app: self-test passed (%s)\n", qUtf8Printable(OrielOS::OsRelease::fromSystem().prettyName()));
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    if (hasOption(argc, argv, launchOption)) {
        return launch(argc, argv);
    }
    const bool selfTest = hasOption(argc, argv, selfTestOption);
    if (selfTest && !qEnvironmentVariableIsSet("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", "offscreen");
    }

    QGuiApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-run-app"), i18nc("@title", "Run this app"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Runs Windows programs."), KAboutLicense::GPL_V3, i18nc("@info:credit", "© 2026 OrielOS contributors"));
    about.setHomepage(QStringLiteral("https://orielos.org"));
    about.setDesktopFileName(QStringLiteral("org.orielos.RunApp"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.addPositionalArgument(QStringLiteral("file"), i18nc("@info:shell", "The Windows program (.exe or .msi) to run."));
    parser.addOption(QCommandLineOption(QString::fromLatin1(launchOption + 2),
        i18nc("@info:shell", "Start a program a Start entry points to, with no window: --launch NAME PATH [ARGUMENTS...].")));
    parser.addOption(QCommandLineOption(
        QString::fromLatin1(selfTestOption + 2), i18nc("@info:shell", "Load the window off screen, report any QML warnings or errors, and exit.")));
    parser.process(app);
    about.processCommandLine(&parser);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);

    if (selfTest) {
        return runSelfTest(app, engine);
    }
    const QStringList files = parser.positionalArguments();
    if (files.size() != 1) {
        parser.showHelp(2);
    }

    Runner runner(files.constFirst(), QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation), stateHome(),
        QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation));
    engine.setInitialProperties({ { QStringLiteral("runner"), QVariant::fromValue(&runner) } });
    engine.loadFromModule("org.orielos.runapp", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().constFirst())) {
        window->show();
    }
    return app.exec();
}
