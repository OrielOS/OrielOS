// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// What the power profiles daemon (tuned-ppd on OrielOS) reports.
struct PowerProfilesState
{
    bool available = false;
    QString active;
    // The profiles it offers: performance, balanced and power-saver, in its order.
    QStringList profiles;
    // Why performance is held back, such as "high-operating-temperature", or empty.
    QString degraded;

    // From the daemon's D-Bus properties, with Profiles as a list of maps with a "Profile" key.
    static PowerProfilesState fromProperties(const QVariantMap &properties);
};

// Reads and sets the power mode. The default talks to org.freedesktop.UPower.PowerProfiles on the
// system bus; the unit tests use their own.
class PowerProfilesBackend : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

public Q_SLOTS:
    // Read the state; stateRead follows, and again whenever the daemon reports a change.
    virtual void read() = 0;

public:
    // Ask for another mode; setFinished follows.
    virtual void setActive(const QString &profile) = 0;

Q_SIGNALS:
    void stateRead(const OrielOSSettingsPages::PowerProfilesState &state);
    void setFinished(bool ok);
};

// The Power mode page's model: Performance, Balanced or Power saver, as in the tray's power and
// battery widget. Performance is OrielOS's default; a mode chosen here is kept by the daemon.
class PowerMode : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ isReady NOTIFY changed)
    // Whether the daemon answered.
    Q_PROPERTY(bool available READ isAvailable NOTIFY changed)
    // { id, name, description } for each mode the daemon offers, Performance first.
    Q_PROPERTY(QVariantList modes READ modes NOTIFY changed)
    Q_PROPERTY(QString active READ active WRITE setActive NOTIFY changed)
    // Why Performance is held back right now, in plain words, or empty.
    Q_PROPERTY(QString degraded READ degraded NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit PowerMode(QObject *parent = nullptr);
    // Uses this backend, which it takes, instead of the daemon. For the unit tests.
    explicit PowerMode(PowerProfilesBackend *backend, QObject *parent = nullptr);

    bool isReady() const { return m_ready; }
    bool isAvailable() const { return m_state.available; }
    QVariantList modes() const;
    QString active() const { return m_pending.isEmpty() ? m_state.active : m_pending; }
    void setActive(const QString &profile);
    QString degraded() const;
    QString error() const { return m_error; }

Q_SIGNALS:
    void changed();

private:
    PowerProfilesBackend *m_backend;
    PowerProfilesState m_state;
    // The mode asked for, shown until the daemon answers.
    QString m_pending;
    bool m_ready = false;
    QString m_error;
};

} // namespace OrielOSSettingsPages
