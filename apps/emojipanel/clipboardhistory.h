// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <qqmlintegration.h>

// The emoji panel's clipboard: the text items in the clipboard history the desktop keeps (Plasma's
// Klipper, in the system tray's Clipboard), newest first, and copying a picked item. copy() puts
// text on the clipboard; the desktop's history keeps it once the panel has closed.
class ClipboardHistory : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QStringList items READ items NOTIFY itemsChanged)
    // False when the desktop keeps no history (Klipper isn't running).
    Q_PROPERTY(bool available READ available NOTIFY itemsChanged)

public:
    explicit ClipboardHistory(QObject *parent = nullptr);

    QStringList items() const { return m_items; }
    bool available() const { return m_available; }

    Q_INVOKABLE void copy(const QString &text);

public Q_SLOTS:
    void refresh();

Q_SIGNALS:
    void itemsChanged();

private:
    QStringList m_items;
    bool m_available = false;
};
