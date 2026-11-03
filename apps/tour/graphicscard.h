// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <qqmlintegration.h>

namespace OrielOSTour {

// The graphics card games run on, and whether its proper driver is running, read once from sysfs
// and named from hwdata's pci.ids. Needs no root and runs nothing.
class GraphicsCard : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Whether there's a display controller at all.
    Q_PROPERTY(bool available READ isAvailable CONSTANT)
    // The maker and model, ready to show: "NVIDIA GeForce RTX 4070".
    Q_PROPERTY(QString name READ name CONSTANT)
    // nvidia, amd, intel or other.
    Q_PROPERTY(QString vendor READ vendor CONSTANT)
    // The kernel driver bound to the card, or empty.
    Q_PROPERTY(QString driver READ driver CONSTANT)
    // NVIDIA's driver version, or empty for every other driver.
    Q_PROPERTY(QString driverVersion READ driverVersion CONSTANT)
    Q_PROPERTY(State state READ state CONSTANT)
    // Universal Blue's driver key waits to be confirmed on shim's blue screen at the next restart,
    // so the signed drivers, NVIDIA's among them, don't load until then.
    Q_PROPERTY(bool keyPending READ keyPending CONSTANT)

public:
    enum class State {
        // The maker's own driver, or any driver for a card from someone else.
        Working,
        // A fallback that can't run games well: nouveau or simpledrm on NVIDIA, radeon on AMD.
        BasicDriver,
        NoDriver,
    };
    Q_ENUM(State)

    explicit GraphicsCard(QObject *parent = nullptr);
    // Reads these folders, and this file instead of orielos-secure-boot-key's state. For the unit
    // tests.
    GraphicsCard(const QString &sysfs, const QString &hwdata, const QString &keyState, QObject *parent = nullptr);

    bool isAvailable() const { return m_available; }
    QString name() const { return m_name; }
    QString vendor() const { return m_vendor; }
    QString driver() const { return m_driver; }
    QString driverVersion() const { return m_driverVersion; }
    State state() const { return m_state; }
    bool keyPending() const { return m_keyPending; }

private:
    bool m_available = false;
    QString m_name;
    QString m_vendor;
    QString m_driver;
    QString m_driverVersion;
    State m_state = State::NoDriver;
    bool m_keyPending = false;
};

} // namespace OrielOSTour
