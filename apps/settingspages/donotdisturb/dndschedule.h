// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// Do not disturb at set times, as Windows' "Turn on do not disturb automatically" offers: on or
// off, the hours (from and to, in minutes after midnight) and which days they start on. Kept in
// orielos-dndrc for the dnd-schedule script; the start time goes to a drop-in for
// orielos-dnd-schedule.timer, which systemd then runs when the hours start.
class DndSchedule : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY changed FINAL)
    Q_PROPERTY(int from READ from WRITE setFrom NOTIFY changed FINAL)
    Q_PROPERTY(int to READ to WRITE setTo NOTIFY changed FINAL)
    Q_PROPERTY(Days days READ days WRITE setDays NOTIFY changed FINAL)

public:
    enum Days {
        EveryDay,
        Weekdays,
        Weekends,
    };
    Q_ENUM(Days)

    explicit DndSchedule(QObject *parent = nullptr);

    bool isEnabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    int from() const { return m_from; }
    void setFrom(int minutes);
    int to() const { return m_to; }
    void setTo(int minutes);
    Days days() const { return m_days; }
    void setDays(Days days);

    // The timer's OnCalendar= for these settings, such as "Mon..Fri *-*-* 22:00:00".
    static QString calendar(Days days, int from);

    // Keep the settings in this file and the drop-in in this folder, and run program with its
    // arguments then systemctl's instead of systemctl --user. For the unit tests.
    void setForTesting(const QString &config, const QString &dropInFolder, const QString &program, const QStringList &arguments);

Q_SIGNALS:
    void changed();

private:
    void load();
    void save();
    void systemctl(const QStringList &arguments) const;

    bool m_enabled = false;
    int m_from = 22 * 60;
    int m_to = 7 * 60;
    Days m_days = EveryDay;
    QString m_config;
    QString m_dropInFolder;
    QString m_program;
    QStringList m_arguments;
};

} // namespace OrielOSSettingsPages
