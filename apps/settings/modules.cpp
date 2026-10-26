// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "modules.h"

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

QList<KPluginMetaData> systemSettingsModules()
{
    QList<KPluginMetaData> out;
    QSet<QString> seen;
    for (const QString &space : { QStringLiteral("plasma/kcms/systemsettings"), QStringLiteral("plasma/kcms/systemsettings_qwidgets") }) {
        for (const KPluginMetaData &metadata : KPluginMetaData::findPlugins(space)) {
            if (metadata.isHidden() || metadata.value(QStringLiteral("X-KDE-System-Settings-Parent-Category")).isEmpty()
                || seen.contains(metadata.pluginId())) {
                continue;
            }
            seen.insert(metadata.pluginId());
            out.append(metadata);
        }
    }
    return out;
}

} // namespace OrielOSSettings
