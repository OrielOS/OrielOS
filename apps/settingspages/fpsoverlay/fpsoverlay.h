// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The FPS overlay page's model. /usr/libexec/orielos/fps-overlay holds the logic; this runs it and
// shows what its status says. The unit tests point it at a stand-in program.
class FpsOverlay : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // The overlay is on: games started from the next sign-in load it.
    Q_PROPERTY(bool enabled READ isEnabled NOTIFY changed)
    Q_PROPERTY(bool frameTime READ frameTime NOTIFY changed)
    Q_PROPERTY(bool stats READ stats NOTIFY changed)
    // Steam from the Store is installed and needs the overlay's add-on to show it.
    Q_PROPERTY(bool steamNeedsAddon READ steamNeedsAddon NOTIFY changed)
    // A change, or the add-on's install, is running.
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    // What went wrong with the last change, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit FpsOverlay(QObject *parent = nullptr);
    // For the tests: another program in place of fps-overlay.
    FpsOverlay(const QString &program, QObject *parent);

    bool isEnabled() const { return m_enabled; }
    bool frameTime() const { return m_frameTime; }
    bool stats() const { return m_stats; }
    bool steamNeedsAddon() const { return m_steam == QLatin1String("needs-addon"); }
    bool isBusy() const { return m_busy; }
    QString error() const { return m_error; }

    Q_INVOKABLE void setEnabled(bool on);
    Q_INVOKABLE void setFrameTime(bool on);
    Q_INVOKABLE void setStats(bool on);
    Q_INVOKABLE void installSteamAddon();
    Q_INVOKABLE void reload();

    // Parses fps-overlay's status: key=value lines.
    void readStatus(const QString &status);

Q_SIGNALS:
    void changed();

private:
    void run(const QStringList &arguments);

    QString m_program;
    bool m_enabled = false;
    bool m_frameTime = false;
    bool m_stats = false;
    QString m_steam;
    bool m_busy = false;
    QString m_error;
};

} // namespace OrielOSSettingsPages
