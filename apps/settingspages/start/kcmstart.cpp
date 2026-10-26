// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_startPlugin)

namespace {

// Start's options as a Plasma settings module.
class StartModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    StartModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Each option applies as soon as it's changed.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(StartModule, "kcm_orielos_start.json")

#include "kcmstart.moc"
