// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QTimer>
#include <QUrl>
#include <qqmlintegration.h>

class QNetworkAccessManager;
class QNetworkReply;

// The first-run setup's time zone from the network: asks Fedora's geolocation service, the one
// Fedora's installer uses, which time zone the computer's internet address is in. It asks as soon
// as it's made and again every little while until the network answers, then stops; zone stays
// empty until then, or if the answer isn't a time zone this computer knows.
class TimeZoneLookup : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString zone READ zone NOTIFY zoneChanged)

public:
    explicit TimeZoneLookup(QObject *parent = nullptr);

    QString zone() const { return m_zone; }

    // The time zone in the service's answer, a JSON object with time_zone, if this computer knows
    // it; otherwise empty.
    static QString zoneFromReply(const QByteArray &reply);

    // Ask url instead of Fedora's service, every interval. For the unit tests.
    void setSourceForTesting(const QUrl &url, std::chrono::milliseconds interval);

Q_SIGNALS:
    void zoneChanged();

private:
    void ask();
    void answered(QNetworkReply *reply);

    QUrl m_url;
    QNetworkAccessManager *m_network = nullptr;
    QNetworkReply *m_reply = nullptr;
    QTimer m_retry;
    QString m_zone;
};
