// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "privacysettings.h"

#include <KLocalizedString>

PrivacySettings::PrivacySettings(QObject *parent)
    : QObject(parent)
    , m_program(QStringLiteral("pkexec"))
    , m_arguments { QStringLiteral("/usr/libexec/orielos/first-run-privacy") }
{
}

PrivacySettings::~PrivacySettings()
{
    // The helper writes one small file; let it finish rather than leave it half done.
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->waitForFinished(5000);
    }
}

void PrivacySettings::setLocation(bool on)
{
    if (on != m_location) {
        m_location = on;
        Q_EMIT settingsChanged();
    }
}

void PrivacySettings::save()
{
    if (m_process) {
        m_saveAgain = true;
        return;
    }
    if (m_location == m_lastSaved) {
        return;
    }
    m_running = m_location;
    m_process = new QProcess(this);
    connect(
        m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) { finish(status == QProcess::NormalExit && exitCode == 0); });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(false);
        }
    });
    m_process->start(m_program, m_arguments + QStringList { QStringLiteral("location"), m_running ? QStringLiteral("on") : QStringLiteral("off") });
    Q_EMIT savingChanged();
}

void PrivacySettings::finish(bool ok)
{
    m_process->deleteLater();
    m_process = nullptr;
    if (ok) {
        m_lastSaved = m_running;
        m_error.clear();
    } else {
        m_error = i18nc("@info", "The location setting couldn't be saved.");
    }
    Q_EMIT errorChanged();
    Q_EMIT savingChanged();
    Q_EMIT saved(ok);
    if (m_saveAgain) {
        m_saveAgain = false;
        save();
    }
}

void PrivacySettings::setCommandForTesting(const QString &program, const QStringList &arguments)
{
    m_program = program;
    m_arguments = arguments;
}
