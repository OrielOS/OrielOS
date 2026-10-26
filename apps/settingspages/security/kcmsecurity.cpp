// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_securityPlugin)

namespace {

// Device security as a Plasma settings module.
class SecurityModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    SecurityModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // The page only shows what it finds; it has nothing to apply.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(SecurityModule, "kcm_orielos_security.json")

#include "kcmsecurity.moc"
