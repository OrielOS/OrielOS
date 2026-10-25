// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QString>

#include <optional>

namespace UpdateNotifier {

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
// (/var/lib/orielos/update/state.json). Everything here is pure: the current time and boot ID are
// passed in, so the logic can be tested without a computer to update.
class UpdateState
{
public:
    // Parses the state file's contents. Empty, malformed or incomplete data gives an invalid state
    // rather than an error: the notifier then simply has nothing to show.
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

    // The file describes one boot; after a restart it is stale until it is written again.
    bool isForThisBoot(const QString &currentBootId) const;
    // A build is staged for the next restart and differs from the one running.
    bool updateWaiting(const QString &currentBootId) const;
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
};

// Pauses last a whole number of weeks, as on Windows.
constexpr int minPauseWeeks = 1;
constexpr int maxPauseWeeks = 5;

QList<int> pauseChoices();
QString pauseChoiceLabel(int weeks);

// The channel's name as orielos-update takes it, and as people read it in the menu.
QString channelName(Channel channel);
QString channelLabel(Channel channel);
// An unknown name counts as stable, the default.
Channel channelFromName(const QString &name);

// The tray icon's tooltip for the current state.
QString statusText(const UpdateState &state, const QString &currentBootId, const QDateTime &now);
// How a date is shown to people, in their own locale.
QString displayDate(const QDateTime &time);

} // namespace UpdateNotifier
