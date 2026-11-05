// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page and its model are a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_datetimePlugin)

namespace {

// Date & time as a Plasma settings module.
class DateTimeModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    DateTimeModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // Each switch and button acts at once; there's nothing to apply.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(DateTimeModule, "kcm_orielos_datetime.json")

#include "kcmdatetime.moc"
