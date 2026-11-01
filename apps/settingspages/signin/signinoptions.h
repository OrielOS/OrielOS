// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariantList>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// The Sign-in options page's model: the PIN (kept by OrielOS's PIN service), fingerprints (fprintd),
// dynamic lock, and the sign-in and lock screens' settings.
class SignInOptions : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool hasPin READ hasPin NOTIFY pinChanged FINAL)
    Q_PROPERTY(int pinLength READ pinLength NOTIFY pinChanged FINAL)
    // Whether the PIN service answered.
    Q_PROPERTY(bool pinServiceAvailable READ pinServiceAvailable NOTIFY pinChanged FINAL)
    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged FINAL)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged FINAL)

    Q_PROPERTY(bool fingerprintReaderPresent READ fingerprintReaderPresent NOTIFY fingerprintChanged FINAL)

    // { address, name } for each paired Bluetooth device.
    Q_PROPERTY(QVariantList pairedDevices READ pairedDevices NOTIFY dynamicLockChanged FINAL)
    Q_PROPERTY(bool dynamicLockEnabled READ dynamicLockEnabled NOTIFY dynamicLockChanged FINAL)
    Q_PROPERTY(QString dynamicLockDevice READ dynamicLockDevice NOTIFY dynamicLockChanged FINAL)

    Q_PROPERTY(bool lockOnResume READ lockOnResume WRITE setLockOnResume NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool requireCtrlAltDel READ requireCtrlAltDel WRITE setRequireCtrlAltDel NOTIFY settingsChanged FINAL)
    Q_PROPERTY(bool startupSound READ startupSound WRITE setStartupSound NOTIFY settingsChanged FINAL)

public:
    explicit SignInOptions(QObject *parent = nullptr);

    bool hasPin() const { return m_pinLength > 0; }
    int pinLength() const { return m_pinLength; }
    bool pinServiceAvailable() const { return m_pinServiceAvailable; }
    bool isBusy() const { return m_busy; }
    QString error() const { return m_error; }
    bool fingerprintReaderPresent() const { return m_fingerprintReader; }
    QVariantList pairedDevices() const { return m_pairedDevices; }
    bool dynamicLockEnabled() const { return !m_dynamicLockDevice.isEmpty(); }
    QString dynamicLockDevice() const { return m_dynamicLockDevice; }
    bool lockOnResume() const;
    void setLockOnResume(bool lock);
    bool requireCtrlAltDel() const;
    void setRequireCtrlAltDel(bool require);
    bool startupSound() const;
    void setStartupSound(bool play);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setPin(const QString &pin, const QString &credential);
    Q_INVOKABLE void removePin(const QString &credential);
    Q_INVOKABLE void openFingerprintSetup();
    Q_INVOKABLE void setDynamicLock(bool enabled, const QString &address);

    // A PIN is 4 to 12 digits.
    static bool isValidPin(const QString &pin);
    // The phone's address in a dynamic lock file ("device=AA:BB:CC:DD:EE:FF"), or empty.
    static QString parseDynamicLockFile(const QByteArray &contents);
    static QByteArray formatDynamicLockFile(const QString &address);

Q_SIGNALS:
    void pinChanged();
    void busyChanged();
    void errorChanged();
    void fingerprintChanged();
    void dynamicLockChanged();
    void settingsChanged();

private:
    // Sends one request to the PIN service and hands its answer (empty if it didn't answer) on.
    void askPinService(const QJsonObject &request, std::function<void(const QJsonObject &)> done);
    void readFingerprintReaders();
    void readPairedDevices();
    void setError(const QString &error);
    void setBusy(bool busy);
    // Runs the sign-in settings helper as an administrator; done gets whether it worked.
    void runSignInSettings(const QString &setting, bool on, std::function<void(bool)> done);

    int m_pinLength = 0;
    bool m_pinServiceAvailable = false;
    bool m_busy = false;
    QString m_error;
    bool m_fingerprintReader = false;
    QVariantList m_pairedDevices;
    QString m_dynamicLockDevice;
    // Whether the startup sound plays, as the helper last left it.
    bool m_startupSound = true;
};

} // namespace OrielOSSettingsPages
