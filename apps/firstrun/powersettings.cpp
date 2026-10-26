// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "powersettings.h"

#include <KLocalizedString>

#include <algorithm>

namespace {
QVariantMap choice(const QString &text, int minutes)
{
    return { { QStringLiteral("text"), text }, { QStringLiteral("minutes"), minutes } };
}

QString duration(int minutes)
{
    if (minutes % 60 == 0) {
        return i18ncp("@item:inlistbox", "%1 hour", "%1 hours", minutes / 60);
    }
    return i18ncp("@item:inlistbox", "%1 minute", "%1 minutes", minutes);
}
} // namespace

PowerSettings::PowerSettings(QObject *parent)
    : QObject(parent)
    , m_program(QStringLiteral("pkexec"))
    , m_arguments { QStringLiteral("/usr/libexec/orielos/first-run-power") }
{
    m_lastSaved = helperArguments();
}

PowerSettings::~PowerSettings()
{
    // The helper only writes a few settings; let it finish rather than leave the file half done.
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->waitForFinished(5000);
    }
}

bool PowerSettings::sleepWhenIdle() const
{
    return m_sleepWhenIdle;
}

void PowerSettings::setSleepWhenIdle(bool sleep)
{
    if (sleep != m_sleepWhenIdle) {
        m_sleepWhenIdle = sleep;
        Q_EMIT settingsChanged();
    }
}

int PowerSettings::sleepAfterMinutes() const
{
    return m_sleepAfterMinutes;
}

void PowerSettings::setSleepAfterMinutes(int minutes)
{
    minutes = std::clamp(minutes, 1, maxMinutes);
    if (minutes != m_sleepAfterMinutes) {
        m_sleepAfterMinutes = minutes;
        Q_EMIT settingsChanged();
    }
}

int PowerSettings::screenOffAfterMinutes() const
{
    return m_screenOffAfterMinutes;
}

void PowerSettings::setScreenOffAfterMinutes(int minutes)
{
    minutes = std::clamp(minutes, 0, maxMinutes);
    if (minutes != m_screenOffAfterMinutes) {
        m_screenOffAfterMinutes = minutes;
        Q_EMIT settingsChanged();
    }
}

QVariantList PowerSettings::sleepChoices() const
{
    QVariantList choices;
    for (int minutes : { 5, 10, 15, 30, 60, 120 }) {
        choices.append(choice(duration(minutes), minutes));
    }
    return choices;
}

QVariantList PowerSettings::screenOffChoices() const
{
    QVariantList choices;
    for (int minutes : { 1, 2, 5, 10, 15, 30, 60 }) {
        choices.append(choice(duration(minutes), minutes));
    }
    choices.append(choice(i18nc("@item:inlistbox The screen never turns off by itself", "Never"), 0));
    return choices;
}

bool PowerSettings::saving() const
{
    return m_process != nullptr;
}

QString PowerSettings::error() const
{
    return m_error;
}

QStringList PowerSettings::helperArguments() const
{
    return { QString::number(m_sleepWhenIdle ? m_sleepAfterMinutes : 0), QString::number(m_screenOffAfterMinutes) };
}

void PowerSettings::save()
{
    if (m_process) {
        m_saveAgain = true;
        return;
    }
    const QStringList arguments = helperArguments();
    if (arguments == m_lastSaved) {
        return;
    }
    m_running = arguments;
    m_process = new QProcess(this);
    connect(
        m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) { finish(status == QProcess::NormalExit && exitCode == 0); });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(false);
        }
    });
    m_process->start(m_program, m_arguments + arguments);
    Q_EMIT savingChanged();
}

void PowerSettings::setCommandForTesting(const QString &program, const QStringList &arguments)
{
    m_program = program;
    m_arguments = arguments;
}

void PowerSettings::setError(const QString &error)
{
    if (error != m_error) {
        m_error = error;
        Q_EMIT errorChanged();
    }
}

void PowerSettings::finish(bool ok)
{
    if (ok) {
        m_lastSaved = m_running;
        setError({ });
    } else {
        setError(i18nc("@info", "The power settings couldn't be saved. You can choose them later in Settings."));
    }
    m_process->deleteLater();
    m_process = nullptr;
    Q_EMIT savingChanged();
    Q_EMIT saved(ok);
    if (m_saveAgain) {
        m_saveAgain = false;
        save();
    }
}
