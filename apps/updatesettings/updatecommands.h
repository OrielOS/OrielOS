// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace OrielOSUpdates {

// Runs orielos-update commands for the Update settings page. The unit tests replace it.
class CommandRunner : public QObject
{
    Q_OBJECT

public:
    enum class Outcome {
        Succeeded,
        // The password prompt was dismissed, or the user isn't allowed: nothing to report.
        Cancelled,
        Failed,
    };
    Q_ENUM(Outcome)

    using QObject::QObject;

    // Runs "orielos-update <arguments>"; finished() follows once for every call.
    virtual void run(const QStringList &arguments) = 0;

Q_SIGNALS:
    // detail is orielos-update's reason when it failed.
    void finished(const QStringList &arguments, OrielOSUpdates::CommandRunner::Outcome outcome, const QString &detail);
};

// Runs pkexec /usr/bin/orielos-update <arguments>, where polkit decides who may and asks for a
// password when it needs one.
class PkexecRunner : public CommandRunner
{
    Q_OBJECT

public:
    using CommandRunner::CommandRunner;
    ~PkexecRunner() override;

    void run(const QStringList &arguments) override;
};

// Says whether the update check, orielos-update-check.service, is running. The unit tests replace
// it.
class CheckMonitor : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    virtual bool isRunning() const = 0;

Q_SIGNALS:
    void runningChanged();
};

// Follows the check unit's state from systemd over the system bus. Without a system bus or systemd
// the check never counts as running.
class SystemdCheckMonitor : public CheckMonitor
{
    Q_OBJECT

public:
    explicit SystemdCheckMonitor(QObject *parent = nullptr);
    ~SystemdCheckMonitor() override;

    bool isRunning() const override { return m_running; }

private Q_SLOTS:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void readActiveState();
    void setActiveState(const QString &state);

    QDBusConnection m_bus;
    QString m_unitPath;
    bool m_subscribed = false;
    bool m_running = false;
};

} // namespace OrielOSUpdates
