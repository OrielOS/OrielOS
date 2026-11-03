// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "appearance.h"

#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

namespace OrielOSTour {

namespace {

const QString accentTheme = QStringLiteral("orielos-accent");

} // namespace

Appearance::Appearance(QObject *parent)
    : QObject(parent)
    , m_plasmaConfig(QStringLiteral("plasmarc"))
    , m_watcher(KConfigWatcher::create(KSharedConfig::openConfig(QStringLiteral("kdeglobals"))))
{
    // The Themes page, or Plasma's own automatic switching, may change it too.
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group) {
        if (group.name() == QLatin1String("General")) {
            reload();
        }
    });
    reload();
}

Appearance::~Appearance()
{
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->waitForFinished(5000);
    }
}

bool Appearance::isDark() const
{
    return m_process ? m_pending : m_dark;
}

void Appearance::reload()
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
    globals->reparseConfiguration();
    // OrielOSDark, or any other dark scheme by its name; OrielOS is dark when nothing says otherwise.
    const QString scheme = KConfigGroup(globals, QStringLiteral("General")).readEntry("ColorScheme", QStringLiteral("OrielOSDark"));
    m_dark = scheme.contains(QLatin1String("dark"), Qt::CaseInsensitive);
    Q_EMIT changed();
}

void Appearance::setDark(bool dark)
{
    if (m_process || dark == m_dark) {
        return;
    }
    m_pending = dark;
    m_error.clear();
    m_steps = {
        { { QStringLiteral("plasma-apply-lookandfeel"), QStringLiteral("--apply"),
              dark ? QStringLiteral("org.orielos.desktop.dark") : QStringLiteral("org.orielos.desktop") },
            true },
        // It says so and may fail when the look-and-feel has already set the scheme.
        { { QStringLiteral("plasma-apply-colorscheme"), dark ? QStringLiteral("OrielOSDark") : QStringLiteral("OrielOSLight") }, false },
    };
    const KConfig plasma(m_plasmaConfig);
    if (KConfigGroup(&plasma, QStringLiteral("Theme")).readEntry("name", QString()) == accentTheme) {
        m_steps.append({ { QStringLiteral("plasma-apply-desktoptheme"), accentTheme }, false });
    }
    runNext();
    Q_EMIT changed();
}

void Appearance::runNext()
{
    if (m_steps.isEmpty()) {
        finish(true);
        return;
    }
    QStringList command = m_steps.constFirst().command;
    m_process = new QProcess(this);
    if (m_program.isEmpty()) {
        m_process->setProgram(command.takeFirst());
        m_process->setArguments(command);
    } else {
        m_process->setProgram(m_program);
        m_process->setArguments(m_arguments + command);
    }
    connect(m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && exitCode == 0;
        const bool required = m_steps.takeFirst().required;
        m_process->deleteLater();
        m_process = nullptr;
        if (!ok && required) {
            finish(false);
        } else {
            runNext();
        }
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) {
            return;
        }
        const bool required = m_steps.takeFirst().required;
        m_process->deleteLater();
        m_process = nullptr;
        if (required) {
            finish(false);
        } else {
            runNext();
        }
    });
    m_process->start();
}

void Appearance::finish(bool ok)
{
    m_steps.clear();
    if (!ok) {
        m_error = m_pending ? i18nc("@info", "Dark mode couldn't be turned on.") : i18nc("@info", "Light mode couldn't be turned on.");
    }
    reload();
    Q_EMIT applied(ok);
}

void Appearance::setCommandForTesting(const QString &program, const QStringList &arguments)
{
    m_program = program;
    m_arguments = arguments;
}

void Appearance::setPlasmaConfigForTesting(const QString &config)
{
    m_plasmaConfig = config;
}

} // namespace OrielOSTour
