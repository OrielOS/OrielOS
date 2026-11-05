// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <qqmlintegration.h>

class QLocalSocket;

// The first-run setup's PIN: save() hands it to OrielOS's PIN service. Plasma Setup creates the
// account only as it finishes, so the service keeps the PIN for the account's name and gives it to
// the account once the setup is done. An empty PIN takes back one handed over before.
class PinSetup : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool saving READ saving NOTIFY savingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit PinSetup(QObject *parent = nullptr);
    ~PinSetup() override;

    bool saving() const { return m_socket != nullptr; }
    QString error() const { return m_error; }

    // A PIN is 4 to 12 digits, 0 to 9.
    Q_INVOKABLE static bool isValidPin(const QString &pin);

    // Hand the PIN for the account named user to the PIN service, unless it's what was handed over
    // last. A call while a save runs is sent once it ends.
    Q_INVOKABLE void save(const QString &user, const QString &pin);

    // Use another socket instead of the PIN service's. For the unit tests.
    void setSocketForTesting(const QString &path);

Q_SIGNALS:
    void savingChanged();
    void errorChanged();
    void saved(bool ok);

private:
    void send();
    void finish(bool ok);
    void setError(const QString &error);

    QString m_socketPath;
    QLocalSocket *m_socket = nullptr;
    // What's being sent, what was saved last, and what to send once the running save ends.
    QString m_user;
    QString m_pin;
    bool m_hasSaved = false;
    QString m_savedUser;
    QString m_savedPin;
    bool m_pending = false;
    QString m_pendingUser;
    QString m_pendingPin;
    QString m_error;
};
