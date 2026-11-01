// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_donotdisturbPlugin)

namespace {

// Do not disturb as a Plasma settings module.
class DoNotDisturbModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    DoNotDisturbModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // A change applies as soon as it is made.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(DoNotDisturbModule, "kcm_orielos_donotdisturb.json")

#include "kcmdonotdisturb.moc"
