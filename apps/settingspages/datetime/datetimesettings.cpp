// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "datetimesettings.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFileInfo>
#include <QLocale>
#include <QPointer>
#include <QProcess>
#include <QTimeZone>

#include <cstdlib>
#include <limits>

using namespace std::chrono_literals;

namespace OrielOSSettingsPages {

namespace {

const QString timedateService = QStringLiteral("org.freedesktop.timedate1");
const QString timedatePath = QStringLiteral("/org/freedesktop/timedate1");
const QString timedateInterface = QStringLiteral("org.freedesktop.timedate1");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

constexpr auto autoTimeZoneTool = "/usr/libexec/orielos/auto-timezone";
constexpr auto timeSyncTool = "/usr/libexec/orielos/time-sync";
// pkexec exits with these when the password prompt is dismissed or the user isn't allowed.
constexpr int pkexecDismissed = 126;
constexpr int pkexecNotAuthorised = 127;
constexpr auto refreshInterval = 30s;

// The reference IDs chronyd shows when it follows no server: none, or the PC's own clock.
constexpr auto noReference = "00000000";
constexpr auto localReference = "7F7F0101";

bool isPkexecDismissed(int exitCode)
{
    return exitCode == pkexecDismissed || exitCode == pkexecNotAuthorised;
}

// timedated answers these when polkit's prompt was dismissed or the user isn't allowed.
bool isDBusDismissed(const QString &errorName)
{
    return errorName == QLatin1String("org.freedesktop.DBus.Error.AccessDenied")
        || errorName == QLatin1String("org.freedesktop.DBus.Error.InteractiveAuthorizationRequired");
}

// The helpers start their messages with their own name, which means nothing on the page.
QString reasonFrom(const QString &detail, const char *tool)
{
    const QString prefix = QString::fromLatin1(tool).section(QLatin1Char('/'), -1) + QLatin1String(": ");
    return detail.startsWith(prefix) ? detail.mid(prefix.size()) : detail;
}

// Runs a program, with pkexec in front for the helpers, where polkit decides who may and asks for a
// password.
void runProgram(const QString &program, const QStringList &arguments, std::function<void(int exitCode, const QByteArray &output, const QString &detail)> done)
{
    auto *process = new QProcess;
    QObject::connect(process, &QProcess::finished, process, [process, done](int exitCode, QProcess::ExitStatus status) {
        const QByteArray output = process->readAllStandardOutput();
        const QString detail = QString::fromLocal8Bit(process->readAllStandardError()).section(QLatin1Char('\n'), 0, 0).trimmed();
        process->deleteLater();
        done(status == QProcess::NormalExit ? exitCode : 1, output, detail);
    });
    QObject::connect(process, &QProcess::errorOccurred, process, [process, program, done](QProcess::ProcessError error) {
        // Other errors end in finished() above.
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            done(1, { }, i18nc("@info %1 is a program's name", "%1 couldn't be started.", program));
        }
    });
    process->start(program, arguments);
}

void readTimedated(std::function<void(const ClockState &state)> done)
{
    QDBusMessage message = QDBusMessage::createMethodCall(timedateService, timedatePath, propertiesInterface, QStringLiteral("GetAll"));
    message << timedateInterface;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message));
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, watcher, [watcher, done]() {
        watcher->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *watcher;
        ClockState state;
        if (!reply.isError()) {
            const QVariantMap properties = reply.value();
            state.valid = true;
            state.ntp = properties.value(QStringLiteral("NTP")).toBool();
            state.canNtp = properties.value(QStringLiteral("CanNTP")).toBool();
            state.timeZone = properties.value(QStringLiteral("Timezone")).toString();
        }
        done(state);
    });
}

// timedated starts or stops chronyd and enables or disables it; polkit asks for a password.
void setTimedatedNtp(bool enable, std::function<void(const QString &errorName, const QString &errorMessage)> done)
{
    QDBusMessage message = QDBusMessage::createMethodCall(timedateService, timedatePath, timedateInterface, QStringLiteral("SetNTP"));
    message << enable << true;
    message.setInteractiveAuthorizationAllowed(true);
    // polkit's prompt waits for the user, for as long as they take.
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, std::numeric_limits<int>::max()));
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, watcher, [watcher, done]() {
        watcher->deleteLater();
        const QDBusError error = watcher->error();
        done(watcher->isError() ? error.name() : QString(), watcher->isError() ? error.message() : QString());
    });
}

QDateTime currentTime()
{
    return QDateTime::currentDateTime();
}

// "UTC", "UTC+1", "UTC−5" or "UTC+5:30".
QString offsetText(int seconds)
{
    if (seconds == 0) {
        return QStringLiteral("UTC");
    }
    const int minutes = std::abs(seconds) / 60;
    QString text = QStringLiteral("UTC") + (seconds < 0 ? QChar(0x2212) : QLatin1Char('+')) + QString::number(minutes / 60);
    if (minutes % 60 != 0) {
        text += QLatin1Char(':') + QStringLiteral("%1").arg(minutes % 60, 2, 10, QLatin1Char('0'));
    }
    return text;
}

} // namespace

SyncStatus SyncStatus::parse(const QByteArray &csv)
{
    SyncStatus status;
    const QStringList fields = QString::fromUtf8(csv).section(QLatin1Char('\n'), 0, 0).trimmed().split(QLatin1Char(','));
    if (fields.size() < 4) {
        return status;
    }
    const QString referenceId = fields.at(0).toUpper();
    bool isHex = false;
    referenceId.toUInt(&isHex, 16);
    bool isTime = false;
    const double referenceTime = fields.at(3).toDouble(&isTime);
    if (referenceId.size() != 8 || !isHex || !isTime) {
        return status;
    }
    status.valid = true;
    const bool notSynchronised = fields.size() >= 14 && fields.at(13) == QLatin1String("Not synchronised");
    status.synchronised = referenceTime > 0 && referenceId != QLatin1String(noReference) && referenceId != QLatin1String(localReference) && !notSynchronised;
    if (status.synchronised) {
        // chronyc shows "?" when it can't name the server.
        const QString server = fields.at(1).trimmed();
        status.server = server == QLatin1String("?") ? QString() : server;
        status.lastMeasurement = QDateTime::fromMSecsSinceEpoch(qint64(referenceTime * 1000), QTimeZone::UTC);
    }
    return status;
}

DateTimeSettings::DateTimeSettings(QObject *parent)
    : DateTimeSettings(Environment { QStringLiteral("/etc/orielos/auto-timezone"), runProgram, readTimedated, setTimedatedNtp, currentTime }, parent)
{
    // Plasma's clock settings, the auto-timezone service or anything else may change the clock too.
    QDBusConnection::systemBus().connect(timedateService, timedatePath, propertiesInterface, QStringLiteral("PropertiesChanged"), this, SLOT(reloadClock()));
}

DateTimeSettings::DateTimeSettings(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    init();
}

void DateTimeSettings::init()
{
    m_tick.setSingleShot(true);
    m_tick.setTimerType(Qt::PreciseTimer);
    connect(&m_tick, &QTimer::timeout, this, [this]() {
        Q_EMIT clockTicked();
        scheduleTick();
    });
    // timedated says when the clock changes; chronyd and the time zone setting don't.
    m_refresh.setInterval(refreshInterval);
    connect(&m_refresh, &QTimer::timeout, this, [this]() {
        readAutoTimeZone();
        readSyncStatus();
    });
    m_refresh.start();
    reload();
    scheduleTick();
}

void DateTimeSettings::scheduleTick()
{
    m_tick.start(1000 - m_environment.now().time().msec() + 5);
}

void DateTimeSettings::reload()
{
    reloadClock();
    readAutoTimeZone();
    readSyncStatus();
}

void DateTimeSettings::reloadClock()
{
    m_environment.readClock([self = QPointer<DateTimeSettings>(this)](const ClockState &state) {
        if (!self) {
            return;
        }
        self->m_clock = state;
        Q_EMIT self->changed();
        Q_EMIT self->clockTicked();
    });
}

void DateTimeSettings::readAutoTimeZone()
{
    const bool on = QFileInfo::exists(m_environment.autoTimeZonePath);
    if (on != m_autoTimeZone) {
        m_autoTimeZone = on;
        Q_EMIT changed();
    }
}

void DateTimeSettings::readSyncStatus()
{
    // -c gives one line of fields; -N names the server as chrony's settings do, such as a pool's
    // name, rather than by its address. chronyc asks chronyd over its local port, without root.
    m_environment.run(QStringLiteral("chronyc"), { QStringLiteral("-c"), QStringLiteral("-N"), QStringLiteral("tracking") },
        [self = QPointer<DateTimeSettings>(this)](int exitCode, const QByteArray &output, const QString &) {
            if (!self) {
                return;
            }
            self->m_syncStatus = exitCode == 0 ? SyncStatus::parse(output) : SyncStatus { };
            Q_EMIT self->changed();
        });
}

QDateTime DateTimeSettings::localNow() const
{
    const QTimeZone zone(m_clock.timeZone.toUtf8());
    return m_environment.now().toTimeZone(zone.isValid() ? zone : QTimeZone::systemTimeZone());
}

QString DateTimeSettings::time() const
{
    const QLocale locale;
    // The user's short time format, with the seconds after the minutes, the way the format
    // separates the hours from the minutes.
    QString format = locale.timeFormat(QLocale::ShortFormat);
    const qsizetype minutes = format.indexOf(QLatin1String("mm"));
    if (minutes >= 0 && !format.contains(QLatin1Char('s'))) {
        const QChar separator = minutes > 0 && !format.at(minutes - 1).isLetter() ? format.at(minutes - 1) : QLatin1Char(':');
        format.insert(minutes + 2, QStringLiteral("%1ss").arg(separator));
    }
    return locale.toString(localNow().time(), format);
}

QString DateTimeSettings::date() const
{
    return QLocale().toString(localNow().date(), QLocale::LongFormat);
}

QString DateTimeSettings::timeZone() const
{
    const QDateTime now = localNow();
    QString name = m_clock.timeZone.isEmpty() ? QString::fromUtf8(now.timeZone().id()) : m_clock.timeZone;
    name.replace(QLatin1Char('_'), QLatin1Char(' '));
    // Etc/UTC and its kind are only an offset, which needn't show twice.
    if (name.startsWith(QLatin1String("Etc/"))) {
        name = name.mid(4);
    }
    if (name == offsetText(now.offsetFromUtc())) {
        return name;
    }
    return i18nc(
        "@info %1 is a time zone, such as Europe/London; %2 its difference from UTC now, such as UTC+1", "%1 (%2)", name, offsetText(now.offsetFromUtc()));
}

bool DateTimeSettings::canChangeAutoTime() const
{
    return m_clock.valid && m_clock.canNtp && m_pendingAutoTime < 0;
}

bool DateTimeSettings::canSync() const
{
    return m_clock.ntp && m_pendingAutoTime < 0 && !m_syncing;
}

QString DateTimeSettings::lastSync() const
{
    if (!m_syncStatus.valid) {
        return i18nc("@info When the clock was last synchronised", "Not known, as network time isn't running");
    }
    if (!m_syncStatus.synchronised) {
        return i18nc("@info When the clock was last synchronised", "Not synchronised yet");
    }
    const QLocale locale;
    const QDateTime now = localNow();
    const QDateTime when = m_syncStatus.lastMeasurement.toTimeZone(now.timeZone());
    if (when.date() == now.date()) {
        const QString time = locale.toString(when.time(), QLocale::ShortFormat);
        return m_syncStatus.server.isEmpty()
            ? i18nc("@info When the clock was last synchronised; %1 is a time", "Today at %1", time)
            : i18nc("@info When the clock was last synchronised; %1 is a time, %2 a time server", "Today at %1, with %2", time, m_syncStatus.server);
    }
    const QString dateTime = locale.toString(when, QLocale::ShortFormat);
    return m_syncStatus.server.isEmpty()
        ? dateTime
        : i18nc("@info When the clock was last synchronised; %1 is a date and time, %2 a time server", "%1, with %2", dateTime, m_syncStatus.server);
}

void DateTimeSettings::setAutoTime(bool on)
{
    if (!canChangeAutoTime() || on == autoTime()) {
        return;
    }
    m_pendingAutoTime = on ? 1 : 0;
    m_error.clear();
    Q_EMIT changed();
    m_environment.setNtp(on, [self = QPointer<DateTimeSettings>(this), on](const QString &errorName, const QString &errorMessage) {
        if (!self) {
            return;
        }
        self->m_pendingAutoTime = -1;
        if (errorName.isEmpty()) {
            // timedated has started or stopped chronyd: show the new state until the next read
            // says what it is, rather than the old one in between.
            self->m_clock.ntp = on;
            self->m_syncResult.clear();
            self->m_syncFailed = false;
        } else if (!isDBusDismissed(errorName)) {
            const QString reason = errorName == QLatin1String("org.freedesktop.timedate1.NoNTPSupport")
                ? i18nc("@info", "no network time service is installed.")
                : (errorMessage.isEmpty() ? i18nc("@info", "the clock service refused.") : errorMessage);
            self->m_error = on ? i18nc("@info %1 is the reason", "Couldn't turn on setting the time automatically: %1", reason)
                               : i18nc("@info %1 is the reason", "Couldn't turn off setting the time automatically: %1", reason);
        }
        Q_EMIT self->changed();
        self->reloadClock();
        self->readSyncStatus();
    });
}

void DateTimeSettings::setAutoTimeZone(bool on)
{
    if (!canChangeAutoTimeZone() || on == autoTimeZone()) {
        return;
    }
    m_pendingAutoTimeZone = on ? 1 : 0;
    m_error.clear();
    Q_EMIT changed();
    // Turning it on also sets the time zone at once, which may take a few seconds. The command goes
    // on if the page closes meanwhile.
    m_environment.run(QStringLiteral("pkexec"), { QLatin1String(autoTimeZoneTool), on ? QStringLiteral("on") : QStringLiteral("off") },
        [self = QPointer<DateTimeSettings>(this), on](int exitCode, const QByteArray &, const QString &detail) {
            if (!self) {
                return;
            }
            self->m_pendingAutoTimeZone = -1;
            if (exitCode != 0 && !isPkexecDismissed(exitCode)) {
                const QString reason = detail.isEmpty() ? i18nc("@info", "auto-timezone stopped with an error.") : reasonFrom(detail, autoTimeZoneTool);
                self->m_error = on ? i18nc("@info %1 is the reason", "Couldn't turn on setting the time zone automatically: %1", reason)
                                   : i18nc("@info %1 is the reason", "Couldn't turn off setting the time zone automatically: %1", reason);
            }
            self->readAutoTimeZone();
            Q_EMIT self->changed();
            // The time zone may have changed.
            self->reloadClock();
        });
}

void DateTimeSettings::syncNow()
{
    if (!canSync()) {
        return;
    }
    m_syncing = true;
    m_syncResult.clear();
    m_syncFailed = false;
    Q_EMIT changed();
    m_environment.run(QStringLiteral("pkexec"), { QLatin1String(timeSyncTool) },
        [self = QPointer<DateTimeSettings>(this)](int exitCode, const QByteArray &, const QString &detail) {
            if (!self) {
                return;
            }
            self->m_syncing = false;
            if (exitCode == 0) {
                self->m_syncResult = i18nc("@info The clock was synchronised", "Synchronised");
            } else if (!isPkexecDismissed(exitCode)) {
                const QString reason = detail.isEmpty() ? i18nc("@info", "time-sync stopped with an error.") : reasonFrom(detail, timeSyncTool);
                self->m_syncResult = i18nc("@info %1 is the reason", "Couldn't synchronise: %1", reason);
                self->m_syncFailed = true;
            }
            Q_EMIT self->changed();
            self->readSyncStatus();
            Q_EMIT self->clockTicked();
        });
}

} // namespace OrielOSSettingsPages
