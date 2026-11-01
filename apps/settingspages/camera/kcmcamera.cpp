// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QtQml/qqmlextensionplugin.h>

// The page is a static QML module linked into this plugin.
Q_IMPORT_QML_PLUGIN(org_orielos_cameraPlugin)

namespace {

// Camera as a Plasma settings module.
class CameraModule : public KQuickConfigModule
{
    Q_OBJECT

public:
    CameraModule(QObject *parent, const KPluginMetaData &metaData)
        : KQuickConfigModule(parent, metaData)
    {
        // A change applies as soon as it is made.
        setButtons(NoAdditionalButton);
    }
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(CameraModule, "kcm_orielos_camera.json")

#include "kcmcamera.moc"
