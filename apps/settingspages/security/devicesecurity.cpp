// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "devicesecurity.h"

#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>

namespace OrielOSSettingsPages {

DeviceSecurity::DeviceSecurity(QObject *parent)
    : DeviceSecurity(SecuritySources { }, parent)
{
}

DeviceSecurity::DeviceSecurity(SecuritySources sources, QObject *parent)
    : QObject(parent)
    , m_sources(std::move(sources))
{
    m_sources.cancelled = [cancelled = m_cancelled]() { return cancelled->load(); };
    connect(&m_watcher, &QFutureWatcher<QList<SecurityCheck>>::finished, this, [this]() {
        m_checks = m_watcher.result();
        Q_EMIT changed();
    });
    run();
}

DeviceSecurity::~DeviceSecurity()
{
    // A run that's still going stops at its next module; it only reads, so it's waited for rather
    // than left behind.
    m_cancelled->store(true);
    m_watcher.waitForFinished();
}

QVariantList DeviceSecurity::checks() const
{
    QVariantList out;
    for (const SecurityCheck &check : m_checks) {
        QString result;
        switch (check.result) {
        case SecurityCheck::Result::Met:
            result = QStringLiteral("met");
            break;
        case SecurityCheck::Result::NotMet:
            result = QStringLiteral("not-met");
            break;
        case SecurityCheck::Result::Unknown:
            result = QStringLiteral("unknown");
            break;
        }
        out.append(QVariantMap {
            { QStringLiteral("id"), check.id },
            { QStringLiteral("title"), check.title },
            { QStringLiteral("result"), result },
            { QStringLiteral("explanation"), check.explanation },
        });
    }
    return out;
}

bool DeviceSecurity::allMet() const
{
    return !m_checks.isEmpty()
        && std::all_of(m_checks.cbegin(), m_checks.cend(), [](const SecurityCheck &check) { return check.result == SecurityCheck::Result::Met; });
}

void DeviceSecurity::run()
{
    if (m_watcher.isRunning()) {
        return;
    }
    m_watcher.setFuture(QtConcurrent::run(runSecurityChecks, m_sources));
    Q_EMIT changed();
}

} // namespace OrielOSSettingsPages
