// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_signinPlugin)

namespace {

// Sign-in options as a Plasma settings module.
class SignInModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    SignInModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Every change applies at once.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(SignInModule, "kcm_orielos_signin.json")

#include "kcmsignin.moc"
