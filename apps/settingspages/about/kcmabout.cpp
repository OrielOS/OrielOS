// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_aboutPlugin)

namespace {

// About as a Plasma settings module.
class AboutModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    AboutModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Renaming acts through its own button; there's nothing to apply.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(AboutModule, "kcm_orielos_about.json")

#include "kcmabout.moc"
