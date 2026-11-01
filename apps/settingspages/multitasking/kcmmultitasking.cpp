// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_multitaskingPlugin)

namespace {

// Multitasking as a Plasma settings module.
class MultitaskingModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    MultitaskingModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Each switch applies as soon as it's changed.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(MultitaskingModule, "kcm_orielos_multitasking.json")

#include "kcmmultitasking.moc"
