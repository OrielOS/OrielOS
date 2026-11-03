// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "resetpc.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QPointer>
#include <QProcess>

#include <algorithm>

namespace OrielOSSettingsPages {

namespace {

constexpr auto resetTool = "/usr/bin/orielos-reset";
// pkexec exits with these when the password prompt is dismissed or the user isn't allowed.
constexpr int pkexecDismissed = 126;
constexpr int pkexecNotAuthorised = 127;

ResetState::Phase phaseFrom(const QString &name)
{
    using Phase = ResetState::Phase;
    if (name == QLatin1String("checking")) {
        return Phase::Checking;
    }
    if (name == QLatin1String("downloading")) {
        return Phase::Downloading;
    }
    if (name == QLatin1String("preparing")) {
        return Phase::Preparing;
    }
    if (name == QLatin1String("ready")) {
        return Phase::Ready;
    }
    if (name == QLatin1String("failed")) {
        return Phase::Failed;
    }
    if (name == QLatin1String("cancelled")) {
        return Phase::Cancelled;
    }
    if (name == QLatin1String("done")) {
        return Phase::Done;
    }
    return Phase::Idle;
}

QString readBootId(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromLatin1(file.readAll()).trimmed();
}

// pkexec /usr/bin/orielos-reset <arguments>, where polkit decides who may and asks for a password.
void runPkexec(const QStringList &arguments, std::function<void(int exitCode, const QString &detail)> done)
{
    auto *process = new QProcess;
    QObject::connect(process, &QProcess::finished, process, [process, done](int exitCode, QProcess::ExitStatus status) {
        const QString detail = QString::fromLocal8Bit(process->readAllStandardError()).section(QLatin1Char('\n'), 0, 0).trimmed();
        process->deleteLater();
        done(status == QProcess::NormalExit ? exitCode : 1, detail);
    });
    QObject::connect(process, &QProcess::errorOccurred, process, [process, done](QProcess::ProcessError error) {
        // Other errors end in finished() above.
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            done(1, i18nc("@info", "pkexec couldn't be started."));
        }
    });
    process->start(QStringLiteral("pkexec"), QStringList { QLatin1String(resetTool) } + arguments);
}

// Plasma signs out cleanly, saving the session, then restarts into the reset.
void logoutAndReboot()
{
    const QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), QStringLiteral("logoutAndReboot"));
    QDBusConnection::sessionBus().asyncCall(message);
}

} // namespace

ResetState ResetState::parse(const QByteArray &json)
{
    const QJsonObject object = QJsonDocument::fromJson(json).object();
    ResetState state;
    state.phase = phaseFrom(object.value(QStringLiteral("phase")).toString());
    state.message = object.value(QStringLiteral("message")).toString();
    state.mode = object.value(QStringLiteral("mode")).toString();
    state.version = object.value(QStringLiteral("version")).toString();
    state.downloaded = object.value(QStringLiteral("downloaded")).toInteger();
    state.total = object.value(QStringLiteral("total")).toInteger();
    state.bootId = object.value(QStringLiteral("bootId")).toString();
    return state;
}

ResetPC::ResetPC(QObject *parent)
    : ResetPC(Environment { QStringLiteral("/var/lib/orielos/reset/state.json"), QStringLiteral("/proc/sys/kernel/random/boot_id"), runPkexec,
                  logoutAndReboot },
          parent)
{
}

ResetPC::ResetPC(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    init();
}

void ResetPC::init()
{
    m_bootId = readBootId(m_environment.bootIdPath);
    // orielos-reset replaces the file in one step, which drops it from the watch list, so the
    // folder is watched too and the file is added back after every change.
    m_reloadDelay.setSingleShot(true);
    m_reloadDelay.setInterval(200);
    connect(&m_reloadDelay, &QTimer::timeout, this, &ResetPC::reload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reloadDelay, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reloadDelay, qOverload<>(&QTimer::start));
    m_pollWhileWorking.setInterval(1000);
    connect(&m_pollWhileWorking, &QTimer::timeout, this, &ResetPC::reload);
    reload();
}

void ResetPC::reload()
{
    const QFileInfo info(m_environment.statePath);
    if (!m_watcher.directories().contains(info.absolutePath()) && info.dir().exists()) {
        m_watcher.addPath(info.absolutePath());
    }
    QFile file(m_environment.statePath);
    if (file.open(QIODevice::ReadOnly)) {
        m_state = ResetState::parse(file.readAll());
        if (!m_watcher.files().contains(m_environment.statePath)) {
            m_watcher.addPath(m_environment.statePath);
        }
    } else {
        m_state = ResetState { };
    }
    if (isWorking()) {
        m_pollWhileWorking.start();
    } else {
        m_pollWhileWorking.stop();
    }
    Q_EMIT changed();
}

bool ResetPC::isCurrent() const
{
    return !m_state.bootId.isEmpty() && m_state.bootId == m_bootId;
}

bool ResetPC::isWorking() const
{
    using Phase = ResetState::Phase;
    return isCurrent() && (m_state.phase == Phase::Checking || m_state.phase == Phase::Downloading || m_state.phase == Phase::Preparing);
}

bool ResetPC::isReady() const
{
    return isCurrent() && m_state.phase == ResetState::Phase::Ready;
}

QString ResetPC::status() const
{
    using Phase = ResetState::Phase;
    const QString version = m_state.version.isEmpty() ? i18nc("@info the version of OrielOS isn't known", "the newest version") : m_state.version;
    if (!isCurrent()) {
        return { };
    }
    switch (m_state.phase) {
    case Phase::Checking:
        return i18nc("@info", "Finding the newest version of OrielOS…");
    case Phase::Downloading:
        return i18nc("@info %1 is a version, such as v0.3.0", "Downloading OrielOS %1…", version);
    case Phase::Preparing:
        return i18nc("@info %1 is a version, such as v0.3.0", "Getting OrielOS %1 ready. This takes a few minutes.", version);
    case Phase::Ready:
        return keepsFiles() ? i18nc("@info %1 is a version, such as v0.3.0",
                                  "OrielOS %1 is ready. Restart to reset this PC. Accounts and their files stay; the restart takes a few minutes longer than usual.",
                                  version)
                            : i18nc("@info %1 is a version, such as v0.3.0",
                                  "OrielOS %1 is ready. Restart to reset this PC and remove every account and file on it. It then starts with first-run setup.",
                                  version);
    default:
        return { };
    }
}

double ResetPC::progress() const
{
    if (m_state.phase != ResetState::Phase::Downloading || m_state.total <= 0) {
        return -1;
    }
    return std::clamp(double(m_state.downloaded) / double(m_state.total), 0.0, 1.0);
}

QString ResetPC::progressText() const
{
    if (!isCurrent() || m_state.phase != ResetState::Phase::Downloading || m_state.total <= 0) {
        return { };
    }
    const QLocale locale;
    return i18nc("@info %1 and %2 are sizes, such as 1.2 GB", "%1 of %2", locale.formattedDataSize(m_state.downloaded, 1, QLocale::DataSizeSIFormat),
        locale.formattedDataSize(m_state.total, 1, QLocale::DataSizeSIFormat));
}

QString ResetPC::outcome() const
{
    using Phase = ResetState::Phase;
    if (!isCurrent()) {
        return { };
    }
    switch (m_state.phase) {
    case Phase::Failed:
        return m_state.message.isEmpty() ? i18nc("@info", "The reset couldn't be got ready. Nothing was changed.") : m_state.message;
    case Phase::Cancelled:
        return i18nc("@info", "The reset was cancelled. Nothing was changed.");
    case Phase::Done:
        return m_state.version.isEmpty() ? i18nc("@info", "This PC was reset.")
                                         : i18nc("@info %1 is a version, such as v0.3.0", "This PC was reset to OrielOS %1.", m_state.version);
    default:
        return { };
    }
}

bool ResetPC::outcomeIsError() const
{
    return isCurrent() && m_state.phase == ResetState::Phase::Failed;
}

void ResetPC::run(const QStringList &arguments)
{
    m_busy = true;
    m_error.clear();
    Q_EMIT changed();
    // The command goes on if the page closes meanwhile: cancelling must never stop halfway.
    m_environment.run(arguments, [self = QPointer<ResetPC>(this), command = arguments.value(0)](int exitCode, const QString &detail) {
        if (!self) {
            return;
        }
        self->onFinished(command, exitCode, detail);
    });
}

void ResetPC::onFinished(const QString &command, int exitCode, const QString &detail)
{
    m_busy = false;
    if (exitCode != 0 && exitCode != pkexecDismissed && exitCode != pkexecNotAuthorised) {
        const QString reason = detail.isEmpty() ? i18nc("@info", "orielos-reset stopped with an error.") : detail;
        m_error = command == QLatin1String("cancel") ? i18nc("@info %1 is the reason", "Couldn't cancel the reset: %1", reason)
                                                     : i18nc("@info %1 is the reason", "Couldn't start the reset: %1", reason);
    }
    // orielos-reset has written the state by now; don't wait for the file watcher.
    reload();
}

void ResetPC::reset(bool keepFiles)
{
    if (m_busy || isWorking() || isReady()) {
        return;
    }
    run({ QStringLiteral("start"), keepFiles ? QStringLiteral("keep") : QStringLiteral("erase") });
}

void ResetPC::cancel()
{
    if (m_busy || (!isWorking() && !isReady())) {
        return;
    }
    run({ QStringLiteral("cancel") });
}

void ResetPC::restart()
{
    if (isReady() && m_environment.restart) {
        m_environment.restart();
    }
}

} // namespace OrielOSSettingsPages
