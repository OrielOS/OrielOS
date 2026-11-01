// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>

namespace Solid {
class Device;
}

// The USB drives and other removable drives plugged in, for the hidden icons pane's eject menu.
// Ejecting one unmounts its volumes, then ejects the disc or powers the drive off through UDisks,
// and a notification says it can be removed, or which apps still use it.
class Drives : public QObject
{
    Q_OBJECT

public:
    explicit Drives(QObject *parent = nullptr);

    // Each drive as { udi, name }.
    QVariantList list() const { return m_list; }

    void eject(const QString &udi);

Q_SIGNALS:
    void changed();

private:
    void refresh();
    // inUse: the folders of the volumes that couldn't be unmounted, empty when all were.
    void finish(const QString &udi, const QString &name, const QStringList &inUse);

    QVariantList m_list;
};
