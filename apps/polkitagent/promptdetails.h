// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QMap>
#include <QString>

// What an administrator prompt says about the request, worked out from what polkit passes the
// agent, as Windows' prompt lays it out: the app's name, its publisher and where the program is.
struct PromptDetails
{
    // The app or the action, in a line of its own.
    QString name;
    // Who made it, empty when unknown.
    QString publisher;
    // Whether the publisher is known: programs and actions that come with OrielOS are, being part
    // of its signed image; a program anywhere else isn't.
    bool verified = false;
    // The program's path, for Show more details; empty for an action that isn't a program.
    QString program;
    QString commandLine;

    // From the action's ID and description, its vendor (from its policy file), polkit's message
    // and its details. Older polkit passes pkexec's program and command line as details; newer
    // polkit passes only the message, which names the program between ` and '.
    static PromptDetails from(
        const QString &actionId, const QString &description, const QString &vendor, const QString &message, const QMap<QString, QString> &details);
};
