// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "modules.h"

#include <KService>

#include <QSet>

namespace OrielOSSettings {

QStringList moduleNamespaces()
{
    return {
        QStringLiteral("plasma/kcms/systemsettings"),
        QStringLiteral("plasma/kcms/systemsettings_qwidgets"),
        QStringLiteral("plasma/kcms"),
        QStringLiteral("plasma/kcms/kinfocenter"),
    };
}

KPluginMetaData findModule(const QString &id)
{
    for (const QString &space : moduleNamespaces()) {
        const KPluginMetaData metadata = KPluginMetaData::findPluginById(space, id);
        if (metadata.isValid()) {
            return metadata;
        }
    }
    return { };
}

QList<KPluginMetaData> settingsModules()
{
    QList<KPluginMetaData> out;
    QSet<QString> seen;
    for (const QString &space : moduleNamespaces()) {
        for (const KPluginMetaData &metadata : KPluginMetaData::findPlugins(space)) {
            const QStringList formFactors = metadata.formFactors();
            const bool forDesktops = formFactors.isEmpty() || formFactors.contains(QLatin1String("desktop"));
            if (metadata.isHidden() || !forDesktops || metadata.pluginId() == QLatin1String("kcm_landingpage") || seen.contains(metadata.pluginId())) {
                continue;
            }
            seen.insert(metadata.pluginId());
            out.append(metadata);
        }
    }
    return out;
}

bool isInfoModule(const KPluginMetaData &metadata)
{
    return metadata.fileName().contains(QLatin1String("/plasma/kcms/kinfocenter/"));
}

bool isAppModule(const QString &module)
{
    return module.startsWith(QLatin1String("app:"));
}

QString appDesktopName(const QString &module)
{
    return module.mid(4);
}

bool isInstalled(const QString &module)
{
    if (isAppModule(module)) {
        return KService::serviceByDesktopName(appDesktopName(module)) != nullptr;
    }
    return findModule(module).isValid();
}

} // namespace OrielOSSettings
