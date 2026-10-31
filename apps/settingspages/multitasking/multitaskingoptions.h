// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KConfigWatcher>
#include <KSharedConfig>

#include <QObject>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// Windows' Multitasking settings, kept in kwinrc: snapping windows by dragging them to an edge,
// the snap layouts under maximise, snap assist's suggestions after a snap, and which windows
// Alt+Tab shows. Each change is written at once and KWin is asked to read its settings again.
class MultitaskingOptions : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Dragging a window to the top maximises it, and to a side or corner snaps it there.
    Q_PROPERTY(bool snapWindows READ snapWindows WRITE setSnapWindows NOTIFY changed FINAL)
    // Resting the pointer on maximise shows the snap layouts.
    Q_PROPERTY(bool snapLayoutsOnMaximise READ snapLayoutsOnMaximise WRITE setSnapLayoutsOnMaximise NOTIFY changed FINAL)
    // After a window snaps to one half, the other half suggests the windows to fill it with.
    Q_PROPERTY(bool suggestNextSnap READ suggestNextSnap WRITE setSuggestNextSnap NOTIFY changed FINAL)
    // Alt+Tab shows the windows of every desktop, not only of the one in use.
    Q_PROPERTY(bool altTabAllDesktops READ altTabAllDesktops WRITE setAltTabAllDesktops NOTIFY changed FINAL)

public:
    explicit MultitaskingOptions(QObject *parent = nullptr);

    bool snapWindows() const;
    void setSnapWindows(bool snap);
    bool snapLayoutsOnMaximise() const;
    void setSnapLayoutsOnMaximise(bool show);
    bool suggestNextSnap() const;
    void setSuggestNextSnap(bool suggest);
    bool altTabAllDesktops() const;
    void setAltTabAllDesktops(bool all);

    // Use this configuration and call this instead of asking KWin to reconfigure. For the unit
    // tests.
    void setConfigForTesting(KSharedConfig::Ptr config, std::function<void()> reconfigure);

Q_SIGNALS:
    void changed();

private:
    void write(const QString &group, const QString &key, bool value);

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    std::function<void()> m_reconfigure;
};

} // namespace OrielOSSettingsPages
