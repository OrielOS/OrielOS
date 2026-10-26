// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "accentcolour.h"

#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QStandardPaths>

namespace OrielOSSettingsPages {

namespace {

QVariantMap choice(const QString &name, const char *colour)
{
    return { { QStringLiteral("name"), name }, { QStringLiteral("colour"), QColor(QLatin1String(colour)) } };
}

} // namespace

AccentColour::AccentColour(QObject *parent)
    : QObject(parent)
    , m_program(QStringLiteral("plasma-apply-colorscheme"))
    , m_watcher(KConfigWatcher::create(KSharedConfig::openConfig(QStringLiteral("kdeglobals"))))
{
    // The Themes page, or any other, may change the colours too.
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group) {
        if (group.name() == QLatin1String("General")) {
            reload();
        }
    });
    reload();
}

AccentColour::~AccentColour()
{
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->waitForFinished(5000);
    }
}

QVariantList AccentColour::choices() const
{
    return {
        choice(i18nc("@item An accent colour", "Blue"), "#3a66f0"),
        choice(i18nc("@item An accent colour", "Teal"), "#0f9d8f"),
        choice(i18nc("@item An accent colour", "Green"), "#2e9d4c"),
        choice(i18nc("@item An accent colour", "Amber"), "#c98a00"),
        choice(i18nc("@item An accent colour", "Orange"), "#e0661b"),
        choice(i18nc("@item An accent colour", "Red"), "#d63a3a"),
        choice(i18nc("@item An accent colour", "Pink"), "#c2185b"),
        choice(i18nc("@item An accent colour", "Purple"), "#8e44ad"),
        choice(i18nc("@item An accent colour", "Indigo"), "#5b5fc7"),
        choice(i18nc("@item An accent colour", "Graphite"), "#6b7280"),
    };
}

QColor AccentColour::current() const
{
    return m_pending.isValid() ? m_pending : m_current;
}

void AccentColour::reload()
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
    globals->reparseConfiguration();
    const KConfigGroup general(globals, QStringLiteral("General"));
    m_current = general.readEntry("AccentColor", QColor());

    // The scheme's own selection colour, from its file.
    m_themeColour = QColor();
    const QString scheme = general.readEntry("ColorScheme", QString());
    const QString path = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("color-schemes/%1.colors").arg(scheme));
    if (!scheme.isEmpty() && !path.isEmpty()) {
        const KConfig schemeFile(path, KConfig::SimpleConfig);
        m_themeColour = KConfigGroup(&schemeFile, QStringLiteral("Colors:Selection")).readEntry("BackgroundNormal", QColor());
    }
    Q_EMIT changed();
}

void AccentColour::choose(const QColor &colour)
{
    if (colour.isValid()) {
        apply(colour);
    }
}

void AccentColour::useThemeColour()
{
    if (m_current.isValid()) {
        apply(QColor());
    }
}

void AccentColour::setCommandForTesting(const QString &program, const QStringList &arguments)
{
    m_program = program;
    m_arguments = arguments;
}

namespace {

// Record the accent in kdeglobals, or remove it for the scheme's own; KConfigWatcher tells the
// desktop.
void writeAccent(const QColor &colour)
{
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
    KConfigGroup general(globals, QStringLiteral("General"));
    if (colour.isValid()) {
        general.writeEntry("AccentColor", colour, KConfig::Notify);
    } else {
        general.deleteEntry("AccentColor", KConfig::Notify);
    }
    globals->sync();
}

} // namespace

void AccentColour::apply(const QColor &colour)
{
    if (m_process) {
        return;
    }
    // plasma-apply-colorscheme recolours the scheme with the accent but doesn't record it, and the
    // next scheme applied, for example by switching to dark mode, keeps only a recorded accent.
    m_previous = m_current;
    writeAccent(colour);
    m_pending = colour;
    m_error.clear();
    m_process = new QProcess(this);
    connect(
        m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) { finish(status == QProcess::NormalExit && exitCode == 0); });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(false);
        }
    });
    m_process->start(m_program,
        m_arguments + QStringList { QStringLiteral("--accent-color"), colour.isValid() ? colour.name(QColor::HexRgb) : QStringLiteral("transparent") });
    Q_EMIT changed();
}

void AccentColour::finish(bool ok)
{
    m_process->deleteLater();
    m_process = nullptr;
    m_pending = QColor();
    if (!ok) {
        writeAccent(m_previous);
        m_error = i18nc("@info", "The accent colour couldn't be changed.");
    }
    reload();
    Q_EMIT applied(ok);
}

} // namespace OrielOSSettingsPages
