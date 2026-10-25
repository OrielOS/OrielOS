// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatestate.h"

#include <KLocalizedString>

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>

namespace UpdateNotifier {

namespace {

// The state file writes UTC times as ISO 8601 with a Z, or null.
QDateTime parseTime(const QJsonValue &value)
{
    if (!value.isString()) {
        return { };
    }
    QDateTime time = QDateTime::fromString(value.toString(), Qt::ISODate);
    return time.isValid() ? time.toUTC() : QDateTime();
}

std::optional<Build> parseBuild(const QJsonValue &value)
{
    if (!value.isObject()) {
        return std::nullopt;
    }
    const QJsonObject object = value.toObject();
    const QString digest = object.value(QLatin1String("digest")).toString();
    if (digest.isEmpty()) {
        return std::nullopt;
    }
    return Build { object.value(QLatin1String("version")).toString(), digest };
}

} // namespace

UpdateState UpdateState::fromJson(const QByteArray &json)
{
    UpdateState state;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(json, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        return state;
    }
    const QJsonObject object = document.object();
    const std::optional<Build> running = parseBuild(object.value(QLatin1String("running")));
    const QString bootId = object.value(QLatin1String("bootId")).toString();
    const QString result = object.value(QLatin1String("result")).toString();
    // Without these the state can't say anything about this computer.
    if (!running || bootId.isEmpty() || result.isEmpty()) {
        return state;
    }

    state.m_valid = true;
    state.m_bootId = bootId;
    state.m_channel = channelFromName(object.value(QLatin1String("channel")).toString());
    state.m_result = result;
    state.m_message = object.value(QLatin1String("message")).toString();
    state.m_checkedAt = parseTime(object.value(QLatin1String("checkedAt")));
    state.m_pausedUntil = parseTime(object.value(QLatin1String("pausedUntil")));
    state.m_running = *running;
    state.m_staged = parseBuild(object.value(QLatin1String("staged")));
    const QJsonValue previous = object.value(QLatin1String("previous"));
    state.m_previous = parseBuild(previous);
    state.m_previousRejected = previous.toObject().value(QLatin1String("rejected")).toBool();
    state.m_rollbackQueued = object.value(QLatin1String("rollbackQueued")).toBool();
    return state;
}

UpdateState UpdateState::fromFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return fromJson(file.readAll());
}

bool UpdateState::isForThisBoot(const QString &currentBootId) const
{
    return m_valid && !currentBootId.isEmpty() && m_bootId == currentBootId;
}

bool UpdateState::updateWaiting(const QString &currentBootId) const
{
    // Going back drops a staged build, so it can't be waiting at the same time.
    return isForThisBoot(currentBootId) && !m_rollbackQueued && m_staged && m_staged->digest != m_running.digest;
}

bool UpdateState::canGoBack(const QString &currentBootId) const
{
    return isForThisBoot(currentBootId) && m_previous && !m_previousRejected && !m_rollbackQueued;
}

bool UpdateState::goingBack(const QString &currentBootId) const
{
    return isForThisBoot(currentBootId) && m_rollbackQueued && m_previous;
}

bool UpdateState::isPaused(const QDateTime &now) const
{
    return m_valid && m_pausedUntil.isValid() && m_pausedUntil > now;
}

QList<int> pauseChoices()
{
    QList<int> choices;
    for (int weeks = minPauseWeeks; weeks <= maxPauseWeeks; ++weeks) {
        choices.append(weeks);
    }
    return choices;
}

QString pauseChoiceLabel(int weeks)
{
    return i18ncp("@action:inmenu How long to pause updates for", "Pause for %1 week", "Pause for %1 weeks", weeks);
}

QString channelName(Channel channel)
{
    switch (channel) {
    case Channel::Testing:
        return QStringLiteral("testing");
    case Channel::Stable:
        break;
    }
    return QStringLiteral("stable");
}

QString channelLabel(Channel channel)
{
    switch (channel) {
    case Channel::Testing:
        return i18nc("@option:radio Update channel", "Testing: new builds sooner, less tested");
    case Channel::Stable:
        break;
    }
    return i18nc("@option:radio Update channel", "Stable (recommended)");
}

Channel channelFromName(const QString &name)
{
    return name == QLatin1String("testing") ? Channel::Testing : Channel::Stable;
}

QString displayDate(const QDateTime &time)
{
    return QLocale().toString(time.toLocalTime().date(), QLocale::LongFormat);
}

QString statusText(const UpdateState &state, const QString &currentBootId, const QDateTime &now)
{
    if (state.goingBack(currentBootId)) {
        return i18nc("@info:tooltip", "Restart to go back to OrielOS %1", state.previous()->version);
    }
    if (state.updateWaiting(currentBootId)) {
        return i18nc("@info:tooltip", "Restart to finish updating to OrielOS %1", state.staged()->version);
    }
    if (state.isPaused(now)) {
        return i18nc("@info:tooltip %1 is a date", "Updates are paused until %1", displayDate(state.pausedUntil()));
    }
    // A state written before the last restart says nothing reliable about now.
    if (!state.isForThisBoot(currentBootId)) {
        return i18nc("@info:tooltip", "Not checked for updates yet");
    }
    const QString result = state.result();
    if (result == QLatin1String("up-to-date") || result == QLatin1String("rejected") || result == QLatin1String("staged")
        || result == QLatin1String("rollback-queued")) {
        return i18nc("@info:tooltip", "OrielOS is up to date");
    }
    if (result == QLatin1String("metered")) {
        return i18nc("@info:tooltip", "Updates are skipped on a metered connection");
    }
    if (result == QLatin1String("unreachable") || result == QLatin1String("error")) {
        return i18nc("@info:tooltip", "Couldn't check for updates");
    }
    return i18nc("@info:tooltip", "Not checked for updates yet");
}

} // namespace UpdateNotifier
