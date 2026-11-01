// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "clipboardhistory.h"

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QGuiApplication>

namespace {
const QString Service = QStringLiteral("org.kde.klipper");
const QString Path = QStringLiteral("/klipper");
const QString Interface = QStringLiteral("org.kde.klipper.klipper");
// As many items as the panel lists.
constexpr int MostItems = 25;
} // namespace

ClipboardHistory::ClipboardHistory(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().connect(Service, Path, Interface, QStringLiteral("clipboardHistoryUpdated"), this, SLOT(refresh()));
    refresh();
}

void ClipboardHistory::refresh()
{
    const QDBusMessage message = QDBusMessage::createMethodCall(Service, Path, Interface, QStringLiteral("getClipboardHistoryMenu"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        watcher->deleteLater();
        const QDBusPendingReply<QStringList> reply = *watcher;
        m_available = !reply.isError();
        m_items.clear();
        if (m_available) {
            // Klipper names a picture or files with a placeholder, which can't be copied as text.
            for (const QString &item : reply.value()) {
                if (!item.trimmed().isEmpty() && m_items.size() < MostItems) {
                    m_items.append(item);
                }
            }
        }
        Q_EMIT itemsChanged();
    });
}

void ClipboardHistory::copy(const QString &text)
{
    QGuiApplication::clipboard()->setText(text);
}
