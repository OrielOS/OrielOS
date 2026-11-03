// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_recoveryPlugin)

namespace {

// Recovery as a Plasma settings module.
class RecoveryModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    RecoveryModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Each choice acts through its own button and question; there's nothing to apply.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(RecoveryModule, "kcm_orielos_recovery.json")

#include "kcmrecovery.moc"
