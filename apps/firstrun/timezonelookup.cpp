// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "timezonelookup.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimeZone>

using namespace std::chrono_literals;

namespace {
// Fedora's geolocation service, which Anaconda asks for the installer's language and time zone.
const QUrl FedoraGeoIp(QStringLiteral("https://geoip.fedoraproject.org/city"));
// How long to wait for an answer, and between tries while there's no network yet.
constexpr auto Timeout = 10s;
constexpr auto RetryInterval = 15s;
} // namespace

TimeZoneLookup::TimeZoneLookup(QObject *parent)
    : QObject(parent)
    , m_url(FedoraGeoIp)
    , m_network(new QNetworkAccessManager(this))
{
    m_retry.setSingleShot(true);
    m_retry.setInterval(RetryInterval);
    connect(&m_retry, &QTimer::timeout, this, &TimeZoneLookup::ask);
    connect(m_network, &QNetworkAccessManager::finished, this, &TimeZoneLookup::answered);
    // Asked once the setup has made the page, so a test can change the source first.
    QTimer::singleShot(0, this, &TimeZoneLookup::ask);
}

QString TimeZoneLookup::zoneFromReply(const QByteArray &reply)
{
    const QString zone = QJsonDocument::fromJson(reply).object().value(QStringLiteral("time_zone")).toString();
    if (zone.isEmpty() || !QTimeZone::isTimeZoneIdAvailable(zone.toUtf8())) {
        return QString();
    }
    return zone;
}

void TimeZoneLookup::setSourceForTesting(const QUrl &url, std::chrono::milliseconds interval)
{
    m_url = url;
    m_retry.setInterval(interval);
}

void TimeZoneLookup::ask()
{
    if (m_reply || !m_zone.isEmpty()) {
        return;
    }
    QNetworkRequest request(m_url);
    request.setTransferTimeout(Timeout);
    m_reply = m_network->get(request);
}

void TimeZoneLookup::answered(QNetworkReply *reply)
{
    reply->deleteLater();
    if (reply != m_reply) {
        return;
    }
    m_reply = nullptr;
    const QString zone = reply->error() == QNetworkReply::NoError ? zoneFromReply(reply->readAll()) : QString();
    if (zone.isEmpty()) {
        m_retry.start();
        return;
    }
    m_zone = zone;
    Q_EMIT zoneChanged();
}
