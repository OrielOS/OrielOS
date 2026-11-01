// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDateTime>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

/**
 * Settings' Recent activity page: which apps used the camera, the microphone and the location in
 * the last seven days, newest first, as privacy-activity notes them in
 * ~/.local/state/orielos/privacy-activity.json ({"camera": {"app ID": last used, in seconds since
 * 1970}, ...}). Each entry is a map with the app's name, icon, when it last used it as text, and
 * whether it's using it now.
 */
class RecentActivity : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList camera READ camera NOTIFY changed)
    Q_PROPERTY(QVariantList microphone READ microphone NOTIFY changed)
    Q_PROPERTY(QVariantList location READ location NOTIFY changed)

public:
    // An app's name and icon from its ID: a desktop entry's, or "exe:" and a program's name.
    using AppLookup = std::function<std::pair<QString, QString>(const QString &id)>;

    explicit RecentActivity(QObject *parent = nullptr);
    // For the tests: another file, the time now and a lookup that needs no installed apps.
    RecentActivity(const QString &stateFile, std::function<QDateTime()> now, AppLookup lookup, QObject *parent = nullptr);

    QVariantList camera() const { return m_lists.value(0); }
    QVariantList microphone() const { return m_lists.value(1); }
    QVariantList location() const { return m_lists.value(2); }

    // How the page says when an app last used something.
    static QString whenText(const QDateTime &when, const QDateTime &now);

Q_SIGNALS:
    void changed();

private:
    void read();
    void watch();

    QString m_stateFile;
    std::function<QDateTime()> m_now;
    AppLookup m_lookup;
    QFileSystemWatcher m_watcher;
    // Rereads now and then, so "Using it now" goes when an app stops.
    QTimer m_refresh;
    QList<QVariantList> m_lists;
};

} // namespace OrielOSSettingsPages
