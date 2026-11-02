// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDateTime>
#include <QList>
#include <QObject>
#include <QVariantList>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// One app from the Store, as Flatpak lists it.
struct InstalledApp
{
    QString id;
    QString name;
    QString version;
    QString size;
    // system or user: where Flatpak installed it, which uninstalling must name.
    QString installation;
    QDateTime installedOn;

    // Parses "flatpak list --app --columns=application,name,version,size,installation": one app a
    // line, the columns separated by tabs. Lines that don't fit are left out.
    static QList<InstalledApp> parseList(const QString &list);
};

// Settings › Apps › Installed apps: the apps from the Store, with their version, size and install
// date, and Uninstall; and where apps may come from.
class InstalledApps : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // { id, name, version, size, installedOn (ready to show), installedAt (for sorting), installation }
    Q_PROPERTY(QVariantList apps READ apps NOTIFY changed)
    // An uninstall is running.
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // 0 anywhere, 1 anywhere with the Store suggested first, 2 the Store only.
    Q_PROPERTY(int appSource READ appSource NOTIFY changed)

public:
    struct Environment
    {
        // Runs flatpak with these arguments and gives its output, or nothing when it fails.
        std::function<QString(const QStringList &arguments)> listApps;
        // When an app was installed, from its folder in the installation.
        std::function<QDateTime(const QString &id, const QString &installation)> installedOn;
        // orielos-appsrc, where the app source choice is kept.
        QString configPath;
        QString flatpakProgram;
    };

    explicit InstalledApps(QObject *parent = nullptr);
    InstalledApps(Environment environment, QObject *parent);

    QVariantList apps() const;
    bool isBusy() const { return m_busy; }
    QString error() const { return m_error; }
    int appSource() const;

    Q_INVOKABLE void reload();
    Q_INVOKABLE void uninstall(const QString &id);
    Q_INVOKABLE void setAppSource(int source);

Q_SIGNALS:
    void changed();

private:
    Environment m_environment;
    QList<InstalledApp> m_apps;
    bool m_busy = false;
    QString m_error;
};

} // namespace OrielOSSettingsPages
