// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fpsoverlay.h"

#include <KLocalizedString>

#include <QProcess>

namespace OrielOSSettingsPages {

FpsOverlay::FpsOverlay(QObject *parent)
    : FpsOverlay(QStringLiteral("/usr/libexec/orielos/fps-overlay"), parent)
{
}

FpsOverlay::FpsOverlay(const QString &program, QObject *parent)
    : QObject(parent)
    , m_program(program)
{
    reload();
}

void FpsOverlay::readStatus(const QString &status)
{
    for (const QString &line : status.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QString key = line.section(QLatin1Char('='), 0, 0);
        const QString value = line.section(QLatin1Char('='), 1);
        if (key == QLatin1String("enabled")) {
            m_enabled = value == QLatin1String("on");
        } else if (key == QLatin1String("frametime")) {
            m_frameTime = value == QLatin1String("on");
        } else if (key == QLatin1String("stats")) {
            m_stats = value == QLatin1String("on");
        } else if (key == QLatin1String("steam")) {
            m_steam = value;
        }
    }
    Q_EMIT changed();
}

void FpsOverlay::reload()
{
    // The status reads two small files and asks Flatpak about Steam: quick enough to wait for.
    QProcess process;
    process.start(m_program, { QStringLiteral("status") });
    if (process.waitForFinished(5000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0) {
        readStatus(QString::fromUtf8(process.readAllStandardOutput()));
    }
}

void FpsOverlay::run(const QStringList &arguments)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    Q_EMIT changed();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus exitStatus) {
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            const QString detail = QString::fromUtf8(process->readAllStandardError()).trimmed();
            m_error = detail.isEmpty() ? i18nc("@info", "The change couldn't be made.") : detail;
        }
        process->deleteLater();
        m_busy = false;
        reload();
    });
    process->start(m_program, arguments);
}

void FpsOverlay::setEnabled(bool on)
{
    if (on != m_enabled) {
        run({ on ? QStringLiteral("on") : QStringLiteral("off") });
    }
}

void FpsOverlay::setFrameTime(bool on)
{
    if (on != m_frameTime) {
        run({ QStringLiteral("option"), QStringLiteral("frametime"), on ? QStringLiteral("on") : QStringLiteral("off") });
    }
}

void FpsOverlay::setStats(bool on)
{
    if (on != m_stats) {
        run({ QStringLiteral("option"), QStringLiteral("stats"), on ? QStringLiteral("on") : QStringLiteral("off") });
    }
}

void FpsOverlay::installSteamAddon()
{
    if (steamNeedsAddon()) {
        run({ QStringLiteral("steam-addon") });
    }
}

} // namespace OrielOSSettingsPages
