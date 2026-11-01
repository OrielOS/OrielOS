// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "recentactivity.h"

#include <KLocalizedString>
#include <KService>

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QStandardPaths>

#include <algorithm>

namespace OrielOSSettingsPages {

namespace {

using namespace std::chrono_literals;

const QStringList Kinds = { QStringLiteral("camera"), QStringLiteral("microphone"), QStringLiteral("location") };
constexpr qint64 KeepSeconds = 7 * 24 * 3600;
// privacy-activity looks every 15 seconds, so an app seen in the last 40 is still using it.
constexpr qint64 NowSeconds = 40;

std::pair<QString, QString> installedApp(const QString &id)
{
    if (id.startsWith(QLatin1String("exe:"))) {
        return { id.mid(4), QStringLiteral("application-x-executable") };
    }
    const KService::Ptr service = KService::serviceByDesktopName(id);
    if (service) {
        return { service->name(), service->icon() };
    }
    return { id, QStringLiteral("application-x-executable") };
}

} // namespace

RecentActivity::RecentActivity(QObject *parent)
    : RecentActivity(QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/orielos/privacy-activity.json"),
          [] { return QDateTime::currentDateTime(); }, &installedApp, parent)
{
}

RecentActivity::RecentActivity(const QString &stateFile, std::function<QDateTime()> now, AppLookup lookup, QObject *parent)
    : QObject(parent)
    , m_stateFile(stateFile)
    , m_now(std::move(now))
    , m_lookup(std::move(lookup))
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &RecentActivity::read);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &RecentActivity::read);
    m_refresh.setInterval(30s);
    connect(&m_refresh, &QTimer::timeout, this, &RecentActivity::read);
    m_refresh.start();
    read();
}

QString RecentActivity::whenText(const QDateTime &when, const QDateTime &now)
{
    if (when.secsTo(now) <= NowSeconds) {
        return i18nc("@info An app is using the camera, microphone or location", "Using it now");
    }
    const QLocale locale;
    const QString time = locale.toString(when.time(), QLocale::ShortFormat);
    const qint64 days = when.date().daysTo(now.date());
    if (days == 0) {
        return i18nc("@info %1 is a time", "Last used today at %1", time);
    }
    if (days == 1) {
        return i18nc("@info %1 is a time", "Last used yesterday at %1", time);
    }
    return i18nc("@info %1 is a day, such as Monday, %2 a time", "Last used on %1 at %2", locale.dayName(when.date().dayOfWeek()), time);
}

void RecentActivity::read()
{
    QFile file(m_stateFile);
    QJsonObject data;
    if (file.open(QIODevice::ReadOnly)) {
        data = QJsonDocument::fromJson(file.readAll()).object();
    }
    const QDateTime now = m_now();
    QList<QVariantList> lists;
    for (const QString &kind : Kinds) {
        const QJsonObject apps = data.value(kind).toObject();
        QList<std::pair<QDateTime, QString>> used;
        for (auto it = apps.constBegin(); it != apps.constEnd(); ++it) {
            const QDateTime when = QDateTime::fromSecsSinceEpoch(static_cast<qint64>(it.value().toDouble()));
            if (it.value().isDouble() && when.secsTo(now) <= KeepSeconds) {
                used.append({ when, it.key() });
            }
        }
        std::sort(used.begin(), used.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
        QVariantList list;
        for (const auto &[when, id] : used) {
            const auto [name, icon] = m_lookup(id);
            list.append(QVariantMap {
                { QStringLiteral("id"), id },
                { QStringLiteral("name"), name },
                { QStringLiteral("icon"), icon },
                { QStringLiteral("when"), whenText(when, now) },
                { QStringLiteral("inUse"), when.secsTo(now) <= NowSeconds },
            });
        }
        lists.append(list);
    }
    m_lists = lists;
    watch();
    Q_EMIT changed();
}

void RecentActivity::watch()
{
    // The file is replaced whole each time, which ends its watch, so it's set again; the folder's
    // watch sees the file appear.
    const QString folder = QFileInfo(m_stateFile).absolutePath();
    if (QFileInfo::exists(folder) && !m_watcher.directories().contains(folder)) {
        m_watcher.addPath(folder);
    }
    if (QFileInfo::exists(m_stateFile) && !m_watcher.files().contains(m_stateFile)) {
        m_watcher.addPath(m_stateFile);
    }
}

} // namespace OrielOSSettingsPages
