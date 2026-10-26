// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatecommands.h"

#include <KLocalizedString>

#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QProcess>

namespace OrielOSUpdates {

namespace {

constexpr auto updateTool = "/usr/bin/orielos-update";
// pkexec exits with these when the password prompt is dismissed or the user isn't allowed.
constexpr int pkexecDismissed = 126;
constexpr int pkexecNotAuthorised = 127;
// How long closing the page waits for a running command, in milliseconds.
constexpr int commandWaitOnClose = 5 * 60 * 1000;

constexpr auto systemdService = "org.freedesktop.systemd1";
constexpr auto systemdPath = "/org/freedesktop/systemd1";
constexpr auto managerInterface = "org.freedesktop.systemd1.Manager";
constexpr auto unitInterface = "org.freedesktop.systemd1.Unit";
constexpr auto propertiesInterface = "org.freedesktop.DBus.Properties";
constexpr auto checkUnit = "orielos-update-check.service";
constexpr auto activeState = "ActiveState";

QDBusMessage managerCall(const char *method)
{
    return QDBusMessage::createMethodCall(QLatin1String(systemdService), QLatin1String(systemdPath), QLatin1String(managerInterface), QLatin1String(method));
}

} // namespace

PkexecRunner::~PkexecRunner()
{
    // A command that has started finishes even when the page closes: QProcess would kill
    // orielos-update halfway through going back or removing a build. Only an unanswered password
    // prompt can take long, so the wait has a limit.
    const QList<QProcess *> processes = findChildren<QProcess *>(Qt::FindDirectChildrenOnly);
    for (QProcess *process : processes) {
        process->disconnect(this);
        process->waitForFinished(commandWaitOnClose);
    }
}

void PkexecRunner::run(const QStringList &arguments)
{
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("pkexec"));
    process->setArguments(QStringList { QLatin1String(updateTool) } + arguments);
    connect(process, &QProcess::finished, this, [this, process, arguments](int exitCode, QProcess::ExitStatus status) {
        process->deleteLater();
        if (status == QProcess::NormalExit && exitCode == 0) {
            Q_EMIT finished(arguments, Outcome::Succeeded, QString());
        } else if (status == QProcess::NormalExit && (exitCode == pkexecDismissed || exitCode == pkexecNotAuthorised)) {
            Q_EMIT finished(arguments, Outcome::Cancelled, QString());
        } else {
            const QString detail = QString::fromLocal8Bit(process->readAllStandardError()).section(QLatin1Char('\n'), 0, 0).trimmed();
            Q_EMIT finished(arguments, Outcome::Failed, detail);
        }
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, arguments](QProcess::ProcessError error) {
        // Other errors end in finished() above.
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            Q_EMIT finished(arguments, Outcome::Failed, i18nc("@info", "pkexec couldn't be started."));
        }
    });
    process->start();
}

SystemdCheckMonitor::SystemdCheckMonitor(QObject *parent)
    : CheckMonitor(parent)
    , m_bus(QDBusConnection::systemBus())
{
    if (!m_bus.isConnected()) {
        return;
    }
    // systemd sends a unit's PropertiesChanged signals only while some client is subscribed.
    m_bus.send(managerCall("Subscribe"));
    m_subscribed = true;

    QDBusMessage load = managerCall("LoadUnit");
    load << QLatin1String(checkUnit);
    auto *call = new QDBusPendingCallWatcher(m_bus.asyncCall(load), this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        const QDBusPendingReply<QDBusObjectPath> reply = *watcher;
        if (reply.isError()) {
            return;
        }
        m_unitPath = reply.value().path();
        m_bus.connect(QLatin1String(systemdService), m_unitPath, QLatin1String(propertiesInterface), QStringLiteral("PropertiesChanged"), this,
            SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
        readActiveState();
    });
}

SystemdCheckMonitor::~SystemdCheckMonitor()
{
    if (m_subscribed) {
        m_bus.send(managerCall("Unsubscribe"));
    }
}

void SystemdCheckMonitor::onPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    if (interface != QLatin1String(unitInterface)) {
        return;
    }
    if (changed.contains(QLatin1String(activeState))) {
        setActiveState(changed.value(QLatin1String(activeState)).toString());
    } else if (invalidated.contains(QLatin1String(activeState))) {
        readActiveState();
    }
}

void SystemdCheckMonitor::readActiveState()
{
    QDBusMessage get = QDBusMessage::createMethodCall(QLatin1String(systemdService), m_unitPath, QLatin1String(propertiesInterface), QStringLiteral("Get"));
    get << QLatin1String(unitInterface) << QLatin1String(activeState);
    auto *call = new QDBusPendingCallWatcher(m_bus.asyncCall(get), this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        const QDBusPendingReply<QDBusVariant> reply = *watcher;
        if (!reply.isError()) {
            setActiveState(reply.value().variant().toString());
        }
    });
}

void SystemdCheckMonitor::setActiveState(const QString &state)
{
    // The check is a oneshot service, which stays "activating" while it runs.
    const bool running = state == QLatin1String("activating") || state == QLatin1String("deactivating");
    if (running != m_running) {
        m_running = running;
        Q_EMIT runningChanged();
    }
}

} // namespace OrielOSUpdates
