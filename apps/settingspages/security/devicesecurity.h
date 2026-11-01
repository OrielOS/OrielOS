// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "securitychecks.h"

#include <QFutureWatcher>
#include <QObject>
#include <QVariantList>
#include <qqmlintegration.h>

#include <atomic>
#include <memory>

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
    // The computer's protection, as checks are: the firewall and updates.
    Q_PROPERTY(QVariantList protection READ protection NOTIFY changed)

public:
    explicit DeviceSecurity(QObject *parent = nullptr);
    // Checks these sources instead of the running system. For the unit tests.
    explicit DeviceSecurity(SecuritySources sources, QObject *parent = nullptr);
    ~DeviceSecurity() override;

    QVariantList checks() const;
    QVariantList protection() const;
    bool isRunning() const { return m_watcher.isRunning(); }
    bool allMet() const;

    // Run the checks again, unless they're running.
    Q_INVOKABLE void run();

Q_SIGNALS:
    void changed();

private:
    SecuritySources m_sources;
    // Set when the page goes, so a run still going stops at the next module.
    std::shared_ptr<std::atomic_bool> m_cancelled = std::make_shared<std::atomic_bool>(false);
    QList<SecurityCheck> m_checks;
    QList<SecurityCheck> m_protection;
    QFutureWatcher<QList<SecurityCheck>> m_watcher;
};

} // namespace OrielOSSettingsPages
