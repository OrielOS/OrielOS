// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "installedapps.h"

#include <KLocalizedString>

#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>

#include <algorithm>
#include <utility>

namespace OrielOSSettingsPages {

namespace {

const QStringList sourceNames = { QStringLiteral("anywhere"), QStringLiteral("suggest"), QStringLiteral("store") };

QString runFlatpak(const QStringList &arguments)
{
    QProcess process;
    process.start(QStringLiteral("flatpak"), arguments);
    if (!process.waitForFinished(15000) || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        return { };
    }
    return QString::fromUtf8(process.readAllStandardOutput());
}

// Flatpak deploys each app in its own folder and points "active" at it; its time is the install's,
// or the last update's, the nearest Flatpak keeps.
QDateTime deployedOn(const QString &id, const QString &installation)
{
    const QString base = installation == QLatin1String("user")
        ? QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/flatpak")
        : QStringLiteral("/var/lib/flatpak");
    const QFileInfo active(base + QStringLiteral("/app/") + id + QStringLiteral("/current/active"));
    return QFileInfo(active.canonicalFilePath()).lastModified();
}

} // namespace

QList<InstalledApp> InstalledApp::parseList(const QString &list)
{
    QList<InstalledApp> apps;
    for (const QString &line : list.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList columns = line.split(QLatin1Char('\t'));
        if (columns.size() < 5 || columns.at(0).trimmed().isEmpty()) {
            continue;
        }
        InstalledApp app;
        app.id = columns.at(0).trimmed();
        app.name = columns.at(1).trimmed().isEmpty() ? app.id : columns.at(1).trimmed();
        app.version = columns.at(2).trimmed();
        app.size = columns.at(3).trimmed();
        app.installation = columns.at(4).trimmed();
        apps.append(app);
    }
    return apps;
}

InstalledApps::InstalledApps(QObject *parent)
    : InstalledApps(Environment { runFlatpak, deployedOn,
                        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/orielos-appsrc"),
                        QStringLiteral("flatpak") },
          parent)
{
}

InstalledApps::InstalledApps(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    reload();
}

void InstalledApps::reload()
{
    m_apps = InstalledApp::parseList(
        m_environment.listApps({ QStringLiteral("list"), QStringLiteral("--app"), QStringLiteral("--columns=application,name,version,size,installation") }));
    for (InstalledApp &app : m_apps) {
        app.installedOn = m_environment.installedOn(app.id, app.installation);
    }
    std::sort(m_apps.begin(), m_apps.end(), [](const InstalledApp &a, const InstalledApp &b) {
        return QString::localeAwareCompare(a.name, b.name) < 0;
    });
    Q_EMIT changed();
}

QVariantList InstalledApps::apps() const
{
    QVariantList out;
    for (const InstalledApp &app : m_apps) {
        out.append(QVariantMap {
            { QStringLiteral("id"), app.id },
            { QStringLiteral("name"), app.name },
            { QStringLiteral("version"), app.version },
            { QStringLiteral("size"), app.size },
            { QStringLiteral("installedOn"), app.installedOn.isValid() ? QLocale().toString(app.installedOn.date(), QLocale::ShortFormat) : QString() },
            { QStringLiteral("installedAt"), app.installedOn.isValid() ? app.installedOn.toSecsSinceEpoch() : 0 },
            { QStringLiteral("installation"), app.installation },
        });
    }
    return out;
}

void InstalledApps::uninstall(const QString &id)
{
    const auto app = std::find_if(m_apps.cbegin(), m_apps.cend(), [&id](const InstalledApp &a) { return a.id == id; });
    if (m_busy || app == m_apps.cend()) {
        return;
    }
    m_busy = true;
    m_error.clear();
    Q_EMIT changed();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, name = app->name](int exitCode, QProcess::ExitStatus exitStatus) {
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            m_error = i18nc("@info %1 is an app", "%1 couldn't be uninstalled.", name);
        }
        process->deleteLater();
        m_busy = false;
        reload();
    });
    // Flatpak asks polkit when the app is installed for everyone.
    process->start(m_environment.flatpakProgram,
        { QStringLiteral("uninstall"), QStringLiteral("--noninteractive"),
            app->installation == QLatin1String("user") ? QStringLiteral("--user") : QStringLiteral("--system"), id });
}

int InstalledApps::appSource() const
{
    const QSettings settings(m_environment.configPath, QSettings::IniFormat);
    return std::max<qsizetype>(0, sourceNames.indexOf(settings.value(QStringLiteral("source")).toString()));
}

void InstalledApps::setAppSource(int source)
{
    if (source < 0 || source >= sourceNames.size() || source == appSource()) {
        return;
    }
    QDir().mkpath(QFileInfo(m_environment.configPath).absolutePath());
    QSettings settings(m_environment.configPath, QSettings::IniFormat);
    settings.setValue(QStringLiteral("source"), sourceNames.at(source));
    settings.sync();
    Q_EMIT changed();
}

} // namespace OrielOSSettingsPages
