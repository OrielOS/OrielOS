// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_accessoriesPlugin)

namespace {

// Accessory apps as a Plasma settings module.
class AccessoriesModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    AccessoriesModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // The page opens apps and Store pages; it has nothing to apply.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(AccessoriesModule, "kcm_orielos_accessories.json")

#include "kcmaccessories.moc"
