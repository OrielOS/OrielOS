// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "dndschedule.h"

#include <KConfig>
#include <KConfigGroup>

#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QTime>

namespace OrielOSSettingsPages {

namespace {

const QString group = QStringLiteral("Schedule");
const QString timer = QStringLiteral("orielos-dnd-schedule.timer");

QString clock(int minutes)
{
    return QTime(minutes / 60, minutes % 60).toString(QStringLiteral("HH:mm"));
}

int minutes(const QString &text, int fallback)
{
    const QTime time = QTime::fromString(text, QStringLiteral("H:mm"));
    return time.isValid() ? time.hour() * 60 + time.minute() : fallback;
}

QString daysName(DndSchedule::Days days)
{
    switch (days) {
    case DndSchedule::Weekdays:
        return QStringLiteral("weekdays");
    case DndSchedule::Weekends:
        return QStringLiteral("weekends");
    case DndSchedule::EveryDay:
        break;
    }
    return QStringLiteral("daily");
}

} // namespace

DndSchedule::DndSchedule(QObject *parent)
    : QObject(parent)
{
    load();
}

QString DndSchedule::calendar(Days days, int from)
{
    const QString time = QStringLiteral("*-*-* %1:00").arg(clock(from));
    switch (days) {
    case Weekdays:
        return QStringLiteral("Mon..Fri ") + time;
    case Weekends:
        return QStringLiteral("Sat,Sun ") + time;
    case EveryDay:
        break;
    }
    return time;
}

void DndSchedule::load()
{
    const KConfig config(m_config.isEmpty() ? QStringLiteral("orielos-dndrc") : m_config, m_config.isEmpty() ? KConfig::FullConfig : KConfig::SimpleConfig);
    const KConfigGroup schedule = config.group(group);
    m_enabled = schedule.readEntry("Enabled", false);
    m_from = minutes(schedule.readEntry("From", QString()), 22 * 60);
    m_to = minutes(schedule.readEntry("To", QString()), 7 * 60);
    const QString days = schedule.readEntry("Days", QString());
    m_days = days == QLatin1String("weekdays") ? Weekdays : (days == QLatin1String("weekends") ? Weekends : EveryDay);
}

void DndSchedule::setEnabled(bool enabled)
{
    if (enabled != m_enabled) {
        m_enabled = enabled;
        save();
    }
}

void DndSchedule::setFrom(int minutes)
{
    minutes = qBound(0, minutes, 24 * 60 - 1);
    if (minutes != m_from) {
        m_from = minutes;
        save();
    }
}

void DndSchedule::setTo(int minutes)
{
    minutes = qBound(0, minutes, 24 * 60 - 1);
    if (minutes != m_to) {
        m_to = minutes;
        save();
    }
}

void DndSchedule::setDays(Days days)
{
    if (days != m_days) {
        m_days = days;
        save();
    }
}

void DndSchedule::save()
{
    KConfig config(m_config.isEmpty() ? QStringLiteral("orielos-dndrc") : m_config, m_config.isEmpty() ? KConfig::FullConfig : KConfig::SimpleConfig);
    KConfigGroup schedule = config.group(group);
    schedule.writeEntry("Enabled", m_enabled);
    schedule.writeEntry("From", clock(m_from));
    schedule.writeEntry("To", clock(m_to));
    schedule.writeEntry("Days", daysName(m_days));
    config.sync();

    // The timer starts the hours; the script, run now, covers hours that have already started.
    const QString folder = m_dropInFolder.isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/systemd/user/") + timer + QStringLiteral(".d")
        : m_dropInFolder;
    QDir().mkpath(folder);
    QFile dropIn(folder + QStringLiteral("/schedule.conf"));
    if (dropIn.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        dropIn.write(
            QStringLiteral("# Written by Settings › System › Do not disturb.\n[Timer]\nOnCalendar=\nOnCalendar=%1\n").arg(calendar(m_days, m_from)).toUtf8());
        dropIn.close();
    }
    systemctl({ QStringLiteral("daemon-reload") });
    if (m_enabled) {
        systemctl({ QStringLiteral("enable"), QStringLiteral("--now"), timer });
        systemctl({ QStringLiteral("start"), QStringLiteral("orielos-dnd-schedule.service") });
    } else {
        systemctl({ QStringLiteral("disable"), QStringLiteral("--now"), timer });
    }
    Q_EMIT changed();
}

void DndSchedule::systemctl(const QStringList &arguments) const
{
    QProcess process;
    if (m_program.isEmpty()) {
        process.start(QStringLiteral("systemctl"), QStringList { QStringLiteral("--user") } + arguments);
    } else {
        process.start(m_program, m_arguments + arguments);
    }
    process.waitForFinished(10000);
}

void DndSchedule::setForTesting(const QString &config, const QString &dropInFolder, const QString &program, const QStringList &arguments)
{
    m_config = config;
    m_dropInFolder = dropInFolder;
    m_program = program;
    m_arguments = arguments;
    load();
}

} // namespace OrielOSSettingsPages
