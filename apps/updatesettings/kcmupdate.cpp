// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_updatesettingsPlugin)

namespace {

// The Update settings page as a Plasma settings module, which System Settings shows under System.
class UpdateModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    UpdateModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Every change takes effect at once, so there is nothing to apply, reset or restore.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(UpdateModule, "kcm_orielos_update.json")

#include "kcmupdate.moc"
