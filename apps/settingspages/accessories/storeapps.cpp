// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "storeapps.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KLocalizedString>
#include <KNotificationJobUiDelegate>
#include <KService>

#include <QDir>
#include <QFileSystemWatcher>
#include <QStandardPaths>
#include <QUrl>

namespace OrielOSSettingsPages {

namespace {

// Where Flatpak keeps the icons of Flathub's catalogue, for apps that aren't installed yet.
const QString flathubIcons = QStringLiteral("/var/lib/flatpak/appstream/flathub/x86_64/active/icons/128x128/");

} // namespace

StoreApps::StoreApps(QObject *parent)
    : StoreApps(Environment {
                    [](const QString &id) {
                        // Flatpak exports an installed app's desktop entry to a folder on XDG_DATA_DIRS.
                        return !QStandardPaths::locate(QStandardPaths::ApplicationsLocation, id + QStringLiteral(".desktop")).isEmpty();
                    },
                    // Through KIO, so the app gets an activation token and comes to the front, and a
                    // failure says so in a notification.
                    [](const QString &id) {
                        const KService::Ptr service = KService::serviceByDesktopName(id);
                        if (!service) {
                            return;
                        }
                        auto *job = new KIO::ApplicationLauncherJob(service);
                        job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
                        job->start();
                    },
                    [](const QString &url) {
                        auto *job = new KIO::OpenUrlJob(QUrl(url));
                        job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
                        job->start();
                    },
                },
          parent)
{
    // An app installed or removed in the Store adds or removes its desktop entry in one of these
    // folders, so the page follows without polling, and only while it exists.
    auto *watcher = new QFileSystemWatcher(this);
    for (const QString &folder : QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation)) {
        if (QDir(folder).exists()) {
            watcher->addPath(folder);
        }
    }
    connect(watcher, &QFileSystemWatcher::directoryChanged, this, &StoreApps::refresh);
}

StoreApps::StoreApps(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
    , m_apps {
        { QStringLiteral("io.github.pwr_solaar.solaar"), QStringLiteral("Solaar"),
            i18nc("@info", "Logitech mice and keyboards, and their Unifying and Bolt receivers: pairing, battery and buttons."), false },
        { QStringLiteral("org.freedesktop.Piper"), QStringLiteral("Piper"),
            i18nc("@info", "Gaming mice from Logitech, SteelSeries, Roccat and others: buttons, sensitivity and lights."), false },
        { QStringLiteral("org.openrgb.OpenRGB"), QStringLiteral("OpenRGB"),
            i18nc("@info", "RGB lighting on keyboards, mice, fans, memory and motherboards from many brands."), false },
    }
{
    refresh();
}

QVariantList StoreApps::apps() const
{
    QVariantList out;
    for (const App &app : m_apps) {
        out.append(QVariantMap {
            { QStringLiteral("id"), app.id },
            { QStringLiteral("name"), app.name },
            { QStringLiteral("description"), app.description },
            // An installed app's icon is in the icon theme under its ID; the others' come with
            // Flathub's catalogue.
            { QStringLiteral("icon"), app.installed ? app.id : QStringLiteral("file://") + flathubIcons + app.id + QStringLiteral(".png") },
            { QStringLiteral("installed"), app.installed },
        });
    }
    return out;
}

void StoreApps::refresh()
{
    bool changed = false;
    for (App &app : m_apps) {
        const bool installed = m_environment.isInstalled(app.id);
        changed = changed || installed != app.installed;
        app.installed = installed;
    }
    if (changed) {
        Q_EMIT this->changed();
    }
}

void StoreApps::open(const QString &id)
{
    for (const App &app : std::as_const(m_apps)) {
        if (app.id != id) {
            continue;
        }
        if (m_environment.isInstalled(id)) {
            m_environment.launch(id);
        } else {
            m_environment.openUrl(QStringLiteral("appstream://") + id);
        }
        return;
    }
}

} // namespace OrielOSSettingsPages
