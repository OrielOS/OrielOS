// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <qqmlintegration.h>

namespace OrielOSTour {

// Starts an app by its desktop entry, through KIO, so it gets an activation token and comes to the
// front, and a failure says so in a notification.
class Launcher : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    using QObject::QObject;

    Q_INVOKABLE void openApp(const QString &desktopName);
};

} // namespace OrielOSTour
