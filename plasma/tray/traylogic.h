// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QStringList>

// Which apps' icons the tray shows on the taskbar and which in the hidden icons pane. An icon
// shows on the taskbar when the user put it there (its id is in `shown`, in that order) and its
// app doesn't mark it passive; every other icon is in the pane, in the order the apps started.
namespace Tray
{

struct Split {
    QStringList taskbar;
    QStringList pane;
};

Split split(const QStringList &present, const QStringList &passive, const QStringList &shown);

// `shown` with `id` moved or added to position `index` (clamped), for an icon dropped on the taskbar.
QStringList showAt(const QStringList &shown, const QString &id, int index);

// `shown` without `id`, for an icon dropped in the pane.
QStringList hide(const QStringList &shown, const QString &id);

// What the eject menu calls a drive: its first volume's label, else its maker and model, else
// Solid's description of it.
QString driveName(const QString &label, const QString &vendor, const QString &product, const QString &description);

} // namespace Tray
