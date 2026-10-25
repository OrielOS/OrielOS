// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QString>

#include <optional>

namespace OrielOSUpdates {

// The update channels: every channel is a tag of the same OrielOS image.
enum class Channel {
    Stable,
    Testing,
};

// A build of OrielOS, as orielos-update reports it.
struct Build
{
    QString version;
    QString digest;

    bool operator==(const Build &) const = default;
};

// The desktop's view of OrielOS updates, read from the state file that orielos-update writes
// (/var/lib/orielos/update/state.json). The update tray icon and the Update settings page both
// use it. Everything here is pure: the current time and boot ID are passed in, so the logic can be
// tested without a computer to update.
class UpdateState
{
public:
    // Parses the state file's contents. Empty, malformed or incomplete data gives an invalid state
    // rather than an error: the desktop then simply has nothing to show.
    static UpdateState fromJson(const QByteArray &json);
    static UpdateState fromFile(const QString &path);

    bool isValid() const { return m_valid; }
    QString bootId() const { return m_bootId; }
    Channel channel() const { return m_channel; }
    QString result() const { return m_result; }
    QString message() const { return m_message; }
    QDateTime checkedAt() const { return m_checkedAt; }
    // When a pause ends, or an invalid time when updates aren't paused.
    QDateTime pausedUntil() const { return m_pausedUntil; }
    Build running() const { return m_running; }
    std::optional<Build> staged() const { return m_staged; }
    // The build that going back would start, and whether it was rolled back on this computer.
    std::optional<Build> previous() const { return m_previous; }
    bool previousRejected() const { return m_previousRejected; }
    // When the previous build is removed, or an invalid time when that isn't known.
    QDateTime previousRemovedAfter() const { return m_previousRemovedAfter; }
    // Someone chose to go back: the previous build starts at the next restart.
    bool rollbackQueued() const { return m_rollbackQueued; }

    // The file describes one boot; after a restart it is stale until it is written again.
    bool isForThisBoot(const QString &currentBootId) const;
    // A build is staged for the next restart and differs from the one running.
    bool updateWaiting(const QString &currentBootId) const;
    // There is a previous build to go back to, it wasn't rolled back before, and going back isn't
    // queued already.
    bool canGoBack(const QString &currentBootId) const;
    // Going back is queued: the previous build starts at the next restart.
    bool goingBack(const QString &currentBootId) const;
    // There is a previous build, and nothing is waiting for the next restart that removing it would
    // change: orielos-update refuses while a build is staged or going back is queued.
    bool canRemovePrevious(const QString &currentBootId) const;
    // This start undid an update that failed to reach the desktop: the boot loader started the
    // previous build, which OrielOS kept. The message says which versions.
    bool updateUndone(const QString &currentBootId) const;
    bool isPaused(const QDateTime &now) const;

private:
    bool m_valid = false;
    QString m_bootId;
    Channel m_channel = Channel::Stable;
    QString m_result;
    QString m_message;
    QDateTime m_checkedAt;
    QDateTime m_pausedUntil;
    Build m_running;
    std::optional<Build> m_staged;
    std::optional<Build> m_previous;
    bool m_previousRejected = false;
    QDateTime m_previousRemovedAfter;
    bool m_rollbackQueued = false;
};

// Pauses last a whole number of weeks.
constexpr int minPauseWeeks = 1;
constexpr int maxPauseWeeks = 5;

QList<int> pauseChoices();
// A pause's length as a list entry, such as "2 weeks".
QString pauseChoiceLabel(int weeks);

// The channel's name as orielos-update takes it. An unknown name counts as stable, the default.
QString channelName(Channel channel);
Channel channelFromName(const QString &name);

// What the last check found, or what a restart will do, in one line.
QString statusText(const UpdateState &state, const QString &currentBootId, const QDateTime &now);
// How a date is shown to people, in their own locale.
QString displayDate(const QDateTime &time);

} // namespace OrielOSUpdates
