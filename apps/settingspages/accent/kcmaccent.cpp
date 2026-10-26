// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_accentPlugin)

namespace {

// Accent colour as a Plasma settings module.
class AccentModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    AccentModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // A colour applies as soon as it's chosen.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(AccentModule, "kcm_orielos_accent.json")

#include "kcmaccent.moc"
