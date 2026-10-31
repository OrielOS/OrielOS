// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KPluginMetaData>

#include <QList>
#include <QStringList>

namespace OrielOSSettings {

// The plugin folders System Settings loads its modules from: Plasma's QML and Qt Widgets ones,
// other Plasma ones, and Info Center's, such as About.
QStringList moduleNamespaces();

// A settings module's plugin, looked for where System Settings looks; invalid if it isn't installed.
KPluginMetaData findModule(const QString &id);

// The modules System Settings lists in its sidebar: those with a category of its own, and not
// hidden.
QList<KPluginMetaData> systemSettingsModules();

// A page's module can also be an app, as "app:<desktop entry name>", for settings that live in an
// app of their own, such as NVIDIA's; Settings opens the app instead of a page.
bool isAppModule(const QString &module);
QString appDesktopName(const QString &module);

// Whether a page's module, or its app, is installed.
bool isInstalled(const QString &module);

} // namespace OrielOSSettings
