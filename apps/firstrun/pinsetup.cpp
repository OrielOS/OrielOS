// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pinsetup.h"

#include <KLocalizedString>

#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QTimer>

#include <chrono>

using namespace std::chrono_literals;

PinSetup::PinSetup(QObject *parent)
    : QObject(parent)
    , m_socketPath(QStringLiteral("/run/orielos/pin.socket"))
{
}

PinSetup::~PinSetup()
{
    if (m_socket) {
        m_socket->disconnect(this);
    }
}

bool PinSetup::isValidPin(const QString &pin)
{
    if (pin.size() < 4 || pin.size() > 12) {
        return false;
    }
    for (const QChar c : pin) {
        if (c.unicode() < u'0' || c.unicode() > u'9') {
            return false;
        }
    }
    return true;
}

void PinSetup::save(const QString &user, const QString &pin)
{
    if (user.isEmpty() || (!pin.isEmpty() && !isValidPin(pin))) {
        setError(i18nc("@info", "The PIN couldn't be saved. You can set one up later in Settings."));
        Q_EMIT saved(false);
        return;
    }
    if (m_socket) {
        m_pending = true;
        m_pendingUser = user;
        m_pendingPin = pin;
        return;
    }
    if (m_hasSaved && user == m_savedUser && pin == m_savedPin) {
        Q_EMIT saved(true);
        return;
    }
    m_user = user;
    m_pin = pin;
    send();
}

void PinSetup::send()
{
    m_socket = new QLocalSocket(this);
    auto *timeout = new QTimer(m_socket);
    timeout->setSingleShot(true);
    connect(timeout, &QTimer::timeout, this, [this]() { finish(false); });
    connect(m_socket, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError error) {
        // The service closes the connection after answering; that's read in readyRead.
        if (error != QLocalSocket::PeerClosedError) {
            finish(false);
        }
    });
    connect(m_socket, &QLocalSocket::connected, this, [this]() {
        const QJsonObject request { { QStringLiteral("op"), QStringLiteral("stage") }, { QStringLiteral("user"), m_user }, { QStringLiteral("pin"), m_pin } };
        m_socket->write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    });
    connect(m_socket, &QLocalSocket::readyRead, this, [this]() {
        if (!m_socket->canReadLine()) {
            return;
        }
        // A line that isn't a JSON object reads as an empty one, so as a refusal.
        finish(QJsonDocument::fromJson(m_socket->readLine(4096)).object().value(QStringLiteral("ok")).toBool());
    });
    timeout->start(10s);
    m_socket->connectToServer(m_socketPath);
    Q_EMIT savingChanged();
}

void PinSetup::finish(bool ok)
{
    if (!m_socket) {
        return;
    }
    m_socket->disconnect(this);
    m_socket->abort();
    m_socket->deleteLater();
    m_socket = nullptr;
    if (ok) {
        m_hasSaved = true;
        m_savedUser = m_user;
        m_savedPin = m_pin;
        setError(QString());
    } else {
        setError(i18nc("@info", "The PIN couldn't be saved. You can set one up later in Settings."));
    }
    Q_EMIT savingChanged();
    Q_EMIT saved(ok);
    if (m_pending) {
        m_pending = false;
        save(m_pendingUser, m_pendingPin);
    }
}

void PinSetup::setError(const QString &error)
{
    if (error != m_error) {
        m_error = error;
        Q_EMIT errorChanged();
    }
}

void PinSetup::setSocketForTesting(const QString &path)
{
    m_socketPath = path;
}
