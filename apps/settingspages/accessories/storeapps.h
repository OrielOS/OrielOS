// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// The apps for mice, keyboards and lighting that OrielOS points to in the Store: Solaar, Piper and
// OpenRGB. Each entry says whether it's installed; an installed one opens, the others open their
// Store page, where the user chooses whether to install them.
class StoreApps : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // { id, name, description, icon, installed } for each app, in order.
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)

public:
    // How the page finds and starts apps. The tests pass their own.
    struct Environment
    {
        std::function<bool(const QString &id)> isInstalled;
        std::function<void(const QString &id)> launch;
        std::function<void(const QString &url)> openUrl;
    };

    // Installed means a Flatpak with that ID exports its desktop entry; apps start with flatpak run,
    // and the Store opens appstream: links.
    explicit StoreApps(QObject *parent = nullptr);
    explicit StoreApps(Environment environment, QObject *parent = nullptr);

    QVariantList apps() const;

    // Look again for installed apps. The page does when an applications folder changes, as when an
    // app is installed from the Store.
    Q_INVOKABLE void refresh();
    // Start the app if it's installed, or else open its page in the Store.
    Q_INVOKABLE void open(const QString &id);

Q_SIGNALS:
    void changed();

private:
    struct App
    {
        QString id;
        QString name;
        QString description;
        bool installed = false;
    };

    Environment m_environment;
    QList<App> m_apps;
};

} // namespace OrielOSSettingsPages
