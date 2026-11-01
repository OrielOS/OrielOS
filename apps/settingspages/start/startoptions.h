// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "shellsettings.h"

#include <QObject>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// What Start shows under Recommended: recently added apps and recently opened files. Changes go
// to the Start menu on the taskbar straight away.
class StartOptions : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ isReady NOTIFY changed)
    // Whether the taskbar has OrielOS's Start menu to change.
    Q_PROPERTY(bool available READ isAvailable NOTIFY changed)
    Q_PROPERTY(bool showRecentlyAdded READ showRecentlyAdded WRITE setShowRecentlyAdded NOTIFY changed)
    Q_PROPERTY(bool showRecentFiles READ showRecentFiles WRITE setShowRecentFiles NOTIFY changed)
    // The shortcuts next to the power button, by ID.
    Q_PROPERTY(QStringList folders READ folders NOTIFY changed)
    // 0 more pins, 1 the default, 2 more recommendations.
    Q_PROPERTY(int layout READ layout WRITE setLayout NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit StartOptions(QObject *parent = nullptr);
    // Uses these settings instead of the desktop's. For the unit tests.
    explicit StartOptions(ShellSettings *settings, QObject *parent = nullptr);

    bool isReady() const { return m_settings->isReady(); }
    bool isAvailable() const { return m_settings->state().hasStart; }
    bool showRecentlyAdded() const { return m_settings->state().showRecentlyAdded; }
    void setShowRecentlyAdded(bool show);
    bool showRecentFiles() const { return m_settings->state().showRecentFiles; }
    void setShowRecentFiles(bool show);
    QStringList folders() const { return m_settings->state().startFolders; }
    Q_INVOKABLE void setFolder(const QString &id, bool shown);
    int layout() const;
    void setLayout(int layout);
    QString error() const { return m_settings->error(); }

Q_SIGNALS:
    void changed();

private:
    ShellSettings *m_settings;
};

} // namespace OrielOSSettingsPages
