// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_powermodePlugin)

namespace {

// Power mode as a Plasma settings module.
class PowerModeModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    PowerModeModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // A mode applies as soon as it's chosen.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(PowerModeModule, "kcm_orielos_powermode.json")

#include "kcmpowermode.moc"
