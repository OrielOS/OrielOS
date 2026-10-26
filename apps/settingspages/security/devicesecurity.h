// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "securitychecks.h"

#include <QFutureWatcher>
#include <QObject>
#include <QVariantList>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The Device security page's self-test: whether this start meets each requirement of games with
// anti-cheat. The checks run on a worker thread when the page opens and when run() is called.
class DeviceSecurity : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // { id, title, result ("met", "not-met" or "unknown"), explanation } for each requirement.
    Q_PROPERTY(QVariantList checks READ checks NOTIFY changed)
    Q_PROPERTY(bool running READ isRunning NOTIFY changed)
    // Whether the checks have run and every requirement is met.
    Q_PROPERTY(bool allMet READ allMet NOTIFY changed)

public:
    explicit DeviceSecurity(QObject *parent = nullptr);
    // Checks these sources instead of the running system. For the unit tests.
    explicit DeviceSecurity(SecuritySources sources, QObject *parent = nullptr);
    ~DeviceSecurity() override;

    QVariantList checks() const;
    bool isRunning() const { return m_watcher.isRunning(); }
    bool allMet() const;

    // Run the checks again, unless they're running.
    Q_INVOKABLE void run();

Q_SIGNALS:
    void changed();

private:
    SecuritySources m_sources;
    QList<SecurityCheck> m_checks;
    QFutureWatcher<QList<SecurityCheck>> m_watcher;
};

} // namespace OrielOSSettingsPages
