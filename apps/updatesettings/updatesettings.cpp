// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatesettings.h"

#include <KFormat>
#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QFile>
#include <QFileInfo>
#include <QLocale>

#include <utility>

namespace OrielOSUpdates {

namespace {

QString readBootId(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromLatin1(file.readAll()).trimmed();
}

// Plasma signs out cleanly, saving the session, then restarts; bootc finishes switching to the
// staged or the previous build while the computer shuts down.
void logoutAndReboot()
{
    const QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), QStringLiteral("logoutAndReboot"));
    QDBusConnection::sessionBus().asyncCall(message);
}

QString failureText(const QString &command, const QString &detail)
{
    const QString reason = detail.isEmpty() ? i18nc("@info", "orielos-update stopped with an error.") : detail;
    if (command == QLatin1String("check-now")) {
        return i18nc("@info %1 is the reason", "Couldn't check for updates: %1", reason);
    }
    if (command == QLatin1String("rollback")) {
        return i18nc("@info %1 is the reason", "Couldn't go back to the previous version: %1", reason);
    }
    if (command == QLatin1String("remove-previous")) {
        return i18nc("@info %1 is the reason", "Couldn't remove the previous version: %1", reason);
    }
    if (command == QLatin1String("restart-at")) {
        return i18nc("@info %1 is the reason", "Couldn't schedule the restart: %1", reason);
    }
    return i18nc("@info %1 is the reason", "Couldn't change the update settings: %1", reason);
}

} // namespace

UpdateSettings::UpdateSettings(QObject *parent)
    : QObject(parent)
{
    m_environment.statePath = QStringLiteral("/var/lib/orielos/update/state.json");
    m_environment.bootIdPath = QStringLiteral("/proc/sys/kernel/random/boot_id");
    m_environment.runner = new PkexecRunner(this);
    m_environment.monitor = new SystemdCheckMonitor(this);
    m_environment.now = [] { return QDateTime::currentDateTimeUtc(); };
    m_environment.restart = logoutAndReboot;
    m_environment.changelogPath = QStringLiteral("/usr/share/doc/orielos/CHANGELOG.md");
    init();
}

UpdateSettings::UpdateSettings(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    init();
}

void UpdateSettings::init()
{
    m_bootId = readBootId(m_environment.bootIdPath);
    connect(m_environment.runner, &CommandRunner::finished, this, &UpdateSettings::onFinished);
    connect(m_environment.monitor, &CheckMonitor::runningChanged, this, &UpdateSettings::onCheckRunningChanged);

    // orielos-update replaces the file in one step, which drops it from the watch list, so the
    // folder is watched too and the file is added back after every change. The periodic read keeps
    // relative times and the end of a pause current.
    m_reloadDelay.setSingleShot(true);
    m_reloadDelay.setInterval(200);
    connect(&m_reloadDelay, &QTimer::timeout, this, &UpdateSettings::reload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reloadDelay, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reloadDelay, qOverload<>(&QTimer::start));
    m_periodicReload.setInterval(60 * 1000);
    connect(&m_periodicReload, &QTimer::timeout, this, &UpdateSettings::reload);
    m_periodicReload.start();

    m_checkStartTimer.setSingleShot(true);
    m_checkStartTimer.setInterval(m_environment.checkStartTimeout);
    connect(&m_checkStartTimer, &QTimer::timeout, this, [this] {
        endPendingCheck();
        Q_EMIT changed();
    });

    reload();
}

void UpdateSettings::watchStateFile()
{
    const QString folder = QFileInfo(m_environment.statePath).absolutePath();
    if (!m_watcher.directories().contains(folder) && QFileInfo::exists(folder)) {
        m_watcher.addPath(folder);
    }
    if (!m_watcher.files().contains(m_environment.statePath) && QFileInfo::exists(m_environment.statePath)) {
        m_watcher.addPath(m_environment.statePath);
    }
}

void UpdateSettings::reload()
{
    watchStateFile();
    m_state = UpdateState::fromFile(m_environment.statePath);
    // A new result means the check that was asked for has run, even if it ended before the unit was
    // seen running.
    if (m_checkPending && m_state.checkedAt() != m_checkedAtWhenAsked) {
        endPendingCheck();
    }
    Q_EMIT changed();
}

QDateTime UpdateSettings::now() const
{
    return m_environment.now();
}

bool UpdateSettings::isForThisBoot() const
{
    return m_state.isForThisBoot(m_bootId);
}

bool UpdateSettings::isValid() const
{
    return isForThisBoot();
}

QString UpdateSettings::headline() const
{
    if (isChecking()) {
        return i18nc("@info:status", "Checking for updates…");
    }
    return statusText(m_state, m_bootId, now());
}

QString UpdateSettings::detail() const
{
    // The messages about restarting say it all while something waits for the next restart.
    if (!isForThisBoot() || isChecking() || updateWaiting() || goingBack() || m_state.result() == QLatin1String("never-checked")) {
        return { };
    }
    return m_state.message();
}

QString UpdateSettings::lastChecked() const
{
    if (!isForThisBoot() || !m_state.checkedAt().isValid()) {
        return { };
    }
    return i18nc(
        "@info %1 is a relative date and time", "Last checked: %1", KFormat().formatRelativeDateTime(m_state.checkedAt().toLocalTime(), QLocale::ShortFormat));
}

QString UpdateSettings::runningVersion() const
{
    return isForThisBoot() ? m_state.running().version : QString();
}

bool UpdateSettings::isChecking() const
{
    return m_environment.monitor->isRunning() || m_checkPending;
}

bool UpdateSettings::updateWaiting() const
{
    return m_state.updateWaiting(m_bootId);
}

QString UpdateSettings::stagedVersion() const
{
    return updateWaiting() ? m_state.staged()->version : QString();
}

bool UpdateSettings::goingBack() const
{
    return m_state.goingBack(m_bootId);
}

bool UpdateSettings::isPaused() const
{
    return isForThisBoot() && m_state.isPaused(now());
}

QString UpdateSettings::pausedUntil() const
{
    return isPaused() ? displayDate(m_state.pausedUntil()) : QString();
}

int UpdateSettings::channel() const
{
    const Channel channel = m_pendingChannel.value_or(m_state.channel());
    return channel == Channel::Testing ? 1 : 0;
}

bool UpdateSettings::hasPrevious() const
{
    return isForThisBoot() && m_state.previous().has_value();
}

QString UpdateSettings::previousVersion() const
{
    return hasPrevious() ? m_state.previous()->version : QString();
}

QString UpdateSettings::previousAvailableUntil() const
{
    if (!hasPrevious() || !m_state.previousRemovedAfter().isValid()) {
        return { };
    }
    return displayDate(m_state.previousRemovedAfter());
}

bool UpdateSettings::canGoBack() const
{
    return m_state.canGoBack(m_bootId);
}

bool UpdateSettings::canRemovePrevious() const
{
    return m_state.canRemovePrevious(m_bootId);
}

bool UpdateSettings::appUpdates() const
{
    return m_pendingAppUpdates.value_or(m_state.appUpdates());
}

QString UpdateSettings::appsUpdated() const
{
    if (!m_state.appsUpdatedAt().isValid()) {
        return { };
    }
    return i18nc("@info %1 is a relative date and time", "Apps last updated: %1",
        KFormat().formatRelativeDateTime(m_state.appsUpdatedAt().toLocalTime(), QLocale::ShortFormat));
}

QStringList UpdateSettings::pauseChoices() const
{
    QStringList labels;
    for (const int weeks : OrielOSUpdates::pauseChoices()) {
        labels.append(pauseChoiceLabel(weeks));
    }
    return labels;
}

bool UpdateSettings::restartScheduled() const
{
    return isForThisBoot() && (updateWaiting() || goingBack()) && m_state.restartAt().isValid() && m_state.restartAt() > now();
}

QString UpdateSettings::restartAt() const
{
    if (!restartScheduled()) {
        return { };
    }
    const QDateTime local = m_state.restartAt().toLocalTime();
    const qint64 days = now().toLocalTime().date().daysTo(local.date());
    const QString time = QLocale().toString(local.time(), QLocale::ShortFormat);
    if (days == 0) {
        return i18nc("@info %1 is a time", "today at %1", time);
    }
    if (days == 1) {
        return i18nc("@info %1 is a time", "tomorrow at %1", time);
    }
    return i18nc("@info %1 is a day of the week, %2 a time", "%1 at %2", QLocale().dayName(local.date().dayOfWeek()), time);
}

QStringList UpdateSettings::restartDays() const
{
    const QDate today = now().toLocalTime().date();
    QStringList days { i18nc("@item:inlistbox", "Today"), i18nc("@item:inlistbox", "Tomorrow") };
    for (int day = 2; day < 7; ++day) {
        days.append(QLocale().dayName(today.addDays(day).dayOfWeek()));
    }
    return days;
}

QStringList UpdateSettings::hourChoices() const
{
    QStringList hours;
    for (int hour = 0; hour < 24; ++hour) {
        hours.append(QLocale().toString(QTime(hour, 0), QLocale::ShortFormat));
    }
    return hours;
}

QVariantList UpdateSettings::history() const
{
    QVariantList out;
    for (const HistoryEntry &entry : m_state.history()) {
        out.append(QVariantMap { { QStringLiteral("version"), entry.version }, { QStringLiteral("date"), displayDate(entry.startedAt) } });
    }
    return out;
}

QString UpdateSettings::whatsNew() const
{
    QFile file(m_environment.changelogPath);
    if (m_environment.changelogPath.isEmpty() || !file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return changelogSection(QString::fromUtf8(file.readAll()), m_state.running().version);
}

void UpdateSettings::run(const QStringList &arguments)
{
    m_busy = true;
    m_error.clear();
    Q_EMIT changed();
    m_environment.runner->run(arguments);
}

void UpdateSettings::checkForUpdates()
{
    if (m_busy || isChecking()) {
        return;
    }
    // "Checking" shows at once; the check unit takes over once it starts.
    m_checkPending = true;
    m_checkedAtWhenAsked = m_state.checkedAt();
    m_checkStartTimer.start();
    run({ QStringLiteral("check-now") });
}

void UpdateSettings::pause(int weeks)
{
    if (m_busy || weeks < OrielOSUpdates::minPauseWeeks || weeks > maxPauseWeeks) {
        return;
    }
    run({ QStringLiteral("pause"), QString::number(weeks) });
}

void UpdateSettings::resume()
{
    if (m_busy || !isPaused()) {
        return;
    }
    run({ QStringLiteral("resume") });
}

void UpdateSettings::setChannel(int channel)
{
    if (m_busy || (channel != 0 && channel != 1)) {
        return;
    }
    const Channel chosen = channel == 1 ? Channel::Testing : Channel::Stable;
    if (chosen == m_state.channel()) {
        return;
    }
    m_pendingChannel = chosen;
    run({ QStringLiteral("channel"), channelName(chosen) });
}

void UpdateSettings::goBack()
{
    if (m_busy || !canGoBack()) {
        return;
    }
    run({ QStringLiteral("rollback") });
}

void UpdateSettings::removePrevious()
{
    if (m_busy || !canRemovePrevious()) {
        return;
    }
    run({ QStringLiteral("remove-previous") });
}

void UpdateSettings::setAppUpdates(bool on)
{
    if (m_busy || on == m_state.appUpdates()) {
        return;
    }
    m_pendingAppUpdates = on;
    run({ QStringLiteral("app-updates"), on ? QStringLiteral("on") : QStringLiteral("off") });
}

void UpdateSettings::scheduleRestart(int day, int hour, int minute)
{
    if (m_busy || !(updateWaiting() || goingBack()) || day < 0 || day > 6 || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return;
    }
    const QDateTime when(now().toLocalTime().date().addDays(day), QTime(hour, minute));
    run({ QStringLiteral("restart-at"), when.toUTC().toString(Qt::ISODate) });
}

void UpdateSettings::cancelRestart()
{
    if (m_busy || !restartScheduled()) {
        return;
    }
    run({ QStringLiteral("restart-at"), QStringLiteral("cancel") });
}

void UpdateSettings::setActiveHours(int start, int end)
{
    if (m_busy || start < 0 || start > 23 || end < 0 || end > 23 || start == end
        || (start == m_state.activeHoursStart() && end == m_state.activeHoursEnd())) {
        return;
    }
    run({ QStringLiteral("active-hours"), QString::number(start), QString::number(end) });
}

void UpdateSettings::setAutoRestart(bool on)
{
    if (m_busy || on == m_state.autoRestart()) {
        return;
    }
    run({ QStringLiteral("auto-restart"), on ? QStringLiteral("on") : QStringLiteral("off") });
}

void UpdateSettings::restart()
{
    m_environment.restart();
}

void UpdateSettings::clearError()
{
    if (!m_error.isEmpty()) {
        m_error.clear();
        Q_EMIT changed();
    }
}

void UpdateSettings::onFinished(const QStringList &arguments, CommandRunner::Outcome outcome, const QString &detail)
{
    const QString command = arguments.value(0);
    m_busy = false;
    m_pendingChannel.reset();
    m_pendingAppUpdates.reset();
    if (command == QLatin1String("check-now") && outcome != CommandRunner::Outcome::Succeeded) {
        endPendingCheck();
    }
    if (outcome == CommandRunner::Outcome::Failed) {
        m_error = failureText(command, detail);
    }
    // orielos-update has written the state by now; don't wait for the file watcher.
    reload();
}

void UpdateSettings::onCheckRunningChanged()
{
    if (m_environment.monitor->isRunning()) {
        // From here on the unit says whether the check is running.
        endPendingCheck();
        Q_EMIT changed();
    } else {
        // The check writes its result as it ends.
        reload();
    }
}

void UpdateSettings::endPendingCheck()
{
    m_checkPending = false;
    m_checkStartTimer.stop();
}

} // namespace OrielOSUpdates
